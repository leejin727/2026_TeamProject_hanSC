"""POST /explain — 경로·모임역 결과를 AI가 문장으로 설명한다."""

from fastapi import APIRouter, Request
from pydantic import BaseModel

from app.ai.explain import explain

router = APIRouter()


class ExplainRequest(BaseModel):
    # type·lang은 잘못된 값을 422가 아니라 400 VALIDATION_ERROR로 답하려고 일반 문자열로 받는다
    type: str      # "route" | "meeting"
    request: dict  # 그 API(/routes, /meeting-station)에 보낸 요청 본문 그대로
    lang: str      # 설명 언어: ko, en, ja, zh-Hans, zh-Hant, vi


@router.post("/explain")
def explain_result(body: ExplainRequest, request: Request) -> dict:
    return explain(request.app.state.network, body.type, body.request, body.lang)
