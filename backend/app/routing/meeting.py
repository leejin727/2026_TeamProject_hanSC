"""전체 후보역을 평가하는 모임역 추천. 요청 안에서 출발역·모드별 탐색을 재사용."""
from dataclasses import dataclass, asdict
from .dijkstra import search, restore_route, UnknownStationError, NoRouteError
from .models import Segment, Transfer

CRITERIA = ("time", "transfers", "fairness")

class InvalidParticipantCountError(ValueError):
    pass

class NoMeetingStationError(NoRouteError):
    pass

@dataclass(frozen=True)
class ParticipantResult:
    start: str
    travel_sec: int
    transfer_count: int
    stations: list[str]
    segments: list[Segment]
    transfers: list[Transfer]

@dataclass(frozen=True)
class MeetingResult:
    criteria: str
    station: str
    station_names: tuple[str, str]
    participants: list[ParticipantResult]
    total_travel_sec: int
    total_transfer_count: int
    max_travel_sec: int

    def to_dict(self):
        return asdict(self)

def _score(criteria, records, station):
    times = [r[0] for r in records]
    transfers = [r[1] for r in records]
    # ID는 API에서는 문자열을 유지하되 최종 동점에서는 숫자 역 번호로 비교한다.
    tie = int(station)
    if criteria == "time":
        return sum(times), tie
    if criteria == "transfers":
        return sum(transfers), sum(times), tie
    return max(times), sum(times), tie

def find_meeting_stations(network, starts, criteria_list=CRITERIA):
    """여러 기준을 함께 요청해도 출발역마다 최대 두 모드만 탐색한다."""
    if not isinstance(starts, list):
        raise ValueError("starts must be a list of station IDs")
    if not 2 <= len(starts) <= 4:
        raise InvalidParticipantCountError("Participant count must be between 2 and 4")
    for station in starts:
        if not isinstance(station, str) or station not in network.names:
            raise UnknownStationError(f"Unknown station: {station!r}")
    if not isinstance(criteria_list, (list, tuple)) or not criteria_list or any(c not in CRITERIA for c in criteria_list):
        raise ValueError("Unknown meeting criteria")
    cache, results = {}, {}
    for criteria in criteria_list:
        if criteria in results:
            continue
        mode = "transfers" if criteria == "transfers" else "time"
        for start in starts:
            if (start, mode) not in cache:
                cache[start, mode] = search(network, start, mode)
        best = None
        selected = None
        for station in network.names:
            selected_nodes, records = [], []
            for start in starts:
                exploration = cache[start, mode]
                node = exploration.station_nodes.get(station)
                if node is None:
                    break
                record = exploration.distances[node]
                records.append(record[::-1] if mode == "transfers" else record)
                selected_nodes.append(node)
            else:
                score = _score(criteria, records, station)
                if best is None or score < best:
                    best, selected = score, (station, selected_nodes, records)
        if selected is None:
            raise NoMeetingStationError("No station is reachable by every participant")
        station, nodes, records = selected
        participants = []
        for start, node, record in zip(starts, nodes, records):
            route = restore_route(cache[start, mode], node, include_fare=False)
            stations = [start]
            for segment in route.segments:
                stations.extend(segment.stations[1:])
            if (route.total_sec, len(route.transfers)) != record:
                raise RuntimeError("Restored route does not match the selected search record")
            participants.append(ParticipantResult(start, route.total_sec, len(route.transfers),
                                                   stations, route.segments, route.transfers))
        results[criteria] = MeetingResult(criteria, station, network.names[station], participants,
                                         sum(p.travel_sec for p in participants),
                                         sum(p.transfer_count for p in participants),
                                         max(p.travel_sec for p in participants))
    return results

def find_meeting_station(network, starts, criteria):
    return find_meeting_stations(network, starts, (criteria,))[criteria]
