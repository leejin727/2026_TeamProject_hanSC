"""GET /stations/{station_id}/facilities 테스트 (주변 시설 AI 예시).

한국어 목록을 먼저 만들고 다른 언어는 그 목록을 번역한다 (2026-11-25). 번역 답의 항목 수·category 순서가
한국어와 다르면 다시 부르는지도 여기서 본다.
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
FIVE_JA = [{**f, "name": "モラン コーヒー", "detail": "2番出口 · 徒歩3分"} for f in FIVE]
FIVE_VI = [{**f, "name": "Cà phê Moran", "detail": "Lối ra 2 · đi bộ 3 phút"} for f in FIVE]
SWAPPED = [FIVE_EN[1], FIVE_EN[0], *FIVE_EN[2:]]  # cafe와 restaurant 순서가 바뀐 번역


class FakeGemini:
    """genai.Client에서 쓰는 부분(client.models.generate_content)만 흉내 낸다.

    answers를 주면 부를 때마다 그 목록에서 차례로 답하고, 다 쓰면 answer로 답한다.
    """

    def __init__(self, answer: object = FIVE, error: Exception | None = None, answers: list | None = None):
        self.models = self
        self.answer = answer
        self.answers = list(answers or [])
        self.error = error
        self.calls = []

    def generate_content(self, model, contents, config):
        self.calls.append({"contents": contents, "system": config.system_instruction,
                           "mime": config.response_mime_type})
        if self.error:
            raise self.error
        answer = self.answers.pop(0) if self.answers else self.answer
        text = answer if isinstance(answer, str) else json.dumps(answer, ensure_ascii=False)
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


def test_other_language_translates_the_korean_list(client, monkeypatch, cache):
    # 언어가 달라도 같은 가게가 보이도록: 한국어 목록을 먼저 만들고(1번째 호출) 그 목록을 번역한다(2번째 호출)
    gemini = use_gemini(monkeypatch, answers=[FIVE, FIVE_JA])
    response = get(client, lang="ja")
    assert response.status_code == 200
    assert response.json()["station"] == {"id": "705", "name": "Moran"}  # ko가 아니면 영어 이름
    assert response.json()["facilities"] == FIVE_JA
    make, translate = gemini.calls
    assert '"station_name_ko": "모란"' in make["contents"]
    assert "모란 커피" in translate["contents"]  # 방금 만든 한국어 목록을 번역한다
    assert '"station_name_en": "Moran"' in translate["contents"]  # 역·지명은 영어 이름을 기준으로
    assert "日本語" in translate["system"]
    assert "katakana" in translate["system"]  # 일본어는 한국 지명을 가타카나로
    assert translate["mime"] == "application/json"  # JSON 모양으로만 답하게 한다
    assert cache == {("705", "ko"): FIVE, ("705", "ja"): FIVE_JA}  # 한국어 목록도 저장한다


def test_saved_korean_list_is_reused_for_every_language(client, monkeypatch, cache):
    cache[("705", "ko")] = FIVE
    gemini = use_gemini(monkeypatch, answers=[FIVE_EN, FIVE_VI])
    assert get(client, lang="en").json()["facilities"] == FIVE_EN
    assert get(client, lang="vi").json()["facilities"] == FIVE_VI
    assert len(gemini.calls) == 2  # 한국어는 다시 만들지 않고 번역만 두 번
    assert all("모란 커피" in call["contents"] for call in gemini.calls)  # 둘 다 같은 한국어 목록에서
    assert "katakana" not in gemini.calls[1]["system"]  # 가타카나 규칙은 일본어에만


# ----- 번역 답 검사 (Gemini 없이 가짜 답으로) -----

def test_check_translation_accepts_same_count_and_order():
    text = json.dumps(FIVE_EN, ensure_ascii=False)
    assert ai_facilities.check_translation(text, FIVE, "en") == FIVE_EN


@pytest.mark.parametrize("answer, reason", [
    (FIVE_EN[:4], "항목 수"),          # 하나가 빠짐
    (FIVE_EN + FIVE_EN[:1], "항목 수"),  # 하나가 더 있음
    (SWAPPED, "category 순서"),         # 순서가 바뀜
    (FIVE, "한글"),                     # 번역하지 않고 한국어 그대로
    ("not json", "모양"),
])
def test_check_translation_rejects_a_list_that_differs_from_korean(answer, reason):
    text = answer if isinstance(answer, str) else json.dumps(answer, ensure_ascii=False)
    with pytest.raises(ValueError, match=reason):
        ai_facilities.check_translation(text, FIVE, "en")


def test_wrong_translation_is_asked_again(client, monkeypatch, cache):
    cache[("705", "ko")] = FIVE
    gemini = use_gemini(monkeypatch, answers=[SWAPPED, FIVE_EN])  # 처음엔 순서가 틀리고 다시 부르면 맞다
    assert get(client, lang="en").json()["facilities"] == FIVE_EN
    assert len(gemini.calls) == 2


def test_translation_still_wrong_returns_503_and_is_not_saved(client, monkeypatch, cache):
    cache[("705", "ko")] = FIVE
    gemini = use_gemini(monkeypatch, answer=FIVE_EN[:4])  # 몇 번을 불러도 하나가 빠진 답
    assert error(get(client, lang="en")) == (503, "AI_UNAVAILABLE", None)
    assert len(gemini.calls) == ai_facilities.TRANSLATE_TRIES
    assert ("705", "en") not in cache


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
    # 실제로 ja 요청에 한국어로 답한 적이 있다. 번역이 한국어 그대로 오면 저장하지 않고 503
    use_gemini(monkeypatch, answer=FIVE)  # 한국어 만들기도, 번역도 한국어(FIVE)로 온다
    assert error(get(client, lang="ja")) == (503, "AI_UNAVAILABLE", None)
    assert cache == {("705", "ko"): FIVE}  # 번역 원본인 한국어 목록만 남는다
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
