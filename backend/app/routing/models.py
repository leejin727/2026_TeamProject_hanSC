from dataclasses import dataclass, asdict

# 역 ID는 문자열이다 (예: "101"). 역 번호는 이름표라서 숫자로 계산하지 않는다.
StationId = str
# 그래프 노드 = (역, 노선). 예: ("123", 1). routing 안에서만 쓴다.
Node = tuple[StationId, int]

@dataclass(frozen=True)
class Edge:
    target: Node
    seconds: int
    transfer: bool = False
    cost_won: int = 0          # 구간 비용. 환승 연결선은 0원

@dataclass(frozen=True)
class Segment:
    """한 노선을 이어서 탄 구간 하나."""
    line: int
    stations: list[StationId]  # 탑승역 ~ 하차역 (양 끝 포함, 탄 순서대로)
    direction: StationId | None  # 방면 역. 표기 방식이 정해질 때까지 항상 None
    ride_sec: int              # 이 구간 탑승 시간의 합

@dataclass(frozen=True)
class Transfer:
    station: StationId
    from_line: int
    to_line: int
    sec: int                   # transfers.csv의 transfer_sec

@dataclass(frozen=True)
class RouteResult:
    segments: list[Segment]
    transfers: list[Transfer]  # 개수 = 환승 횟수
    total_sec: int             # ride_sec 합 + 환승 sec 합
    cost_won: int              # 지나간 구간 비용의 합 (환승은 0원)

    def to_dict(self):
        return asdict(self)
