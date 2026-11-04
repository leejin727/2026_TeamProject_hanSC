import heapq
from .models import Route, Segment, Transfer

class UnknownStationError(ValueError):
    pass

class NoRouteError(ValueError):
    pass

def find_route(network, origin, destination, mode="fastest"):
    """IDs are integer station IDs. Total time includes transfer walking time.
    Initial boarding and final alighting are free. No waiting-time data exists.
    """
    if mode not in ("fastest", "fewest_transfers"):
        raise ValueError("Unknown routing mode")
    for station in (origin, destination):
        if type(station) is not int or station not in network.names:
            raise UnknownStationError(f"Unknown station: {station}")
    if origin == destination:
        return Route(origin, destination, 0, 0, [origin], [], [])
    distances, previous, queue = {}, {}, []
    for node in sorted(network.adjacency):
        if node[0] == origin:
            distances[node] = (0, 0)
            heapq.heappush(queue, ((0, 0), node))
    end = None
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != distances[node]:
            continue
        if node[0] == destination:
            end = node
            break
        for edge in network.adjacency[node]:
            delta = (int(edge.transfer), edge.seconds) if mode == "fewest_transfers" else (edge.seconds, int(edge.transfer))
            candidate = (cost[0] + delta[0], cost[1] + delta[1])
            if edge.target not in distances or candidate < distances[edge.target]:
                distances[edge.target] = candidate
                previous[edge.target] = node, edge
                heapq.heappush(queue, (candidate, edge.target))
    if end is None:
        raise NoRouteError(f"No route from {origin} to {destination}")
    steps = []
    while end in previous:
        node, edge = previous[end]
        steps.append((node, edge))
        end = node
    stations, segments, transfers = [origin], [], []
    total = 0
    for node, edge in reversed(steps):
        total += edge.seconds
        if edge.transfer:
            transfers.append(Transfer(node[0], node[1], edge.target[1], edge.seconds))
        else:
            stations.append(edge.target[0])
            segments.append(Segment(node[0], edge.target[0], node[1], edge.seconds))
    return Route(origin, destination, total, len(transfers), stations, segments, transfers)
