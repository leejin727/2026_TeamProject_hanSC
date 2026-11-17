"""GET /stations/{station_id}/facilities 처리: 캐시 조회 → 없으면 Gemini로 예시 생성 → 저장 → 응답.

주변 시설은 실제 데이터가 아니라, 실제 역 이름을 바탕으로 AI가 만든 예시다 (ASSUMPTIONS.md 팀 결정 2026-11-18).
그래서 응답에 "ai_generated": true를 넣고, 앱은 "실제와 다를 수 있음"을 함께 보여 준다.
"""

import logging
import re
from typing import Literal

import psycopg
from psycopg.types.json import Jsonb
from pydantic import BaseModel, Field, TypeAdapter, ValidationError

from app.ai import client, prompts
from app.api.common import check_station, station_ref
from app.config import MissingSettingError
from app.db.connection import connect
from app.errors import AppError
from app.routing.graph_builder import Network

logger = logging.getLogger("subfit")

FACILITY_LANGS = tuple(prompts.LANGUAGES)  # ko, en, ja, zh-Hans, zh-Hant, vi


class Facility(BaseModel):
    """시설 하나. Gemini에게 이 모양으로만 답하게 한다."""

    category: Literal["cafe", "restaurant", "convenience_store", "pharmacy", "restroom"]
    name: str = Field(min_length=1, max_length=60)
    detail: str = Field(min_length=1, max_length=80)  # 예: "2번 출구 · 도보 3분"


_FACILITY_LIST = TypeAdapter(list[Facility])


def facilities(network: Network, station_id: str, lang: str) -> dict:
    if lang not in FACILITY_LANGS:
        raise AppError(400, "VALIDATION_ERROR", f"지원하지 않는 언어입니다: {lang}",
                       {"field": "lang", "supported": list(FACILITY_LANGS)})
    check_station(network, station_id)  # 없는 역 → 400 STATION_NOT_FOUND

    # 역 이름 데이터는 한국어·영어만 있다. 다른 언어로 볼 때는 영어 이름을 보여 준다.
    station = station_ref(network, station_id, "ko" if lang == "ko" else "en")

    items = load_cached(station_id, lang)
    cached = items is not None
    if items is None:
        name_ko, name_en = network.names[station_id]
        system_prompt, user_prompt = prompts.facilities_prompt(name_ko, name_en, lang)
        try:
            text = client.generate_json(system_prompt, user_prompt, list[Facility])
            items = _clean(text, lang)
        except (MissingSettingError, client.AIUnavailableError, ValueError) as e:
            logger.warning("주변 시설 생성 실패: %s", e)  # 원인(키 없음, 시간 초과, 모양 틀림)은 서버 로그에만
            raise AppError(503, "AI_UNAVAILABLE", "지금은 주변 시설 정보를 만들 수 없습니다") from e
        save_cached(station_id, lang, items)

    return {"station": station, "facilities": items, "ai_generated": True, "cached": cached}


_HANGUL = re.compile(r"[가-힣ㄱ-ㆎ]")  # 한글 글자·자모


def _clean(text: str, lang: str) -> list[dict]:
    """Gemini 답을 확인하고 정리한다: 종류마다 1개만, 항상 같은 순서.

    하나도 없거나, 한국어가 아닌 언어인데 한글이 섞였으면 ValueError (저장하지 않는다).
    """
    try:
        parsed = _FACILITY_LIST.validate_json(text)
    except ValidationError as e:
        raise ValueError(f"Gemini 답의 모양이 틀립니다: {e.errors()[0]['msg']}") from e
    if lang != "ko" and any(_HANGUL.search(f.name + f.detail) for f in parsed):
        # 실제로 ja 요청에 한국어로 답한 적이 있다 (2026-11-18)
        raise ValueError(f"{lang}로 요청했는데 한글이 섞인 답이 왔습니다")
    first = {}
    for facility in parsed:
        first.setdefault(facility.category, facility)
    items = [first[c].model_dump() for c in prompts.FACILITY_CATEGORIES if c in first]
    if not items:
        raise ValueError("Gemini가 시설을 하나도 주지 않았습니다")
    return items


# ----- ai_facilities 테이블 (schema.sql). DB를 못 쓰면 캐시 없이 계속 진행한다 -----

def load_cached(station_id: str, lang: str) -> list[dict] | None:
    try:
        with connect() as conn:
            row = conn.execute(
                "SELECT items FROM ai_facilities WHERE station_id = %s AND lang = %s", (station_id, lang)
            ).fetchone()
    except (psycopg.Error, MissingSettingError) as e:
        logger.warning("주변 시설 캐시 조회 실패 (캐시 없이 진행): %s", e)
        return None
    return row[0] if row else None


def save_cached(station_id: str, lang: str, items: list[dict]) -> None:
    try:
        with connect() as conn:
            conn.execute(
                "INSERT INTO ai_facilities (station_id, lang, items) VALUES (%s, %s, %s) "
                "ON CONFLICT (station_id, lang) DO NOTHING",
                (station_id, lang, Jsonb(items)),
            )
    except (psycopg.Error, MissingSettingError) as e:
        logger.warning("주변 시설 캐시 저장 실패: %s", e)
