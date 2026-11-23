"""POST /chat 테스트 (docs/api-spec.md 4-2장).

- 대화 테스트는 진짜 모델로 주고받는다. 모델 실행기가 이 컴퓨터에서 안 되면 건너뛴다 (model 픽스처).
- 입력 검사·오류 테스트는 모델 없이 돈다.
"""

import logging

import pytest
from fastapi.testclient import TestClient

from app.chat import nano
from app.main import app


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="module")
def model(client):
    try:
        nano.understand(client.app.state.network, "안녕하세요")
    except nano.NanoUnavailable as e:
        pytest.skip(f"나노 모델 실행기를 쓸 수 없음: {e}")
    yield
    nano._runner().close()


def say(client, message, before=None, lang="ko"):
    """메시지를 보낸다. before는 직전 응답 (앱처럼 그 context를 그대로 돌려보낸다)."""
    response = client.post("/chat", json={"message": message, "lang": lang, "context": before and before["context"]})
    assert response.status_code == 200, response.text
    return response.json()


def error(response):
    err = response.json()["error"]
    return response.status_code, err["code"], err.get("details")


# ----- 대화 (진짜 모델) -----

def test_route_then_follow_ups(client, model):
    r = say(client, "신도림에서 강남까지 어떻게 가?")
    assert set(r) == {"intent", "topic", "lang", "text", "route", "phrases", "options", "context"}
    assert (r["intent"], r["topic"], r["lang"]) == ("route", "result", "ko")
    assert r["text"] == "신도림 → 강남 · 51분 · 환승 2회 (최단 시간)"
    assert r["context"] == {"start": "101", "end": "208", "criteria": "time", "asked": None}

    r = say(client, "그럼 환승 없이는?", r)
    assert r["text"] == "신도림 → 강남 · 58분 · 환승 0회 (최소 환승)"
    r = say(client, "반대로는?", r)
    assert r["text"] == "강남 → 신도림 · 58분 · 환승 0회 (최소 환승)"
    r = say(client, "그럼 잠실까지는?", r)
    assert r["text"] == "강남 → 잠실 · 39분 · 환승 0회 (최소 환승)"

    r = say(client, "고마워", r)
    assert (r["intent"], r["route"]) == ("thanks", None)
    assert r["context"] == {"start": "208", "end": "214", "criteria": "transfers", "asked": None}  # 그대로


def test_asks_for_the_missing_station(client, model):
    r = say(client, "강남 가는 법")
    assert (r["topic"], r["text"]) == ("ask_start", "강남까지 가는 길을 찾을게요. 어디에서 출발하나요?")
    r = say(client, "신도림", r)
    assert r["text"] == "신도림 → 강남 · 51분 · 환승 2회 (최단 시간)"


def test_typo_and_several_candidates(client, model):
    r = say(client, "신도릠에서 교댸까지")
    assert r["text"].splitlines() == [
        "‘신도릠’ → 신도림 (이 역으로 이해했어요)",
        "‘교댸’ → 교대 (이 역으로 이해했어요)",
        "신도림 → 교대 · 42분 · 환승 1회 (최단 시간)",
    ]

    r = say(client, "종로에서 강남까지")
    assert r["topic"] == "choose_station"
    assert r["options"] == [{"id": "107", "name": "종로3가"}, {"id": "108", "name": "종로5가"}]
    r = say(client, "종로3가", r)
    assert r["text"] == "종로3가 → 강남 · 77분 · 환승 1회 (최단 시간)"


def test_conversation_in_english(client, model):
    r = say(client, "how do i get from Sindorim to Gangnam", lang="en")
    assert (r["lang"], r["text"]) == ("en", "Sindorim → Gangnam · 51 min · Transfers: 2 (fastest)")
    r = say(client, "fewer transfers please", r, lang="en")
    assert r["text"] == "Sindorim → Gangnam · 58 min · Transfers: 0 (fewest transfers)"
    r = say(client, "and the way back?", r, lang="en")
    assert r["route"]["start"] == {"id": "208", "name": "Gangnam"}


