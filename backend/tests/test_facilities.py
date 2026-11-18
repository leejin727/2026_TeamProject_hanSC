"""GET /stations/{station_id}/facilities 테스트 (주변 시설 AI 예시).

진짜 Gemini와 진짜 DB는 부르지 않는다. 그래서 API 키나 PostgreSQL이 없는 컴퓨터에서도 통과한다.
- Gemini: client._get_facility_client를 가짜(FakeGemini)로 바꾼다
- 캐시: load_cached/save_cached를 메모리 사전으로 바꾼다
"""

import json
import logging
from types import SimpleNamespace

import httpx2
import pytest
from fastapi.testclient import TestClient

from app.ai import client as ai_client
from app.ai import facilities as ai_facilities
from app.main import app

FIVE = [
    {"category": "cafe", "name": "모란 커피", "detail": "2번 출구 · 도보 3분"},
    {"category": "restaurant", "name": "모란 국밥", "detail": "4번 출구 · 도보 5분"},
    {"category": "convenience_store", "name": "GS25 모란역점", "detail": "1번 출구 · 도보 1분"},
    {"category": "pharmacy", "name": "모란 약국", "detail": "3번 출구 · 도보 2분"},
    {"category": "restroom", "name": "공중화장실", "detail": "역 안 · 대합실"},
]
FIVE_EN = [{**f, "name": "Moran Coffee", "detail": "Exit 2 · 3 min walk"} for f in FIVE]  # 한글 없는 답


class FakeGemini:
    """genai.Client에서 쓰는 부분(client.models.generate_content)만 흉내 낸다."""

    def __init__(self, answer: object = FIVE, error: Exception | None = None):
        self.models = self
        self.answer = answer
        self.error = error
        self.calls = []

    def generate_content(self, model, contents, config):
        self.calls.append({"contents": contents, "system": config.system_instruction,
                           "mime": config.response_mime_type})
        if self.error:
            raise self.error
        text = self.answer if isinstance(self.answer, str) else json.dumps(self.answer, ensure_ascii=False)
        return SimpleNamespace(text=text)


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(autouse=True)
def cache(monkeypatch):
    store = {}
    monkeypatch.setattr(ai_facilities, "load_cached", lambda sid, lang: store.get((sid, lang)))
    monkeypatch.setattr(ai_facilities, "save_cached", lambda sid, lang, items: store.setdefault((sid, lang), items))
    return store


def use_gemini(monkeypatch, **kwargs) -> FakeGemini:
    fake = FakeGemini(**kwargs)
    monkeypatch.setattr(ai_client, "_get_facility_client", lambda: fake)
    return fake


def get(client, station_id="705", lang="ko"):
    return client.get(f"/stations/{station_id}/facilities", params={"lang": lang} if lang else None)


def error(response):
    err = response.json()["error"]
    return response.status_code, err["code"], err.get("details")


# ----- 정상 + 캐시 -----

def test_first_call_generates_then_cached(client, monkeypatch):
    gemini = use_gemini(monkeypatch)
    first = get(client)
    assert first.status_code == 200
    assert first.json() == {
        "station": {"id": "705", "name": "모란"},
        "facilities": FIVE,
        "ai_generated": True,
        "cached": False,
    }
    second = get(client)
    assert second.json()["cached"] is True
    assert second.json()["facilities"] == FIVE
    assert len(gemini.calls) == 1  # 두 번째는 Gemini를 부르지 않는다


