"""교수님 원본(stations.xlsx)과 팀이 만든 노선 순서(line_stations.csv)가 서로 맞는지 검사한다.

실행: python scripts/validate_data.py
원본은 data/raw/stations.xlsx 에 두고 절대 수정하지 않는다.
"""
import sys
from collections import Counter, defaultdict

import pandas as pd

RAW = "data/raw/stations.xlsx"
LINE_STATIONS = "data/extra/line_stations.csv"
LINES = "data/extra/lines.csv"
NAMES = "data/extra/station_names.csv"
TRANSFERS = "data/extra/transfers.csv"

EXPECTED = {"stations": 111, "edges": 139, "transfers": 35}

errors = []

raw = pd.read_excel(RAW)
raw.columns = ["from", "to", "sec", "meter", "won"]
edges = {frozenset((r["from"], r["to"])) for _, r in raw.iterrows()}

ls = pd.read_csv(LINE_STATIONS).sort_values(["line", "seq"])
circular = set(pd.read_csv(LINES).query("is_circular == 1")["line"])

# 1) 노선 순서의 인접한 두 역이 원본 구간에 있는지, 각 구간이 정확히 한 번 쓰이는지
used = Counter()
members = defaultdict(set)
for line, g in ls.groupby("line"):
    seq = g["station"].tolist()
    if line in circular:
        seq = seq + [seq[0]]  # 순환선은 마지막 역 → 첫 역 연결
    for s in seq:
        members[s].add(line)
    for a, b in zip(seq, seq[1:]):
        key = frozenset((a, b))
        if key not in edges:
            errors.append(f"{line}호선 {a}-{b} 구간이 원본에 없음")
        used[key] += 1

unused = [tuple(k) for k in edges if used[k] == 0]
dup = [tuple(k) for k, n in used.items() if n > 1]
if unused:
    errors.append(f"어느 노선에도 속하지 않은 원본 구간: {unused}")
if dup:
    errors.append(f"두 번 이상 쓰인 구간: {dup}")

# 2) 개수 확인
stations = {s for k in edges for s in k}
transfers = [s for s, l in members.items() if len(l) > 1]
counts = {"stations": len(stations), "edges": len(edges), "transfers": len(transfers)}
for k, v in EXPECTED.items():
    if counts[k] != v:
        errors.append(f"{k} 개수 {counts[k]} (기대값 {v})")

# 3) 역 이름: 모든 역에 한국어·영어 이름이 있고 중복이 없는지
names = pd.read_csv(NAMES)
if set(names["station"]) != stations:
    errors.append("station_names.csv의 역 목록이 원본과 다름")
for col in ["name_ko", "name_en"]:
    if names[col].isna().any():
        errors.append(f"{col}에 빈 이름이 있음")
    if names[col].duplicated().any():
        errors.append(f"{col}에 중복 이름: {names[names[col].duplicated()][col].tolist()}")

# 4) 환승: 환승역 목록·노선 쌍이 노선 순서표와 일치하고 환승 시간이 양수인지
tr = pd.read_csv(TRANSFERS)
expected_tr = {s: tuple(sorted(l)) for s, l in members.items() if len(l) > 1}
actual_tr = {r.station: tuple(sorted((r.line_a, r.line_b))) for r in tr.itertuples()}
if expected_tr != actual_tr:
    errors.append("transfers.csv가 노선 순서표에서 계산한 환승역과 다름")
if (tr["transfer_sec"] <= 0).any():
    errors.append("0 이하인 환승 시간이 있음")

# 5) 원본 값 이상 여부
if raw.isna().any().any():
    errors.append("원본에 빈 칸이 있음")
if (raw[["sec", "meter", "won"]] <= 0).any().any():
    errors.append("0 이하인 시간/거리/비용이 있음")

print("개수:", counts)
if errors:
    print("❌ 검증 실패")
    for e in errors:
        print(" -", e)
    sys.exit(1)
print("✅ 검증 통과")
