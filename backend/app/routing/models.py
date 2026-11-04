from dataclasses import dataclass, asdict

Node = tuple[int, int]

@dataclass(frozen=True)
class Edge:
    target: Node
    seconds: int
    transfer: bool = False

@dataclass(frozen=True)
class Segment:
    from_station: int
    to_station: int
    line: int
    seconds: int

@dataclass(frozen=True)
class Transfer:
    station: int
    from_line: int
    to_line: int
    seconds: int

@dataclass(frozen=True)
class Route:
    origin: int
    destination: int
    total_seconds: int
    transfer_count: int
    stations: list[int]
    segments: list[Segment]
    transfers: list[Transfer]

    def to_dict(self):
        return asdict(self)
