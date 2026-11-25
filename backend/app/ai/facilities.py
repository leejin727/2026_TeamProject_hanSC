"""GET /stations/{station_id}/facilities 처리: 캐시 조회 → 없으면 Gemini로 예시 생성 → 저장 → 응답.

주변 시설은 AI가 만든 예시다. 앱 화면에는 이 사실을 표시하지 않고, API의 ai_generated 값으로만 구분한다
(2026-11-25 이진 결정. 예시를 쓰기로 한 처음 결정은 ASSUMPTIONS.md 팀 결정 2026-11-18).

언어가 달라도 같은 가게가 보이도록, 한국어 목록을 먼저 만들고 다른 언어는 그 목록을 번역한다 (2026-11-25).
예전에는 언어마다 따로 만들어서, 같은 역의 카페가 한국어·영어·일본어에서 서로 다른 가게였다.
"""

import logging
import re
from typing import Literal

import psycopg
from psycopg.types.json import Jsonb
from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, ValidationError

from app.ai import client, prompts
from app.api.common import check_station, station_ref
from app.config import MissingSettingError
from app.db.connection import connect
from app.errors import AppError
from app.routing.graph_builder import Network

logger = logging.getLogger("subfit")

FACILITY_LANGS = tuple(prompts.LANGUAGES)  # ko, en, ja, zh-Hans, zh-Hant, vi

# 번역 답의 항목 수·category 순서가 한국어와 다르거나 한글이 섞이면, 이 횟수까지 다시 부른다
TRANSLATE_TRIES = 2


class Facility(BaseModel):
    """시설 하나. Gemini에게 이 모양으로만 답하게 한다."""

    model_config = ConfigDict(str_strip_whitespace=True)  # 앞뒤 빈칸은 지운다 (실제로 " チョンホ薬局"이 온 적 있음)

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
        try:
            if lang == "ko":
                items = generate_korean(name_ko)
            else:
                items = translate(_korean_list(station_id, name_ko), name_en, lang)
        except (MissingSettingError, client.AIUnavailableError, ValueError) as e:
            logger.warning("주변 시설 생성 실패: %s", e)  # 원인(키 없음, 시간 초과, 모양 틀림)은 서버 로그에만
            raise AppError(503, "AI_UNAVAILABLE", "지금은 주변 시설 정보를 만들 수 없습니다") from e
        save_cached(station_id, lang, items)

    return {"station": station, "facilities": items, "ai_generated": True, "cached": cached}


def _korean_list(station_id: str, name_ko: str) -> list[dict]:
    """번역할 한국어 목록. 저장된 것이 있으면 그대로 쓰고, 없으면 만들어 저장한다."""
    korean = load_cached(station_id, "ko")
    if korean is None:
        korean = generate_korean(name_ko)
        save_cached(station_id, "ko", korean)
    return korean


def generate_korean(name_ko: str) -> list[dict]:
    """Gemini로 역 하나의 한국어 시설 예시를 만든다. 다른 언어는 이 목록을 번역한다 (translate).

    서버와 미리 만들기 스크립트(scripts/generate_facilities.py)가 같이 쓴다.
    키가 없으면 MissingSettingError, Gemini 실패는 client.AIUnavailableError, 답이 틀리면 ValueError.
    """
    system_prompt, user_prompt = prompts.facilities_prompt(name_ko)
    text = client.generate_json(system_prompt, user_prompt, list[Facility])
    return _clean(text)


def translate(korean: list[dict], name_en: str, lang: str) -> list[dict]:
    """한국어 목록을 [lang]으로 옮긴다. 항목 수·순서·category는 그대로 두고 name과 detail만 바꾼다.

    답이 틀리면(check_translation) TRANSLATE_TRIES번까지 다시 부르고, 그래도 틀리면 ValueError.
    Gemini 호출 자체가 실패하면 client.AIUnavailableError (다시 부르지 않는다).
    """
    system_prompt, user_prompt = prompts.facilities_translate_prompt(korean, name_en, lang)
    for attempt in range(1, TRANSLATE_TRIES + 1):
        text = client.generate_json(system_prompt, user_prompt, list[Facility])
        try:
            return check_translation(text, korean, lang)
        except ValueError as e:
            if attempt == TRANSLATE_TRIES:
                raise
            logger.warning("주변 시설 번역 답이 틀려서 다시 부름 (%s): %s", lang, e)
    raise AssertionError("여기에는 오지 않는다")


_HANGUL = re.compile(r"[가-힣ㄱ-ㆎ]")  # 한글 글자·자모


def check_translation(text: str, korean: list[dict], lang: str) -> list[dict]:
    """번역 답을 검사한다: 항목 수와 category 순서가 한국어와 같아야 하고, 한글이 섞이면 안 된다.

    틀리면 ValueError (저장하지 않는다).
    """
    try:
        parsed = _FACILITY_LIST.validate_json(text)
    except ValidationError as e:
        raise ValueError(f"번역 답의 모양이 틀립니다: {e.errors()[0]['msg']}") from e
    if len(parsed) != len(korean):
        raise ValueError(f"번역 답의 항목 수({len(parsed)})가 한국어({len(korean)})와 다릅니다")
    got = [f.category for f in parsed]
    if got != [k["category"] for k in korean]:
        raise ValueError(f"번역 답의 category 순서가 한국어와 다릅니다: {got}")
    mixed = [f.name for f in parsed if _HANGUL.search(f.name + f.detail)]
    if mixed:
        # 따로 만들던 때 ja 요청에 한국어로 답한 적이 있다 (2026-11-18). 번역에서도 같은 실수를 막는다
        raise ValueError(f"{lang}로 요청했는데 한글이 섞인 답이 왔습니다: {mixed[0]}")
    return [f.model_dump() for f in parsed]


def _clean(text: str) -> list[dict]:
    """한국어 답을 확인하고 정리한다: 종류마다 1개만, 항상 같은 순서. 하나도 없으면 ValueError."""
    try:
        parsed = _FACILITY_LIST.validate_json(text)
    except ValidationError as e:
        raise ValueError(f"Gemini 답의 모양이 틀립니다: {e.errors()[0]['msg']}") from e
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
