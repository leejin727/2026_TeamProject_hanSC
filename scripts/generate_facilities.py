"""역마다 주변 시설 예시를 Gemini로 미리 만들어 data/extra/ai_facilities.json에 저장한다.

실행 (저장소 최상위에서):
    .venv/bin/python scripts/generate_facilities.py                               # 파일에 없는 것만 (6개 언어)
    .venv/bin/python scripts/generate_facilities.py --lang ko en                  # 한국어·영어만
    .venv/bin/python scripts/generate_facilities.py --stations 701 705 --rebuild  # 두 역만 새로 만들기
    .venv/bin/python scripts/generate_facilities.py --rebuild                     # 111개 역 전부 새로 만들기

- 역마다 한국어 목록을 먼저 만들고, 다른 언어는 그 한국어 목록을 번역한다 (2026-11-25).
  그래서 언어가 달라도 같은 가게다. 한국어가 파일에 있으면 그것을 번역한다 (--rebuild면 한국어부터 새로 만든다).
- .env의 GEMINI_FACILITY_API_KEY를 쓴다. 서버의 주변 시설 API와 같은 프롬프트·같은 검사를 쓴다.
- 파일에 이미 있는 역·언어는 건너뛴다 (--rebuild를 주면 다시 만든다). 하나 만들 때마다 바로 저장하므로,
  중간에 멈추거나(Ctrl+C) 사용량 한도에 걸려도 다시 실행하면 이어서 만든다.
- 실패(과부하, 시간 초과, 한글 섞임, 번역 항목 수가 다름 등)하면 기다렸다 다시 시도하고, 그래도 안 되면 건너뛴다.
  번역할 한국어 목록이 없는 역은 다른 언어도 건너뛴다.
- 만든 파일은 커밋한다. python scripts/load_db.py가 이 파일을 DB(ai_facilities)에 넣는다.
- 왜 파일인가: 캐시 DB는 컴퓨터마다 따로라서, 파일로 공유해야 모두 같은 시설을 보고 Gemini도 한 번만 부른다.
"""

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))  # 서버의 프롬프트·Gemini 호출·검사를 그대로 쓰기 위해

from app.ai.client import AIUnavailableError  # noqa: E402
from app.ai.facilities import FACILITY_LANGS, generate_korean, translate  # noqa: E402
from app.config import DATA_DIR, MissingSettingError  # noqa: E402
from app.routing.graph_builder import load_network  # noqa: E402

OUTPUT = ROOT / "data/extra/ai_facilities.json"
RETRY_WAITS = (10, 30, 60)  # 실패하면 이만큼(초) 기다렸다 다시 시도. 그래도 안 되면 그 역·언어는 건너뛴다
MAX_FAILS_IN_A_ROW = 3  # 호출 자체가 연속으로 이만큼 실패하면 멈춘다 (하루 사용량 한도나 Gemini 장애일 가능성이 큼)
PAUSE_SEC = 4.0  # 호출 사이에 쉬는 시간. 분당 사용 한도를 넘지 않게


