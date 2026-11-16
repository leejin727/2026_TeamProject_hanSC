"""POST /routes — 경로 계산 (docs/api-spec.md 2장)."""

from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel

from app.api.common import check_lang, check_station, station_ref
from app.errors import AppError
from app.routing.dijkstra import NoRouteError, UnknownStationError, find_route
from app.routing.graph_builder import Network

router = APIRouter()

KST = timezone(timedelta(hours=9))  # 한국 시간. 서머타임이 없어 +09:00으로 고정


class RouteRequest(BaseModel):
    start_station_id: str
    end_station_id: str
    criteria: Literal["time", "transfers"]  # 다른 값이면 422 INVALID_REQUEST
    lang: str  # ko·en이 아니면 422가 아니라 400 UNSUPPORTED_LANGUAGE로 답하려고 일반 문자열로 받는다
    departure_time: datetime | None = None  # 없으면 서버 현재 시각 (명세 가안, 논의 필요 5)


@router.post("/routes")
def calculate_route(body: RouteRequest, request: Request) -> dict:
    return compute_route(request.app.state.network, body)


def compute_route(network: Network, body: RouteRequest) -> dict:
    """입력 검사 + 경로 계산 + 응답 모양 만들기. POST /explain도 이 함수로 경로를 다시 계산한다."""
    start, end, lang = body.start_station_id, body.end_station_id, body.lang

    # 입력 검사는 API 층이 먼저 한다 (명세 6장). 순서: 언어 → 출발역 → 도착역 → 같은 역
    check_lang(lang)
    check_station(network, start)
    check_station(network, end)
    if start == end:
        raise AppError(400, "SAME_STATION", f"출발역과 도착역이 같습니다: {start}", {"station_id": start})

    try:
        result = find_route(network, start, end, body.criteria)
    except UnknownStationError as e:  # 위에서 이미 막지만, routing이 내는 오류도 같은 모양으로 바꾼다
        raise AppError(400, "STATION_NOT_FOUND", f"존재하지 않는 역입니다: {e}") from e
    except NoRouteError as e:
        raise AppError(
            404, "NO_ROUTE", f"두 역을 잇는 경로가 없습니다: {start} → {end}",
            {"start_station_id": start, "end_station_id": end},
        ) from e

    def ref(station_id: str) -> dict:
        return station_ref(network, station_id, lang)

    departure = body.departure_time or datetime.now(KST).replace(microsecond=0)
    if departure.tzinfo is None:  # 시간대 없이 오면 한국 시간으로 본다
        departure = departure.replace(tzinfo=KST)
    departure = departure.astimezone(KST)

    return {
        "criteria": body.criteria,
        "start": ref(start),
        "end": ref(end),
        "departure_time": departure.isoformat(),
        # 시간표 데이터가 없어 기다리는 시간은 넣지 않는다 (명세 가안, 논의 필요 5)
        "arrival_time": (departure + timedelta(seconds=result.total_sec)).isoformat(),
        "total_sec": result.total_sec,
        "transfer_count": len(result.transfers),
        "cost_won": result.cost_won,
        "segments": [
            {
                "line": segment.line,
                "board": ref(segment.stations[0]),
                "alight": ref(segment.stations[-1]),
                "direction": ref(segment.direction) if segment.direction is not None else None,
                "stations": [ref(station) for station in segment.stations],
                "ride_sec": segment.ride_sec,
            }
            for segment in result.segments
        ],
        "transfers": [
            {"station": ref(t.station), "from_line": t.from_line, "to_line": t.to_line, "sec": t.sec}
            for t in result.transfers
        ],
    }
