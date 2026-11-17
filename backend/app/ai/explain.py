"""POST /explain 처리: 서버가 결과를 다시 계산 → 캐시 조회 → 없으면 Gemini 호출 → 저장 → 응답."""

import hashlib
import json
import logging

import psycopg
from pydantic import BaseModel, ValidationError

from app.ai import client, prompts
from app.api.meeting import MeetingRequest, compute_meeting
from app.api.routes import RouteRequest, compute_route
from app.config import MissingSettingError
from app.db.connection import connect
from app.errors import AppError
from app.routing.graph_builder import Network

logger = logging.getLogger("subfit")

# type별로 (요청 모양, 다시 계산하는 함수, 프롬프트 만드는 함수). 계산 함수는 해당 API와 같은 것을 쓴다.
_HANDLERS = {
    "route": (RouteRequest, compute_route, prompts.route_prompt),        # POST /routes
    "meeting": (MeetingRequest, compute_meeting, prompts.meeting_prompt),  # POST /meeting-station
}
EXPLAIN_TYPES = tuple(_HANDLERS)  # route, meeting
EXPLAIN_LANGS = tuple(prompts.LANGUAGES)  # ko, en, ja, zh-Hans, zh-Hant, vi


def explain(network: Network, type_: str, request: dict, lang: str) -> dict:
    if type_ not in EXPLAIN_TYPES:
        raise AppError(400, "VALIDATION_ERROR", f"지원하지 않는 type입니다: {type_}",
                       {"field": "type", "supported": list(EXPLAIN_TYPES)})
    if lang not in EXPLAIN_LANGS:
        raise AppError(400, "VALIDATION_ERROR", f"지원하지 않는 설명 언어입니다: {lang}",
                       {"field": "lang", "supported": list(EXPLAIN_LANGS)})
    request_model, compute, make_prompt = _HANDLERS[type_]

    body = _parse_request(request_model, request)
    # 앱이 보낸 결과는 믿지 않는다. 같은 요청으로 서버가 경로·모임역을 다시 계산한다.
    # (없는 역 → 400 STATION_NOT_FOUND 등 /routes·/meeting-station과 같은 검사도 여기서 한다)
    result = compute(network, body)

    key = cache_key(type_, _normalize(body), lang)
    cached = load_cached(key, lang)
    if cached is not None:
        return {"explanation": cached, "cached": True}

    system_prompt, user_prompt = make_prompt(result, lang)
    try:
        text = client.generate(system_prompt, user_prompt)
    except (MissingSettingError, client.AIUnavailableError) as e:
        logger.warning("AI 설명 실패: %s", e)  # 원인(키 없음, 시간 초과 등)은 서버 로그에만 남긴다
        raise AppError(503, "AI_UNAVAILABLE", "지금은 AI 설명을 만들 수 없습니다") from e

    save_cached(key, lang, type_, text)
    return {"explanation": text, "cached": False}


def _parse_request(request_model: type[BaseModel], request: dict) -> BaseModel:
    try:
        return request_model.model_validate(request)
    except ValidationError as e:
        first = e.errors()[0]
        field = "request." + ".".join(str(part) for part in first["loc"])
        raise AppError(400, "VALIDATION_ERROR", f"요청 값이 올바르지 않습니다 ({field}): {first['msg']}",
                       {"field": field}) from e


def _normalize(body: BaseModel) -> str:
    """캐시 키용으로 요청을 항상 같은 글자로 바꾼다 (키 순서 고정, 공백 없음).

    경로의 departure_time은 설명에 쓰지 않으므로 뺀다 → 출발 시각만 다른 같은 경로는 설명을 같이 쓴다.
    모임역 출발역은 순서를 그대로 둔다 (설명에서 참여자를 요청 순서대로 말하기 때문).
    """
    data = body.model_dump(exclude={"departure_time"})
    return json.dumps(data, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def cache_key(type_: str, normalized_request: str, lang: str) -> str:
    return hashlib.sha256(f"{type_}\n{normalized_request}\n{lang}".encode("utf-8")).hexdigest()


# ----- ai_explanations 테이블 (schema.sql). DB를 못 쓰면 캐시 없이 계속 진행한다 -----

def load_cached(key: str, lang: str) -> str | None:
    try:
        with connect() as conn:
            row = conn.execute(
                "SELECT text FROM ai_explanations WHERE cache_key = %s AND lang = %s", (key, lang)
            ).fetchone()
    except (psycopg.Error, MissingSettingError) as e:
        logger.warning("설명 캐시 조회 실패 (캐시 없이 진행): %s", e)
        return None
    return row[0] if row else None


def save_cached(key: str, lang: str, type_: str, text: str) -> None:
    try:
        with connect() as conn:
            conn.execute(
                "INSERT INTO ai_explanations (cache_key, lang, type, text) VALUES (%s, %s, %s, %s) "
                "ON CONFLICT (cache_key, lang) DO NOTHING",
                (key, lang, type_, text),
            )
    except (psycopg.Error, MissingSettingError) as e:
        logger.warning("설명 캐시 저장 실패: %s", e)