def test_prompt_uses_station_names_and_language(client, monkeypatch):
    gemini = use_gemini(monkeypatch, answer=FIVE_EN)
    response = get(client, lang="ja")
    assert response.json()["station"] == {"id": "705", "name": "Moran"}  # ko가 아니면 영어 이름
    call = gemini.calls[0]
    # 한국어가 아니면 영어 역 이름만 주고, 프롬프트에 한글을 한 글자도 넣지 않는다
    # (한국어 이름이나 한국어 프롬프트를 주면 답에 한글이 섞이는 일이 잦았다)
    assert '"station_name_en": "Moran"' in call["contents"]
    assert not ai_facilities._HANGUL.search(call["system"] + call["contents"])
    assert "日本語" in call["system"]
    assert "katakana" in call["system"]  # 일본어는 한국 지명을 가타카나로
    assert call["mime"] == "application/json"  # JSON 모양으로만 답하게 한다

    get(client, lang="ko")
    assert '"station_name_ko": "모란"' in gemini.calls[1]["contents"]
    get(client, lang="vi")
    assert "katakana" not in gemini.calls[2]["system"]  # 가타카나 규칙은 일본어에만


def test_answer_is_cleaned_one_per_category_in_fixed_order(client, monkeypatch):
    messy = [FIVE[4], {**FIVE[0], "name": " 모란 커피  "}, {**FIVE[0], "name": "두 번째 카페"}, FIVE[2]]
    use_gemini(monkeypatch, answer=messy)
    items = get(client).json()["facilities"]
    assert [i["category"] for i in items] == ["cafe", "convenience_store", "restroom"]
    assert items[0]["name"] == "모란 커피"  # 같은 종류가 여러 개면 첫 번째만, 앞뒤 빈칸은 지운다


# ----- 오류 -----

@pytest.mark.parametrize("bad_answer", ["not json", "[]", json.dumps([{"category": "bar", "name": "x", "detail": "y"}])])
def test_bad_answer_returns_503_and_is_not_cached(client, monkeypatch, cache, bad_answer):
    use_gemini(monkeypatch, answer=bad_answer)
    assert error(get(client)) == (503, "AI_UNAVAILABLE", None)
    assert cache == {}


def test_korean_answer_for_other_language_is_rejected(client, monkeypatch, cache):
    # 실제로 ja 요청에 한국어로 답한 적이 있다. 그런 답은 저장하지 않고 503
    use_gemini(monkeypatch, answer=FIVE)
    assert error(get(client, lang="ja")) == (503, "AI_UNAVAILABLE", None)
    assert cache == {}
    use_gemini(monkeypatch, answer=FIVE_EN)
    assert get(client, lang="ja").status_code == 200  # 한글만 없으면 통과 (영어 고유명사는 허용)


def test_timeout_returns_503(client, monkeypatch):
    use_gemini(monkeypatch, error=httpx2.ReadTimeout("timed out"))
    assert error(get(client)) == (503, "AI_UNAVAILABLE", None)


def test_missing_facility_key_returns_503_without_using_explain_key(client, monkeypatch, caplog):
    caplog.set_level(logging.WARNING, logger="subfit")
    monkeypatch.setenv("GEMINI_API_KEY", "explain-key-is-set")  # 설명용 키가 있어도
    monkeypatch.setenv("GEMINI_FACILITY_API_KEY", "")           # 시설용 키가 없으면 대신 쓰지 않는다
    monkeypatch.setattr(ai_client, "_facility_client", None)
    response = get(client)
    assert error(response) == (503, "AI_UNAVAILABLE", None)
    assert "GEMINI_FACILITY_API_KEY" not in response.text  # 원인은 응답이 아니라
    assert "GEMINI_FACILITY_API_KEY" in caplog.text        # 서버 로그에만 남긴다


def test_unknown_station_bad_lang_and_missing_lang(client, monkeypatch):
    gemini = use_gemini(monkeypatch)
    assert error(get(client, station_id="999")) == (400, "STATION_NOT_FOUND", {"station_id": "999"})
    code, name, details = error(get(client, lang="fr"))
    assert (code, name, details["field"]) == (400, "VALIDATION_ERROR", "lang")
    code, name, details = error(get(client, lang=None))
    assert (code, name, details) == (422, "INVALID_REQUEST", {"field": "lang"})
    assert gemini.calls == []
