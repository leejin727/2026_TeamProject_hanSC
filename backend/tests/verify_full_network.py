"""Run after the small unit tests. Floyd-Warshall is an independent oracle.

실행 (backend 폴더에서): python -m tests.verify_full_network
"""
import json
from time import perf_counter
from pathlib import Path
from app.routing.graph_builder import load_network, read_edges
from app.routing.dijkstra import find_route


def verify_route(route, start, end, raw_edges, allowed, transfers):
    """Verify returned paths against source records, not the constructed graph."""
    # 환승은 구간과 구간 사이에만 있다
    assert len(route.transfers) == max(len(route.segments) - 1, 0)
    position, line, cost = start, None, 0
    for i, segment in enumerate(route.segments):
        assert len(segment.stations) >= 2
        assert segment.stations[0] == position
        assert segment.direction == segment.stations[1]
        if i > 0:
            transfer = route.transfers[i - 1]
            assert line != segment.line
            assert (transfer.station, transfer.from_line, transfer.to_line) == (position, line, segment.line)
            assert transfer.sec == transfers[(position, *sorted((line, segment.line)))]
        ride_sec = 0
        for a, b in zip(segment.stations, segment.stations[1:]):
            pair = tuple(sorted((a, b)))
            assert (segment.line, pair) in allowed
            ride_sec += raw_edges[pair][0]
            cost += raw_edges[pair][1]
        assert segment.ride_sec == ride_sec
        position, line = segment.stations[-1], segment.line
    assert position == end
    assert route.cost_won == cost
    assert route.total_sec == sum(s.ride_sec for s in route.segments) + sum(t.sec for t in route.transfers)

def source_records(data):
    import csv
    def rows(name):
        with (data / "extra" / name).open(encoding="utf-8") as f:
            return list(csv.DictReader(f))
    circular = {int(r["line"]) for r in rows("lines.csv") if r["is_circular"] == "1"}
    orders = {}
    for r in rows("line_stations.csv"):
        orders.setdefault(int(r["line"]), []).append((int(r["seq"]), r["station"]))
    allowed = set()
    for line, items in orders.items():
        stations = [s for _,s in sorted(items)]
        for i in range(len(stations)):
            if i + 1 < len(stations) or line in circular:
                pair = tuple(sorted((stations[i],stations[(i+1)%len(stations)])))
                allowed.add((line,pair))
    transfers = {(r["station"], *sorted((int(r["line_a"]),int(r["line_b"])))):int(r["transfer_sec"])
                 for r in rows("transfers.csv")}
    return read_edges(data/"raw"/"stations.xlsx"), allowed, transfers


def main():
    data = Path(__file__).resolve().parents[2] / "data"
    source = source_records(data)
    start = perf_counter()
    graph = load_network(data)
    build_seconds = perf_counter() - start
    durations = []
    nodes = sorted(graph.adjacency)
    stations = sorted(graph.names)
    assert len(stations) == 111 and len(nodes) == 146
    edges = [e for es in graph.adjacency.values() for e in es]
    assert sum(not e.transfer for e in edges) == 278
    assert sum(e.transfer for e in edges) == 70
    groups = {s: [i for i,n in enumerate(nodes) if n[0] == s] for s in stations}
    index = {n:i for i,n in enumerate(nodes)}
    checked = 0
    for criteria in ("time", "transfers"):
        inf = (float("inf"), float("inf"))
        d = [[inf] * len(nodes) for _ in nodes]
        for i,node in enumerate(nodes):
            d[i][i] = (0,0)
            for edge in graph.adjacency[node]:
                d[i][index[edge.target]] = ((edge.seconds, int(edge.transfer)) if criteria == "time"
                                          else (int(edge.transfer), edge.seconds))
        for k in range(len(nodes)):
            for i in range(len(nodes)):
                if d[i][k] == inf:
                    continue
                for j in range(len(nodes)):
                    candidate = (d[i][k][0] + d[k][j][0], d[i][k][1] + d[k][j][1])
                    if candidate < d[i][j]:
                        d[i][j] = candidate
        for a in stations:
            for b in stations:
                start = perf_counter()
                route = find_route(graph, a, b, criteria)
                durations.append(perf_counter() - start)
                verify_route(route, a, b, *source)
                expected = min(d[i][j] for i in groups[a] for j in groups[b])
                actual = ((route.total_sec, len(route.transfers)) if criteria == "time"
                          else (len(route.transfers), route.total_sec))
                assert actual == expected, (a,b,criteria,actual,expected)
                checked += 1
    print(json.dumps({"stations":111,"line_station_nodes":146,"travel_edges":139,
                      "transfer_edges":35,"checked_routes":checked,"oracle":"Floyd-Warshall",
                      "graph_build_seconds":build_seconds,
                      "max_route_seconds":max(durations),
                      "mean_route_seconds":sum(durations)/len(durations)}))
    print(json.dumps({c:find_route(graph,"112","118",c).to_dict() for c in ("time","transfers")}, ensure_ascii=False))
if __name__ == "__main__":
    main()