def test_user_language_wins_over_app_language(client, model):
    assert say(client, "신도림에서 강남까지", lang="en")["lang"] == "ko"
    assert say(client, "from Sindorim to Gangnam", lang="ko")["lang"] == "en"
    assert say(client, "Gangnam", lang="ja")["lang"] == "en"  # 역 이름뿐이라 앱 언어를 따르는데, ja 문구가 없어 영어


def test_fixed_replies(client, model):
    r = say(client, "교통카드는 어디서 사요?")
    assert (r["intent"], r["topic"]) == ("faq", "ticket")
    assert r["phrases"] == [{"id": "buy_ticket_help", "korean": "표 사는 것을 도와주세요.", "meaning": None}]

    r = say(client, "i feel dizzy and sick", lang="en")
    assert (r["intent"], r["topic"]) == ("emergency", "feel_sick")
    assert r["phrases"][0]["meaning"] == "I don't feel well. Please help me."

    assert say(client, "화장실 어디에 있어요")["topic"] == "station_facility"
    assert say(client, "asdfgh")["topic"] == "not_understood"


def test_japanese_gets_a_notice_not_a_wrong_answer(client, model):
    r = say(client, "すみません、切符はどこで買えますか", lang="ja")
    assert (r["intent"], r["topic"], r["lang"]) == ("out_of_scope", "unsupported_language", "en")


def test_route_is_the_same_as_post_routes(client, model):
    chat_route = say(client, "신도림에서 강남까지 환승 적게")["route"]
    body = {"start_station_id": "101", "end_station_id": "208", "criteria": "transfers", "lang": "ko"}
    direct = client.post("/routes", json=body).json()
    for times in ("departure_time", "arrival_time"):  # 요청한 시각이 달라서 뺀다
        chat_route.pop(times), direct.pop(times)
    assert chat_route == direct


# ----- 입력 검사와 오류 (모델 없이) -----

LANGS = ["ko", "en", "ja", "zh-Hans", "zh-Hant", "vi"]


@pytest.mark.parametrize("body, expected", [
    ({"lang": "ko"}, (422, "INVALID_REQUEST", {"field": "message"})),
    ({"message": "   ", "lang": "ko"}, (422, "INVALID_REQUEST", {"field": "message"})),
    ({"message": "가" * 301, "lang": "ko"}, (422, "INVALID_REQUEST", {"field": "message"})),
    ({"message": "안녕하세요"}, (422, "INVALID_REQUEST", {"field": "lang"})),
    ({"message": "안녕하세요", "lang": "fr"}, (400, "VALIDATION_ERROR", {"field": "lang", "supported": LANGS})),
    ({"message": "안녕하세요", "lang": "ko", "context": {"start": "999"}}, (400, "STATION_NOT_FOUND", {"station_id": "999"})),
    ({"message": "안녕하세요", "lang": "ko", "context": {"criteria": "fast"}}, (422, "INVALID_REQUEST", {"field": "context.criteria"})),
    ({"message": "안녕하세요", "lang": "ko", "context": {"asked": "middle"}}, (422, "INVALID_REQUEST", {"field": "context.asked"})),
])
def test_bad_requests(client, body, expected):
    assert error(client.post("/chat", json=body)) == expected


def test_model_unavailable_is_503(client, monkeypatch):
    def broken(network, message):
        raise nano.NanoUnavailable("실행기가 없습니다")

    monkeypatch.setattr(nano, "understand", broken)
    response = client.post("/chat", json={"message": "안녕하세요", "lang": "ko"})
    assert error(response) == (503, "CHAT_UNAVAILABLE", None)


def test_message_is_not_written_to_the_log(client, monkeypatch, caplog):
    caplog.set_level(logging.INFO)
    secret = "여권번호 M12345678"

    monkeypatch.setattr(nano, "understand", lambda network, message: nano.Answer(intent="greet", lang="ko"))
    assert client.post("/chat", json={"message": secret, "lang": "ko"}).status_code == 200

    def broken(network, message):
        raise nano.NanoUnavailable("실행기가 없습니다")

    monkeypatch.setattr(nano, "understand", broken)
    assert client.post("/chat", json={"message": secret, "lang": "ko"}).status_code == 503

    assert "POST /chat" in caplog.text  # 요청 기록은 남지만
    assert "M12345678" not in caplog.text and "여권번호" not in caplog.text  # 메시지 내용은 남지 않는다
