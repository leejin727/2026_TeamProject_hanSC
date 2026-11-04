"""Run after the small unit tests. Floyd-Warshall is an independent oracle."""
import json
from time import perf_counter
from pathlib import Path
from backend.app.routing.graph_builder import load_network, read_times
from backend.app.routing.dijkstra import find_route


def verify_route(route, raw_times, allowed, transfers):
    """Verify returned paths against source records, not the constructed graph."""
    assert route.stations == [route.origin] + [s.to_station for s in route.segments]
    position, line, transfer_index = route.origin, None, 0
    for segment in route.segments:
        assert segment.from_station == position
        if line is not None and line != segment.line:
            assert transfer_index < len(route.transfers)
            transfer = route.transfers[transfer_index]
            assert (transfer.station, transfer.from_line, transfer.to_line) == (position, line, segment.line)
            key = (position, *sorted((line, segment.line)))
            assert transfer.seconds == transfers[key]
            transfer_index += 1
        pair = tuple(sorted((position, segment.to_station)))
        assert (segment.line, pair) in allowed
        assert segment.seconds == raw_times[pair]
        position, line = segment.to_station, segment.line
    assert position == route.destination
    assert transfer_index == len(route.transfers)

def source_records(data):
    import csv
    def rows(name):
        with (data / "extra" / name).open(encoding="utf-8") as f:
            return list(csv.DictReader(f))
    circular = {int(r["line"]) for r in rows("lines.csv") if r["is_circular"] == "1"}
    orders = {}
    for r in rows("line_stations.csv"):
        orders.setdefault(int(r["line"]), []).append((int(r["seq"]), int(r["station"])))
    allowed = set()
    for line, items in orders.items():
        stations = [s for _,s in sorted(items)]
        for i in range(len(stations)):
            if i + 1 < len(stations) or line in circular:
                pair = tuple(sorted((stations[i],stations[(i+1)%len(stations)])))
                allowed.add((line,pair))
    transfers = {(int(r["station"]), *sorted((int(r["line_a"]),int(r["line_b"])))):int(r["transfer_sec"])
                 for r in rows("transfers.csv")}
    return read_times(data/"raw"/"stations.xlsx"), allowed, transfers


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
    for mode in ("fastest", "fewest_transfers"):
        inf = (float("inf"), float("inf"))
        d = [[inf] * len(nodes) for _ in nodes]
        for i,node in enumerate(nodes):
            d[i][i] = (0,0)
            for edge in graph.adjacency[node]:
                d[i][index[edge.target]] = ((edge.seconds, int(edge.transfer)) if mode == "fastest"
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
                route = find_route(graph, a, b, mode)
                durations.append(perf_counter() - start)
                verify_route(route, *source)
                expected = min(d[i][j] for i in groups[a] for j in groups[b])
                actual = ((route.total_seconds, route.transfer_count) if mode == "fastest"
                          else (route.transfer_count, route.total_seconds))
                assert actual == expected, (a,b,mode,actual,expected)
                assert route.total_seconds == sum(s.seconds for s in route.segments) + sum(t.seconds for t in route.transfers)
                assert route.transfer_count == len(route.transfers)
                assert route.stations[0] == a and route.stations[-1] == b
                checked += 1
    print(json.dumps({"stations":111,"line_station_nodes":146,"travel_edges":139,
                      "transfer_edges":35,"checked_routes":checked,"oracle":"Floyd-Warshall",
                      "graph_build_seconds":build_seconds,
                      "max_route_seconds":max(durations),
                      "mean_route_seconds":sum(durations)/len(durations)}))
    print(json.dumps({m:find_route(graph,112,118,m).to_dict() for m in ("fastest","fewest_transfers")}))
if __name__ == "__main__":
    main()
