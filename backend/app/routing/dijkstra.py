import heapq
from .models import RouteResult, Segment, Transfer

class UnknownStationError(ValueError):
    pass

class NoRouteError(ValueError):
    pass

def find_route(network, start, end, criteria):
    """start 역에서 end 역까지의 경로를 찾는다.

    - 역 ID는 문자열 (예: "101")
    - criteria: "time" 최단 시간 / "transfers" 최소 환승
    - 총 시간에는 환승 시간이 들어간다. 출발역에서 처음 탈 때와 도착역에서 내릴 때는
      환승 시간을 넣지 않는다. 기다리는 시간 데이터는 없다.
    """
    if criteria not in ("time", "transfers"):
        raise ValueError(f"Unknown criteria: {criteria!r}")
    for station in (start, end):
        if not isinstance(station, str) or station not in network.names:
            raise UnknownStationError(f"Unknown station: {station!r}")
    if start == end:
        return RouteResult([], [], 0, 0)
    distances, previous, queue = {}, {}, []
    for node in sorted(network.adjacency):
        if node[0] == start:
            distances[node] = (0, 0)
            heapq.heappush(queue, ((0, 0), node))
    end_node = None
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != distances[node]:
            continue
        if node[0] == end:
            end_node = node
            break
        for edge in network.adjacency[node]:
            delta = (int(edge.transfer), edge.seconds) if criteria == "transfers" else (edge.seconds, int(edge.transfer))
            candidate = (cost[0] + delta[0], cost[1] + delta[1])
            if edge.target not in distances or candidate < distances[edge.target]:
                distances[edge.target] = candidate
                previous[edge.target] = node, edge
                heapq.heappush(queue, (candidate, edge.target))
    if end_node is None:
        raise NoRouteError(f"No route from {start} to {end}")
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
