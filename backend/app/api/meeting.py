"""POST /meeting-station — 모임역 추천 (docs/api-spec.md 3장).

모임역을 고르는 알고리즘(find_meeting_station)은 표혜정 님이 routing에 만든다 (명세 6장 모양,
기준 계산식은 data/extra/ASSUMPTIONS.md). 그 전까지는 입력 검사를 통과한 요청에 501로 답한다.
"""

from typing import Literal

from fastapi import APIRouter, Request
from pydantic import BaseModel

from app.api.common import check_lang, check_station, station_ref
from app.errors import AppError
from app.routing.graph_builder import Network

router = APIRouter()

MIN_PARTICIPANTS = 2
MAX_PARTICIPANTS = 4


class MeetingRequest(BaseModel):
    start_station_ids: list[str]  # 사람별 출발역. 같은 역을 여러 번 넣어도 된다 (ASSUMPTIONS.md)
    criteria: Literal["time", "transfers", "fairness"]  # 다른 값이면 422 INVALID_REQUEST
    lang: str  # ko·en이 아니면 400 UNSUPPORTED_LANGUAGE로 답하려고 일반 문자열로 받는다 (routes.py와 같음)


def find_meeting_station(network: Network, starts: list[str], criteria: str):
    # TODO(S09a): 표혜정 님이 routing에 find_meeting_station을 만들면 이 함수를 지우고
    # 그 함수를 import한다. 결과는 명세 6장의 MeetingResult 모양 (station, participants).
    raise AppError(501, "NOT_IMPLEMENTED", "모임역 계산은 아직 준비 중입니다")


@router.post("/meeting-station")
def recommend_meeting_station(body: MeetingRequest, request: Request) -> dict:
    return compute_meeting(request.app.state.network, body)


def compute_meeting(network: Network, body: MeetingRequest) -> dict:
    """입력 검사 + 모임역 계산 + 응답 모양 만들기."""
    starts, lang = body.start_station_ids, body.lang

    # 입력 검사는 API 층이 먼저 한다 (명세 6장). 순서: 언어 → 인원 수 → 출발역(요청 순서대로)
    check_lang(lang)
    count = len(starts)
    if not MIN_PARTICIPANTS <= count <= MAX_PARTICIPANTS:
        raise AppError(
            400, "INVALID_PARTICIPANT_COUNT",
            f"출발역은 {MIN_PARTICIPANTS}~{MAX_PARTICIPANTS}개여야 합니다: {count}개",
            {"count": count, "min": MIN_PARTICIPANTS, "max": MAX_PARTICIPANTS},
        )
    for station in starts:
        check_station(network, station)

    result = find_meeting_station(network, starts, body.criteria)

    def ref(station_id: str) -> dict:
        return station_ref(network, station_id, lang)

    return {
        "criteria": body.criteria,
        "station": ref(result.station),
        # 알고리즘이 요청 순서 그대로 돌려준다 (명세 6장). 여기서 순서를 바꾸지 않는다.
        "participants": [
            {"start": ref(p.start), "travel_sec": p.travel_sec, "transfer_count": p.transfer_count}
            for p in result.participants
        ],
        "nearby_facilities": [],  # 주변 시설 데이터가 없어 항상 빈 목록 (명세 논의 필요 4)
    }
