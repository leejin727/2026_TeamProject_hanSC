"""공통 Dijkstra 탐색 기록과 경로 복원. 시간·환승 기록을 사전식 비교한다."""
import heapq
from dataclasses import dataclass
from .models import RouteResult, Segment, Transfer, Node, Edge

class UnknownStationError(ValueError):
    pass

class NoRouteError(ValueError):
    pass

@dataclass
class SearchResult:
    start: str
    criteria: str
    distances: dict[Node, tuple[int, int]]
    previous: dict[Node, tuple[Node, Edge]]
    station_nodes: dict[str, Node]

def search(network, start, criteria, end=None):
    """end가 없으면 전체 탐색. station_nodes에는 확정한 도착 노드를 저장한다."""
    if criteria not in ("time", "transfers"):
        raise ValueError(f"Unknown criteria: {criteria!r}")
    for station in (start,) if end is None else (start, end):
        if not isinstance(station, str) or station not in network.names:
            raise UnknownStationError(f"Unknown station: {station!r}")
    distances, previous, queue, station_nodes = {}, {}, [], {}
    for node in sorted(network.adjacency):
        if node[0] == start:
            distances[node] = (0, 0)
            heapq.heappush(queue, ((0, 0), node))
    while queue:
        record, node = heapq.heappop(queue)
        if record != distances[node]:
            continue
        # 우선순위 큐에서 처음 확정한 노드가 해당 역의 최선 기록이다.
        station_nodes.setdefault(node[0], node)
        if node[0] == end:
            break
        for edge in network.adjacency[node]:
            delta = ((int(edge.transfer), edge.seconds) if criteria == "transfers"
                     else (edge.seconds, int(edge.transfer)))
            candidate = (record[0] + delta[0], record[1] + delta[1])
            if edge.target not in distances or candidate < distances[edge.target]:
                distances[edge.target] = candidate
                previous[edge.target] = node, edge
                heapq.heappush(queue, (candidate, edge.target))
    return SearchResult(start, criteria, distances, previous, station_nodes)

def restore_route(result, end_node, *, include_fare=True):
    """저장한 이전 노드로 복원한다. 모임역에서는 요금을 누적하지 않는다."""
    previous = result.previous
    if end_node not in result.distances:
        raise NoRouteError(f"Unreachable node: {end_node!r}")
    steps = []
    while end_node in previous:
        node, edge = previous[end_node]
        steps.append((node, edge))
        end_node = node

    # 지나온 연결선을 처음부터 보면서, 같은 노선을 이어서 탄 정거장들을 한 구간으로 묶는다.
    rides = []  # 구간마다 {"line", "stations", "ride_sec"}
    transfers = []
    total_sec = cost_won = 0
    for node, edge in reversed(steps):
        total_sec += edge.seconds
        if include_fare:
            cost_won += edge.cost_won
        if edge.transfer:
            transfers.append(Transfer(node[0], node[1], edge.target[1], edge.seconds))
            continue
        station, line = node
        if not rides or rides[-1]["line"] != line:
            rides.append({"line": line, "stations": [station], "ride_sec": 0})
        rides[-1]["stations"].append(edge.target[0])
        rides[-1]["ride_sec"] += edge.seconds
    # direction: 방향 표기 방식이 아직 정해지지 않아 None (api-spec 논의 필요 1)
    segments = [Segment(r["line"], r["stations"], None, r["ride_sec"]) for r in rides]
    return RouteResult(segments, transfers, total_sec, cost_won)


def find_route(network, start, end, criteria):
    """기존 단일 목적지 인터페이스와 응답 형식을 유지한다."""
    result = search(network, start, criteria, end=end)
    if start == end:
        return RouteResult([], [], 0, 0)
    if end not in result.station_nodes:
        raise NoRouteError(f"No route from {start} to {end}")
    return restore_route(result, result.station_nodes[end])
