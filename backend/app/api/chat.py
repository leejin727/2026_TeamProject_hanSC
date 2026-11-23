"""POST /chat — 챗봇 (docs/api-spec.md 4-2장). 답은 app/chat/service.py가 만든다."""

from typing import Annotated

from fastapi import APIRouter, Request
from pydantic import BaseModel, StringConstraints

from app.ai.prompts import LANGUAGES
from app.api.common import check_station
from app.chat import service
from app.errors import AppError

router = APIRouter()

CHAT_LANGS = tuple(LANGUAGES)  # 앱의 언어 설정 6가지. 답 문구는 ko·en뿐이라 나머지 언어에는 영어로 답한다
MAX_MESSAGE_LENGTH = 300       # 글자 수. 모델은 어차피 앞부분만 읽는다


class ChatRequest(BaseModel):
    # 앞뒤 빈칸을 뗀 뒤 비어 있거나 너무 길면 422 INVALID_REQUEST
    message: Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=MAX_MESSAGE_LENGTH)]
    lang: str  # 6가지가 아니면 422가 아니라 400 VALIDATION_ERROR로 답하려고 일반 문자열로 받는다
    context: service.Context | None = None  # 직전 응답의 context. 첫 메시지에는 없다


@router.post("/chat")
def chat(body: ChatRequest, request: Request) -> dict:
    network = request.app.state.network
    if body.lang not in CHAT_LANGS:
        raise AppError(400, "VALIDATION_ERROR", f"지원하지 않는 언어입니다: {body.lang}",
                       {"field": "lang", "supported": list(CHAT_LANGS)})
    context = body.context or service.Context()
    for station_id in (context.start, context.end):
        if station_id is not None:
            check_station(network, station_id)  # 없는 역 → 400 STATION_NOT_FOUND
    return service.reply(network, body.message, body.lang, context)
