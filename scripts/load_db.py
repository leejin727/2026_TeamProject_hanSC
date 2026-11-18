"""원본 xlsx와 data/extra CSV를 PostgreSQL에 넣는다.

실행 (저장소 최상위에서, PostgreSQL이 켜져 있어야 함):
    source .venv/bin/activate
    python scripts/load_db.py

- 필요한 패키지: scripts/requirements.txt + backend/requirements.txt
- 접속 주소는 .env의 DATABASE_URL (backend/app/config.py가 읽는다).
- 여러 번 실행해도 결과가 같다. 파일에서 오는 표는 매번 파일 내용과 똑같이 맞춘다.
- 전체가 트랜잭션 하나다. 중간에 실패하거나 검증에 걸리면 DB는 실행 전 그대로 남는다.
- 주변 인프라(nearby_facilities)와 AI 설명 캐시(ai_explanations)는 건드리지 않는다.
- 주변 시설 AI 예시(ai_facilities)는 data/extra/ai_facilities.json(scripts/generate_facilities.py가 만듦)에
  있는 역·언어만 파일 내용으로 맞춘다. 파일에 없는 것(서버가 그때그때 만든 것)은 그대로 둔다.
- 원본 data/raw/stations.xlsx는 읽기만 한다.
테이블 설명: docs/db-schema.md
"""

import json
import sys
from pathlib import Path

import pandas as pd
import psycopg
from psycopg.types.json import Jsonb

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))  # backend/app의 설정·DB 모듈을 같이 쓰기 위해

from app.ai.prompts import LANGUAGES  # noqa: E402
from app.config import MissingSettingError  # noqa: E402
from app.db.connection import connect  # noqa: E402

RAW = ROOT / "data/raw/stations.xlsx"
EXTRA = ROOT / "data/extra"
SCHEMA = ROOT / "backend/app/db/schema.sql"
FACILITIES = EXTRA / "ai_facilities.json"  # 없으면 건너뛴다

# 적재 후 반드시 맞아야 하는 개수 (validate_data.py의 EXPECTED와 같은 기준)
EXPECTED = {"역": 111, "구간": 139, "환승역": 35, "노선": 9}
EXPECTED_SQL = {
    "역": "SELECT count(*) FROM stations",
    "구간": "SELECT count(*) FROM edges",
    "환승역": "SELECT count(DISTINCT station_id) FROM transfers",
    "노선": "SELECT count(*) FROM lines",
}

# 표마다 행을 넣는 SQL.
# lines·stations는 주변 인프라 표가 가리키므로 지우지 않고 upsert한다 (있으면 고치고, 없으면 넣기).
INSERT_SQL = {
    "lines": "INSERT INTO lines (line, is_circular) VALUES (%s, %s) "
             "ON CONFLICT (line) DO UPDATE SET is_circular = EXCLUDED.is_circular",
    "stations": "INSERT INTO stations (id) VALUES (%s) ON CONFLICT (id) DO NOTHING",
    "station_names": "INSERT INTO station_names (station_id, lang, name) VALUES (%s, %s, %s)",
    "line_stations": "INSERT INTO line_stations (line, seq, station_id) VALUES (%s, %s, %s)",
    "edges": "INSERT INTO edges (station_a, station_b, travel_sec, distance_m, cost_won) "
             "VALUES (%s, %s, %s, %s, %s)",
    "transfers": "INSERT INTO transfers (station_id, line_a, line_b, transfer_sec) VALUES (%s, %s, %s, %s)",
}

# 매번 비우고 다시 채우는 표. 이 순서대로 지운다 (다른 표가 가리키는 표를 나중에).
REPLACED = ["transfers", "line_stations", "edges", "station_names"]

# 건드리지 않지만 행 수를 보여 주는 표
UNTOUCHED = ["nearby_facilities", "ai_explanations"]


class CheckFailed(Exception):
    """적재 후 검증에 실패함. 이 오류가 나면 트랜잭션 전체가 취소된다."""


def sid(value) -> str:
    """역 ID를 문자열로. 엑셀·CSV에서는 숫자(101)로 읽히므로 '101'로 바꾼다."""
    return str(int(value))


def read_files() -> dict[str, list[tuple]]:
    """파일을 읽어 표 이름 → 넣을 행 목록으로 만든다."""
    raw = pd.read_excel(RAW)
    raw.columns = ["a", "b", "sec", "meter", "won"]  # 출발역, 도착역, 시간(초), 거리(미터), 비용(원)
    edges = []
    for r in raw.itertuples():
        a, b = sorted((sid(r.a), sid(r.b)))  # 양방향이라 작은 ID를 앞에 둔다
        edges.append((a, b, int(r.sec), int(r.meter), int(r.won)))

    names = pd.read_csv(EXTRA / "station_names.csv")
    station_names = [(sid(r.station), "ko", r.name_ko) for r in names.itertuples()]
    station_names += [(sid(r.station), "en", r.name_en) for r in names.itertuples()]

    transfers = []
    for r in pd.read_csv(EXTRA / "transfers.csv").itertuples():
        line_a, line_b = sorted((int(r.line_a), int(r.line_b)))
        transfers.append((sid(r.station), line_a, line_b, int(r.transfer_sec)))

    return {
        "lines": [(int(r.line), bool(r.is_circular)) for r in pd.read_csv(EXTRA / "lines.csv").itertuples()],
        "stations": [(s,) for s in sorted({s for e in edges for s in e[:2]})],
        "station_names": station_names,
        "line_stations": [
            (int(r.line), int(r.seq), sid(r.station))
            for r in pd.read_csv(EXTRA / "line_stations.csv").itertuples()
        ],
        "edges": edges,
        "transfers": transfers,
    }


