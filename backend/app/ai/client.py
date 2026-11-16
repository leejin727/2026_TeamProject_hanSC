"""Gemini 호출 (google-genai 라이브러리). 키는 서버의 .env에서만 읽는다 (AGENTS.md 보안)."""

from google import genai
from google.genai import types

from app.config import get_gemini_api_key, get_gemini_model

# 명세: AI 설명 5초 이하. 우리 쪽 연결을 5초에 끊는다 (라이브러리 기본값은 재시도 안 함 → 전체 5초).
TIMEOUT_MS = 5000
# 라이브러리는 timeout 값을 X-Server-Timeout 헤더로 Gemini 서버에도 보내는데,
# 서버는 10초 미만이면 400("Minimum allowed deadline is 10s")으로 모든 요청을 거절한다.
# 헤더를 직접 넣어 두면 라이브러리가 덮어쓰지 않으므로, 서버에는 최소값 10초를 알려 준다.
SERVER_DEADLINE_HEADER = {"X-Server-Timeout": "10"}


class AIUnavailableError(Exception):
    """Gemini 호출 실패: 시간 초과, 키 오류, 사용량 초과, 빈 응답 등."""


_client: genai.Client | None = None


def _get_client() -> genai.Client:
    """처음 부를 때 한 번만 만든다. 키가 없으면 MissingSettingError가 난다."""
    global _client
    if _client is None:
        _client = genai.Client(
            api_key=get_gemini_api_key(),
            http_options=types.HttpOptions(timeout=TIMEOUT_MS, headers=SERVER_DEADLINE_HEADER),
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
                # 생각(thinking)을 짧게 해서 5초 안에 답하게 한다
                thinking_config=types.ThinkingConfig(thinking_level=types.ThinkingLevel.LOW),
            ),
        )
    except Exception as e:  # 시간 초과(httpx2.TimeoutException), API 오류(google.genai.errors.APIError) 등
        raise AIUnavailableError(f"{type(e).__name__}: {e}") from e

    text = (response.text or "").strip()
    if not text:
        raise AIUnavailableError("Gemini가 빈 응답을 보냈습니다")
    return text
