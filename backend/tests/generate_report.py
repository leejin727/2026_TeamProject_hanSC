"""backend에서 python -m tests.generate_report --output ../reports 로 실행."""
import argparse
import csv
import hashlib
import json
import os
from dataclasses import asdict
from datetime import datetime, timezone
from pathlib import Path

from app.routing.graph_builder import load_network
from app.routing.dijkstra import find_route
from app.routing.meeting import find_meeting_stations
from tests.verify_full_network import source_records, verify_route

LABELS = {"time": "최단 시간", "transfers": "최소 환승", "fairness": "공평성"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def oracle(network, mode):
    """Dijkstra와 독립적인 Floyd–Warshall 탐색 기록."""
    nodes = sorted(network.adjacency)
    index = {node: i for i, node in enumerate(nodes)}
    inf = (float("inf"), float("inf"))
    records = [[inf for _ in nodes] for _ in nodes]
    for i, node in enumerate(nodes):
        records[i][i] = (0, 0)
        for edge in network.adjacency[node]:
            value = (edge.seconds, int(edge.transfer))
            if mode == "transfers":
                value = value[::-1]
            j = index[edge.target]
            records[i][j] = min(records[i][j], value)
    for k in range(len(nodes)):
        for i in range(len(nodes)):
            if records[i][k] == inf:
                continue
            for j in range(len(nodes)):
                a, b = records[i][k], records[k][j]
                records[i][j] = min(records[i][j], (a[0] + b[0], a[1] + b[1]))
    groups = {s: [index[n] for n in nodes if n[0] == s] for s in network.names}
    return {(a, b): min(records[i][j] for i in groups[a] for j in groups[b])
            for a in groups for b in groups}


def write_csv(path, rows):
    # Windows Excel에서 한글을 읽을 수 있도록 BOM이 있는 UTF-8로 저장한다.
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def generate(output):
    root = Path(__file__).resolve().parents[2]
    data = root / "data"
    network = load_network(data)
    source = source_records(data)
    station_ids = sorted(network.names, key=int)
    name = lambda station: f"{station} {network.names[station][0]}"
    expected = {mode: oracle(network, mode) for mode in ("time", "transfers")}
    routes, route_rows = [], []
    for mode in expected:
        for start in station_ids:
            for end in station_ids:
                route = find_route(network, start, end, mode)
                verify_route(route, start, end, *source)
                actual = (route.total_sec, len(route.transfers))
                best = expected[mode][start, end]
                if mode == "transfers":
                    best = best[::-1]
                require(actual == best, f"Route mismatch: {start}, {end}, {mode}")
                stations = [start]
                for segment in route.segments:
                    stations.extend(segment.stations[1:])
                routes.append({"start": start, "end": end, "criteria": mode,
                               "expected_seconds": best[0], "expected_transfers": best[1],
                               "passed": True, "stations": stations, "actual": route.to_dict()})
                route_rows.append({"출발역": name(start), "도착역": name(end), "기준": LABELS[mode],
                                   "기대시간_초": best[0], "실제시간_초": actual[0],
                                   "기대환승_회": best[1], "실제환승_회": actual[1],
                                   "일치": True, "경유역": " → ".join(map(name, stations)),
                                   "노선": " → ".join(str(s.line) for s in route.segments),
                                   "구간별방면": " → ".join(name(s.direction) for s in route.segments),
                                   "환승정보": json.dumps([asdict(t) for t in route.transfers], ensure_ascii=False)})
    meetings, meeting_rows = [], []
    cases = (["101", "101", "207"], ["101", "416", "805"], ["112", "118"])
    for starts in cases:
        for criteria, result in find_meeting_stations(network, starts).items():
            mode = "transfers" if criteria == "transfers" else "time"
            candidates = {}
            for station in station_ids:
                values = [expected[mode][s, station] for s in starts]
                if any(float("inf") in v for v in values):
                    continue
                values = [v[::-1] if mode == "transfers" else v for v in values]
                times, transfers = [v[0] for v in values], [v[1] for v in values]
                score = ((sum(times), int(station)) if criteria == "time" else
                         (sum(transfers), sum(times), int(station)) if criteria == "transfers" else
                         (max(times), sum(times), int(station)))
                candidates[station] = {"score": score, "participant_records": values}
            winner = min(candidates, key=lambda s: candidates[s]["score"])
            require(result.station == winner, "Meeting station mismatch")
            for p, best in zip(result.participants, candidates[winner]["participant_records"]):
                require((p.travel_sec, p.transfer_count) == best, "Participant record mismatch")
                require(p.travel_sec == sum(s.ride_sec for s in p.segments) + sum(t.sec for t in p.transfers),
                        "Restored time mismatch")
                require(p.transfer_count == len(p.transfers), "Restored transfers mismatch")
            require(result.total_travel_sec == sum(p.travel_sec for p in result.participants), "Total time mismatch")
            require(result.total_transfer_count == sum(p.transfer_count for p in result.participants), "Total transfers mismatch")
            require(result.max_travel_sec == max(p.travel_sec for p in result.participants), "Maximum time mismatch")
            meetings.append({"starts": starts, "criteria": criteria, "expected_station": winner,
                             "passed": True, "all_candidate_expectations": candidates, "actual": result.to_dict()})
            for i, p in enumerate(result.participants, 1):
                meeting_rows.append({"출발역목록": ", ".join(map(name, starts)), "기준": LABELS[criteria],
                                     "기대추천역": name(winner), "실제추천역": name(result.station), "일치": True,
                                     "참여자순서": i, "참여자출발역": name(p.start),
                                     "개인시간_초": p.travel_sec, "개인환승_회": p.transfer_count,
                                     "전체시간_초": result.total_travel_sec, "전체환승_회": result.total_transfer_count,
                                     "최대시간_초": result.max_travel_sec,
                                     "경유역": " → ".join(map(name, p.stations)),
                                     "노선": " → ".join(str(s.line) for s in p.segments),
                                     "구간별방면": " → ".join(name(s.direction) for s in p.segments),
                                     "환승정보": json.dumps([asdict(t) for t in p.transfers], ensure_ascii=False)})
    files = [data / "raw/stations.xlsx"] + sorted((data / "extra").glob("*.csv"))
    edges = [edge for values in network.adjacency.values() for edge in values]
    metadata = {"generated_at_utc": datetime.now(timezone.utc).isoformat(),
                "github_sha": os.environ.get("GITHUB_SHA"), "github_run_id": os.environ.get("GITHUB_RUN_ID"),
                "stations": len(station_ids), "line_station_nodes": len(network.adjacency),
                "travel_edges_undirected": sum(not e.transfer for e in edges) // 2,
                "transfer_edges_undirected": sum(e.transfer for e in edges) // 2,
                "transfer_seconds": sorted({e.seconds for e in edges if e.transfer}),
                "oracle": "Floyd-Warshall", "route_cases": len(routes), "meeting_cases": len(meetings),
                "source_sha256": {str(p.relative_to(root)).replace("\\", "/"): hashlib.sha256(p.read_bytes()).hexdigest() for p in files},
                "scope": "프로젝트 가상 노선. 전체 역 쌍의 두 길찾기 기준 및 명시한 모임역 사례만 검사. API/전체 참여자 조합 검사가 아님."}
    output.mkdir(parents=True, exist_ok=True)
    for filename, content in (("metadata.json", metadata), ("routes.json", routes), ("meetings.json", meetings)):
        (output / filename).write_text(json.dumps(content, ensure_ascii=False, indent=2), encoding="utf-8")
    write_csv(output / "routes.csv", route_rows)
    write_csv(output / "meetings.csv", meeting_rows)
    lines = ["# SubFit 알고리즘 실행 보고서", "", metadata["scope"], "",
             f"- 역 {len(station_ids)}개 / 노드 {len(network.adjacency)}개",
             f"- 길찾기 {len(routes):,}건, 모임역 {len(meetings)}건: 기대값과 모두 일치",
             "- 기대값: 별도 Floyd–Warshall 탐색 기록. 이동·환승 시간 단위: 초.",
             "- 전체 경유역·이동 구간·환승 정보: CSV 및 JSON 참고.",
             "- 이 보고서의 통과는 보고서 자체 검사 결과이며 pytest/API 통과 개수를 의미하지 않습니다.", "",
             "## 길찾기 대표 사례", "", "|출발|도착|기준|기대 시간|실제 시간|환승|일치|",
             "|---|---|---|---:|---:|---:|---|"]
    for row in route_rows:
        if (row["출발역"].split()[0], row["도착역"].split()[0]) in (("112", "118"), ("101", "207"), ("101", "101")):
            lines.append(f'|{row["출발역"]}|{row["도착역"]}|{row["기준"]}|{row["기대시간_초"]}|{row["실제시간_초"]}|{row["실제환승_회"]}|통과|')
    lines.extend(["", "## 모임역 사례 전체", "", "|출발역|기준|기대 / 실제 추천역|개인별 시간|합계|환승 합계|최대|일치|",
                  "|---|---|---|---|---:|---:|---:|---|"])
    for entry in meetings:
        r = entry["actual"]
        lines.append(f'|{", ".join(map(name, entry["starts"]))}|{LABELS[entry["criteria"]]}|{name(entry["expected_station"])} / {name(r["station"])}|{", ".join(str(p["travel_sec"]) for p in r["participants"])}|{r["total_travel_sec"]}|{r["total_transfer_count"]}|{r["max_travel_sec"]}|통과|')
    summary = "\n".join(lines) + "\n"
    (output / "summary.md").write_text(summary, encoding="utf-8")
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as stream:
            stream.write(summary)
    print(json.dumps(metadata, ensure_ascii=True))
    return metadata


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=Path("../reports"))
    generate(parser.parse_args().output)