def load(conn: psycopg.Connection, rows: dict[str, list[tuple]]) -> None:
    """테이블을 만들고 파일 내용으로 채운다. (commit은 호출한 쪽의 with 블록이 한다)"""
    # ① 테이블이 없으면 만든다
    conn.execute(SCHEMA.read_text(encoding="utf-8"))

    with conn.cursor() as cur:
        # ② 파일에서 통째로 오는 표를 비운다
        for table in REPLACED:
            cur.execute(f"DELETE FROM {table}")

        # ③ 노선·역은 upsert하고, 파일에서 사라진 것만 지운다.
        #    사라진 역을 주변 인프라가 가리키고 있으면 오류가 나고 전체가 취소된다.
        cur.executemany(INSERT_SQL["lines"], rows["lines"])
        cur.executemany(INSERT_SQL["stations"], rows["stations"])
        cur.execute("DELETE FROM lines WHERE line <> ALL(%s)", ([r[0] for r in rows["lines"]],))
        cur.execute("DELETE FROM stations WHERE id <> ALL(%s)", ([r[0] for r in rows["stations"]],))

        # ④ 비웠던 표를 다시 채운다 (지운 순서의 반대: 가리키는 표를 먼저)
        for table in reversed(REPLACED):
            cur.executemany(INSERT_SQL[table], rows[table])


def read_facilities(stations: set[str]) -> list[tuple]:
    """ai_facilities.json → (역 ID, 언어, 시설 목록) 행. 모르는 역·언어가 있으면 CheckFailed."""
    if not FACILITIES.exists():
        return []
    data = json.loads(FACILITIES.read_text(encoding="utf-8"))
    rows = [(sid, lang, items) for sid, by_lang in data.items() for lang, items in by_lang.items()]
    errors = [f"{FACILITIES.name}: 모르는 역 {sid}" for sid in data if sid not in stations]
    errors += [f"{FACILITIES.name}: 모르는 언어 {sid}/{lang}" for sid, lang, _ in rows if lang not in LANGUAGES]
    if errors:
        raise CheckFailed(errors)
    return rows


def load_facilities(conn: psycopg.Connection, rows: list[tuple]) -> None:
    """파일에 있는 역·언어만 upsert한다 (있으면 파일 내용으로 바꾸고, 없으면 넣기)."""
    conn.cursor().executemany(
        "INSERT INTO ai_facilities (station_id, lang, items) VALUES (%s, %s, %s) "
        "ON CONFLICT (station_id, lang) DO UPDATE SET items = EXCLUDED.items, created_at = now()",
        [(sid, lang, Jsonb(items)) for sid, lang, items in rows],
    )
    total = count(conn, "SELECT count(*) FROM ai_facilities")
    print(f"{'ai_facilities':<20}{total:>6}{len(rows):>6}   (파일에 없는 {total - len(rows)}행은 그대로 둠)")


def count(conn: psycopg.Connection, sql: str) -> int:
    return conn.execute(sql).fetchone()[0]


def verify(conn: psycopg.Connection, rows: dict[str, list[tuple]]) -> None:
    """DB 행 수가 파일과 기준 개수에 맞는지 확인하고 표로 보여 준다."""
    errors = []
    print(f"{'테이블':<17}{'DB':>6}{'파일':>4}")  # 한글은 두 칸을 차지해서 폭을 줄여 맞춤
    for table, file_rows in rows.items():
        n = count(conn, f"SELECT count(*) FROM {table}")
        print(f"{table:<20}{n:>6}{len(file_rows):>6}")
        if n != len(file_rows):
            errors.append(f"{table}: DB {n}행, 파일 {len(file_rows)}행")
    for table in UNTOUCHED:
        print(f"{table:<20}{count(conn, f'SELECT count(*) FROM {table}'):>6}   (건드리지 않음)")

    got = {k: count(conn, sql) for k, sql in EXPECTED_SQL.items()}
    for k, want in EXPECTED.items():
        if got[k] != want:
            errors.append(f"{k} {got[k]}개 (기대값 {want})")
    if errors:
        raise CheckFailed(errors)
    print("기준 개수:", ", ".join(f"{k} {v}" for k, v in got.items()))


def main() -> int:
    rows = read_files()
    try:
        facilities = read_facilities({r[0] for r in rows["stations"]})
        with connect() as conn:  # 블록이 오류 없이 끝나면 commit, 오류가 나면 전부 rollback
            load(conn, rows)
            verify(conn, rows)
            load_facilities(conn, facilities)
    except MissingSettingError as e:
        print(f"❌ {e}")
        return 1
    except psycopg.OperationalError as e:
        print(f"❌ DB에 접속하지 못했습니다: {e}")
        print("   PostgreSQL이 켜져 있는지(맥: brew services start postgresql@16),")
        print("   .env의 DATABASE_URL 주소와 DB 이름이 맞는지 확인하세요. (DB 만들기: createdb subfit)")
        return 1
    except CheckFailed as e:
        print("❌ 검증 실패. DB는 실행 전 그대로입니다 (rollback).")
        for err in e.args[0]:
            print(" -", err)
        return 1
    except psycopg.Error as e:
        print(f"❌ DB 오류. DB는 실행 전 그대로입니다 (rollback).\n   {type(e).__name__}: {e}")
        return 1
    print("✅ 적재 완료, 검증 통과")
    return 0


if __name__ == "__main__":
    sys.exit(main())
