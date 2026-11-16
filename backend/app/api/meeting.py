"""POST /meeting-station — 기존 API 명세를 확장한 모임역 추천."""
from typing import Literal
from fastapi import APIRouter, Request
from pydantic import BaseModel, StrictStr
from app.api.common import check_lang, check_station, station_ref
from app.errors import AppError
from app.routing.meeting import find_meeting_station, NoMeetingStationError

router = APIRouter()

class MeetingRequest(BaseModel):
    start_station_ids: list[StrictStr]
    criteria: Literal["time", "transfers", "fairness"]
    lang: str

@router.post("/meeting-station")
def calculate_meeting_station(body: MeetingRequest, request: Request) -> dict:
    network = request.app.state.network
    check_lang(body.lang)
    count = len(body.start_station_ids)
    if not 2 <= count <= 4:
        raise AppError(400, "INVALID_PARTICIPANT_COUNT", "참여자는 2~4명이어야 합니다",
                       {"count": count, "min": 2, "max": 4})
    for start in body.start_station_ids:
        check_station(network, start)
    try:
        result = find_meeting_station(network, body.start_station_ids, body.criteria)
    except NoMeetingStationError as exc:
        raise AppError(404, "NO_MEETING_STATION", "모든 참여자가 도달할 수 있는 모임역이 없습니다") from exc

    def ref(station):
        return station_ref(network, station, body.lang)

    return {
        "criteria": result.criteria,
        "station": ref(result.station),
        "participants": [
            {
                "start": ref(p.start),
                "travel_sec": p.travel_sec,
                "transfer_count": p.transfer_count,
                "stations": [ref(s) for s in p.stations],
                "segments": [
                    {"line": s.line, "board": ref(s.stations[0]), "alight": ref(s.stations[-1]),
                     "direction": None, "stations": [ref(x) for x in s.stations], "ride_sec": s.ride_sec}
                    for s in p.segments
                ],
                "transfers": [
                    {"station": ref(t.station), "from_line": t.from_line,
                     "to_line": t.to_line, "sec": t.sec} for t in p.transfers
                ],
            } for p in result.participants
        ],
        "total_travel_sec": result.total_travel_sec,
        "total_transfer_count": result.total_transfer_count,
        "max_travel_sec": result.max_travel_sec,
        "nearby_facilities": [],
    }
