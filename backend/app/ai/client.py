"""Gemini 호출 (google-genai 라이브러리). 키는 서버의 .env에서만 읽는다 (AGENTS.md 보안)."""

from google import genai
from google.genai import types

from app.config import get_gemini_api_key, get_gemini_facility_api_key, get_gemini_model

# AI 설명 제한 12초 (팀 결정 2026-11-18). 처음 목표는 5초였지만, Gemini가 느린 때에는
# 5~11초가 걸려 5초 제한으로는 설명이 거의 실패했다. 앱은 경로를 먼저 보여 주고 설명만 따로 기다린다.
# 라이브러리 기본값은 재시도 안 함 → 전체 12초. 이 값은 Gemini 서버에도 전달되는데,
# 서버는 10초 미만이면 400("Minimum allowed deadline is 10s")으로 거절하므로 10초 아래로 내리지 않는다.
TIMEOUT_MS = 12_000


class AIUnavailableError(Exception):
    """Gemini 호출 실패: 시간 초과, 키 오류, 사용량 초과, 빈 응답 등."""


_client: genai.Client | None = None


def _get_client() -> genai.Client:
    """처음 부를 때 한 번만 만든다. 키가 없으면 MissingSettingError가 난다."""
    global _client
    if _client is None:
        _client = genai.Client(
            api_key=get_gemini_api_key(),
            http_options=types.HttpOptions(timeout=TIMEOUT_MS),
        )
    return _client


def generate(system_prompt: str, user_prompt: str) -> str:
    """Gemini에게 설명 문장을 받아 온다.

    키가 없으면 MissingSettingError, 그 밖의 실패는 AIUnavailableError를 낸다.
    """
    client = _get_client()
    try:
        response = client.models.generate_content(
            model=get_gemini_model(),
            contents=user_prompt,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                temperature=0.3,  # 같은 입력이면 비슷한 문장이 나오도록 낮게
                # 생각(thinking)을 짧게 해서 빨리 답하게 한다
                thinking_config=types.ThinkingConfig(thinking_level=types.ThinkingLevel.LOW),
            ),
        )
    except Exception as e:  # 시간 초과(httpx2.TimeoutException), API 오류(google.genai.errors.APIError) 등
        raise AIUnavailableError(f"{type(e).__name__}: {e}") from e

    text = (response.text or "").strip()
    if not text:
        raise AIUnavailableError("Gemini가 빈 응답을 보냈습니다")
    return text


# ----- 주변 시설(AI 예시)용. 설명과 다른 키를 쓴다 (GEMINI_FACILITY_API_KEY) -----

_facility_client: genai.Client | None = None


def _get_facility_client() -> genai.Client:
    """처음 부를 때 한 번만 만든다. 키가 없으면 MissingSettingError가 난다."""
    global _facility_client
    if _facility_client is None:
        _facility_client = genai.Client(
            api_key=get_gemini_facility_api_key(),
            http_options=types.HttpOptions(timeout=TIMEOUT_MS),
        )
    return _facility_client


def generate_json(system_prompt: str, user_prompt: str, schema: object) -> str:
    """Gemini에게 [schema] 모양의 JSON 글자를 받아 온다 (주변 시설용 키 사용).

    모양이 맞는지는 부르는 쪽에서 다시 확인한다. 실패는 generate()와 같은 오류를 낸다.
    """
    client = _get_facility_client()
    try:
        response = client.models.generate_content(
            model=get_gemini_model(),
            contents=user_prompt,
            config=types.GenerateContentConfig(
                system_instruction=system_prompt,
                temperature=0.7,  # 예시 시설 이름이 역마다 너무 비슷하지 않게 조금 높인다
                response_mime_type="application/json",  # JSON으로만 답하게 한다
                response_schema=schema,
                thinking_config=types.ThinkingConfig(thinking_level=types.ThinkingLevel.LOW),
            ),
        )
    except Exception as e:  # 시간 초과, API 오류 등
        raise AIUnavailableError(f"{type(e).__name__}: {e}") from e

    text = (response.text or "").strip()
    if not text:
        raise AIUnavailableError("Gemini가 빈 응답을 보냈습니다")
    return text