def read_file(path: Path) -> dict:
    """{역 ID: {언어: [시설, …]}}. 파일이 없으면 빈 사전."""
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def write_file(path: Path, data: dict) -> None:
    """역 번호·언어 순서로 정렬해 저장한다. 순서가 늘 같아서 PR에서 바뀐 부분만 보인다."""
    ordered = {
        sid: {lang: data[sid][lang] for lang in FACILITY_LANGS if lang in data[sid]}
        for sid in sorted(data)
    }
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(ordered, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(path)  # 다 쓴 뒤에 바꿔치기 → 쓰는 도중에 멈춰도 원래 파일이 깨지지 않는다


def make_one(make) -> list[dict]:
    """make()로 한 역·한 언어를 만든다. 다시 시도해도 안 되면 마지막 오류를 그대로 낸다.

    AIUnavailableError: 호출 실패(과부하, 한도, 시간 초과). ValueError: 답이 틀림(한글 섞임, 항목 수 다름 등).
    키가 없으면 MissingSettingError.
    """
    for wait in RETRY_WAITS:
        try:
            return make()
        except (AIUnavailableError, ValueError) as e:
            print(f"    실패: {str(e)[:150]}")
            print(f"    {wait}초 뒤 다시 시도")
            time.sleep(wait)
    return make()  # 마지막 시도


def plan(stations: list[str], langs: list[str], data: dict, rebuild: bool) -> list[tuple[str, str]]:
    """만들 (역, 언어) 목록. 역마다 한국어가 먼저 온다 (다른 언어는 한국어를 번역하므로)."""
    others = [lang for lang in FACILITY_LANGS if lang in langs and lang != "ko"]
    jobs = []
    for sid in stations:
        have = data.get(sid, {})
        todo = [lang for lang in others if rebuild or lang not in have]
        make_ko = rebuild or ("ko" not in have and ("ko" in langs or bool(todo)))
        jobs += ([(sid, "ko")] if make_ko else []) + [(sid, lang) for lang in todo]
    return jobs


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="주변 시설 AI 예시를 미리 만들어 파일에 저장")
    parser.add_argument("--lang", nargs="+", choices=FACILITY_LANGS, default=list(FACILITY_LANGS),
                        help="만들 언어 (기본: 6개 전부). 번역할 한국어가 없으면 한국어도 만든다")
    parser.add_argument("--stations", nargs="+", metavar="ID",
                        help="만들 역 번호 (기본: 111개 전부). 예: --stations 701 705")
    parser.add_argument("--rebuild", action="store_true",
                        help="파일에 있어도 다시 만든다 (한국어부터 새로 만들고 나머지 언어는 그것을 번역)")
    parser.add_argument("--pause", type=float, default=PAUSE_SEC, help=f"호출 사이 쉬는 초 (기본 {PAUSE_SEC})")
    args = parser.parse_args(argv)

    network = load_network(DATA_DIR)
    stations = list(dict.fromkeys(args.stations)) if args.stations else sorted(network.names)
    unknown = [sid for sid in stations if sid not in network.names]
    if unknown:
        print(f"❌ 없는 역 번호: {', '.join(unknown)}")
        return 2

    data = read_file(OUTPUT)
    jobs = plan(stations, args.lang, data, args.rebuild)
    print(f"만들 것 {len(jobs)}개 (역 {len(stations)}개 × 언어 {', '.join(args.lang)}"
          f"{', 다시 만들기' if args.rebuild else ' 중 파일에 없는 것'})")
    if args.rebuild and len(args.lang) < len(FACILITY_LANGS):
        print("⚠️ 한국어를 새로 만들면, 이번에 고르지 않은 언어는 예전 목록이라 가게가 다를 수 있습니다.")

    korean = {sid: data.get(sid, {}).get("ko") for sid in stations}  # 번역할 원본
    done, skipped, fails_in_a_row = set(), [], 0
    try:
        for i, (sid, lang) in enumerate(jobs, 1):
            name_ko, name_en = network.names[sid]
            print(f"[{i}/{len(jobs)}] {sid} {name_ko} ({lang})")
            if lang != "ko" and korean[sid] is None:
                print("    번역할 한국어 목록이 없어서 건너뜀")
                skipped.append(f"{sid}/{lang}")
                continue
            try:
                if lang == "ko":
                    items = make_one(lambda: generate_korean(name_ko))
                else:
                    items = make_one(lambda: translate(korean[sid], name_en, lang))
            except (AIUnavailableError, ValueError) as e:
                print(f"    실패: {str(e)[:150]} → 건너뜀")
                skipped.append(f"{sid}/{lang}")
                # 답이 틀린 것(ValueError)은 그 역만의 문제라 계속한다. 호출 자체가 계속 실패할 때만 멈춘다
                if isinstance(e, AIUnavailableError):
                    fails_in_a_row += 1
                    if fails_in_a_row >= MAX_FAILS_IN_A_ROW:
                        print(f"❗ 연속 {fails_in_a_row}번 호출이 실패해서 멈춥니다. "
                              "하루 사용량 한도이거나 Gemini 장애일 수 있습니다.")
                        break
            else:
                data.setdefault(sid, {})[lang] = items
                if lang == "ko":
                    korean[sid] = items
                write_file(OUTPUT, data)
                done.add((sid, lang))
                fails_in_a_row = 0
            if i < len(jobs):
                time.sleep(args.pause)
    except MissingSettingError as e:
        print(f"❌ {e}")
        return 1
    except KeyboardInterrupt:
        print("\n멈췄습니다.")

    print(f"\n새로 만든 것 {len(done)}개 → {OUTPUT}")
    if skipped:
        print(f"건너뛴 것 {len(skipped)}개: {', '.join(skipped)}")
    left = len(jobs) - len(done)
    if left:
        print(f"남은 것 {left}개. 같은 명령을 다시 실행하면 이어서 만듭니다 (--rebuild 없이 실행하면 없는 것만).")
        return 1
    print("✅ 모두 만들었습니다. DB에 넣으려면: python scripts/load_db.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
