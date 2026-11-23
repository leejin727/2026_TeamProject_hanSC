"""챗봇 답 만들기 테스트 (app/chat/service.py). 모델 대신 정해진 이해 결과(Answer)를 넣는다.

그래서 모델 실행기가 없는 컴퓨터에서도 돈다. 진짜 모델로 주고받는 대화는 test_chat_api.py에 있다.
"""

import struct

import pytest

from app.chat import nano, service
from app.chat.service import Context
from app.config import DATA_DIR
from app.errors import AppError
from app.routing.graph_builder import load_network


@pytest.fixture(scope="module")
def network():
    return load_network(DATA_DIR)


@pytest.fixture
def chat(network, monkeypatch):
    """chat(이해 결과, 직전 context, 앱 언어) → 답."""

    def run(answer, context=None, lang="ko"):
        monkeypatch.setattr(nano, "understand", lambda network, message: answer)
        return service.reply(network, "(메시지)", lang, context or Context())

    return run


def route(start=None, end=None, station=None, lang="ko", **flags):
    """길찾기로 이해한 결과. station은 출발인지 도착인지 말하지 않은 역이다."""

    def name(text):
        return nano.StationName(text) if text else None

    return nano.Answer(intent="route", lang=lang, start=name(start), end=name(end), station=name(station), **flags)


def ctx(**values):
    return Context(**values).model_dump()


def again(response):
    """앱이 하는 것처럼, 받은 context를 다음 요청에 그대로 돌려보낸다."""
    return Context(**response["context"])


# ----- 길찾기 -----

def test_route_with_both_stations(chat):
    r = chat(route("신도림", "강남"))
    assert (r["intent"], r["topic"], r["lang"]) == ("route", "result", "ko")
    assert r["text"] == "신도림 → 강남 · 51분 · 환승 2회 (최단 시간)"
    assert r["route"]["start"] == {"id": "101", "name": "신도림"}
    assert (r["route"]["end"]["id"], r["route"]["total_sec"], r["route"]["criteria"]) == ("208", 3060, "time")
    assert r["context"] == ctx(start="101", end="208", criteria="time")
    assert r["phrases"] == [] and r["options"] == []


def test_follow_up_changes_only_what_was_said(chat):
    r = chat(route(criteria="transfers", follow_up=True), Context(start="101", end="208", criteria="time"))  # "그럼 환승 없이는?"
    assert r["text"] == "신도림 → 강남 · 58분 · 환승 0회 (최소 환승)"
    r = chat(route(follow_up=True, reverse=True), again(r))  # "반대로는?"
    assert r["text"] == "강남 → 신도림 · 58분 · 환승 0회 (최소 환승)"  # 기준은 그대로
    r = chat(route(end="잠실", follow_up=True), again(r))  # "그럼 잠실까지는?"
    assert r["text"] == "강남 → 잠실 · 39분 · 환승 0회 (최소 환승)"
    assert r["context"] == ctx(start="208", end="214", criteria="transfers")


def test_new_question_does_not_reuse_old_stations(chat):
    r = chat(route(end="잠실"), Context(start="101", end="208", criteria="transfers"))  # "잠실 가는 법": 이어 묻는 말이 아니다
    assert (r["topic"], r["route"]) == ("ask_start", None)
    assert r["text"] == "잠실까지 가는 길을 찾을게요. 어디에서 출발하나요?"
    assert r["context"] == ctx(end="214", criteria="time", asked="start")


def test_missing_station_is_asked_then_filled(chat):
    r = chat(route(end="강남"))
    assert r["topic"] == "ask_start"
    r = chat(route(station="신도림", lang=None), again(r))  # "신도림": 방금 물어본 출발역으로 본다
    assert r["text"] == "신도림 → 강남 · 51분 · 환승 2회 (최단 시간)"

    r = chat(route(start="신도림"))
    assert (r["topic"], r["text"]) == ("ask_end", "신도림에서 출발하는군요. 어디로 가시나요?")
    assert r["context"] == ctx(start="101", criteria="time", asked="end")
    r = chat(route(end="강남"), again(r))  # "강남까지요"
    assert r["context"] == ctx(start="101", end="208", criteria="time")


def test_single_station_without_role_is_the_destination(chat):
    r = chat(route(station="강남", lang=None))
    assert (r["topic"], r["context"]) == ("ask_start", ctx(end="208", criteria="time", asked="start"))


def test_no_station_asks_for_both_and_keeps_criteria(chat):
    r = chat(route(criteria="transfers"))  # "환승 적게 가는 길 알려줘"
    assert (r["topic"], r["context"]) == ("ask_both", ctx(criteria="transfers", asked="end"))
    assert chat(route("신도림", "강남"), again(r))["route"]["criteria"] == "transfers"

    assert chat(route(follow_up=True, reverse=True))["topic"] == "ask_both"  # 앞 대화 없이 "반대로는?"


def test_typo_or_alias_with_one_candidate_is_used_and_told(chat):
    r = chat(route("신도릠", "고터"))
    assert r["text"].splitlines() == [
        "‘신도릠’ → 신도림 (이 역으로 이해했어요)",
        "‘고터’ → 고속터미널 (이 역으로 이해했어요)",
        "신도림 → 고속터미널 · 24분 · 환승 1회 (최단 시간)",
    ]
    assert r["context"] == ctx(start="101", end="303", criteria="time")


def test_several_candidates_are_offered(chat):
    r = chat(route("종로", "강남"))
    assert (r["topic"], r["text"]) == ("choose_station", "‘종로’ — 어느 역을 말씀하시나요?")
    assert r["options"] == [{"id": "107", "name": "종로3가"}, {"id": "108", "name": "종로5가"}]
    assert r["context"] == ctx(end="208", criteria="time", asked="start")  # 다른 쪽 역은 기억해 둔다
    r = chat(route(station="종로3가", lang=None), again(r))
    assert (r["route"]["start"]["id"], r["route"]["end"]["id"]) == ("107", "208")


def test_same_station(chat):
    r = chat(route("신도림", "신도림"))
    assert (r["topic"], r["text"]) == ("same_station", "출발역과 도착역이 같아요 (신도림). 어디로 가시나요?")
    assert r["context"] == ctx(start="101", criteria="time", asked="end")


def test_no_route(chat, monkeypatch):
    def no_route(network, body):
        raise AppError(404, "NO_ROUTE", "경로 없음")

    monkeypatch.setattr(service, "compute_route", no_route)  # 지금 데이터는 모든 역이 이어져 있어서 가짜로 만든다
    r = chat(route("신도림", "강남"))
    assert (r["topic"], r["route"], r["text"]) == ("no_route", None, "두 역을 잇는 경로를 찾지 못했어요.")


# ----- 고정 문구 -----

ALL_PHRASES = ["which_side", "transfer_where", "buy_ticket_help", "lost_item", "feel_sick", "no_korean"]


@pytest.mark.parametrize("answer, topic, cards", [
    (nano.Answer(intent="faq", lang="ko", faq_id="ticket"), "ticket", ["buy_ticket_help"]),
    (nano.Answer(intent="faq", lang="ko", faq_id="gate"), "gate", []),
    (nano.Answer(intent="phrase", lang="ko"), "list", ALL_PHRASES),
    (nano.Answer(intent="phrase", lang="ko", phrase_id="which_side"), "which_side", ["which_side"]),
    (nano.Answer(intent="help", lang="ko"), "lost", []),
    (nano.Answer(intent="emergency", lang="ko", phrase_id="feel_sick"), "feel_sick", ["feel_sick"]),
    (nano.Answer(intent="emergency", lang="ko", phrase_id="lost_item"), "lost_item", ["lost_item"]),
    (nano.Answer(intent="out_of_scope", lang="ko", kind="not_understood"), "not_understood", []),
    (nano.Answer(intent="greet", lang="ko"), "hello", []),
    (nano.Answer(intent="thanks", lang="ko"), "welcome", []),
])
def test_fixed_replies(chat, answer, topic, cards):
    before = Context(end="208", criteria="transfers", asked="start")
    r = chat(answer, before)
    assert (r["intent"], r["topic"], r["route"], r["options"]) == (answer.intent, topic, None, [])
    assert r["text"]
    assert [card["id"] for card in r["phrases"]] == cards
    assert r["context"] == before.model_dump()  # 길찾기 대화는 끊기지 않는다


def test_last_train_and_emergency_texts(chat):
    # 첫차·막차는 아직 정하지 않은 범위다 (AGENTS.md). 시간을 지어내지 않고 없다고 답한다
    assert "첫차·막차 시간 정보가 없어요" in chat(nano.Answer(intent="faq", lang="ko", faq_id="last_train"))["text"]
    assert "119" in chat(nano.Answer(intent="emergency", lang="ko", phrase_id="feel_sick"))["text"]
    assert "112" in chat(nano.Answer(intent="emergency", lang="en", phrase_id="lost_item"))["text"]


def model_labels() -> list[str]:
    """모델 파일에 들어 있는 의도 라벨 (subfit_nano.cpp의 load()와 같은 순서로 읽는다)."""
    data = nano.MODEL_FILE.read_bytes()
    assert data[:4] == b"SFN1"
    vocab_size = struct.unpack_from("<I", data, 4 + 5 * 4)[0]
    pos = 4 + 7 * 4

    def text():
        nonlocal pos
        length = data[pos]
        pos += 1 + length
        return data[pos - length:pos].decode("utf-8")

    for _ in range(vocab_size):
        text()
    assert text() == "intent"
    count = struct.unpack_from("<I", data, pos)[0]
    pos += 4
    return [text() for _ in range(count)]


def test_every_label_the_model_can_pick_has_a_reply(chat):
    labels = model_labels()
    assert len(labels) == 26
    for label in labels:
        picked = {"intent": (label, 1.0), "criteria": ("none", 1.0), "flow": ("new", 1.0)}
        for lang in service.REPLY_LANGS:
            r = chat(nano.to_answer(picked, [], "", lang))  # 문구가 없으면 여기서 KeyError
            assert r["text"] and r["lang"] == lang, label


def test_every_text_has_korean_and_english():
    for group in ("route", "faq", "phrase", "help", "emergency", "out_of_scope", "greet", "thanks"):
        for topic, entry in service.TEXTS[group].items():
            assert entry["ko"].strip() and entry["en"].strip(), f"{group}/{topic}"
            assert entry.get("phrase", "lost_item") in service.TEXTS["phrases"], f"{group}/{topic}"
    assert list(service.TEXTS["phrases"]) == ALL_PHRASES
    for phrase in service.TEXTS["phrases"].values():
        assert phrase["korean"].strip() and phrase["en"].strip()


# ----- 언어 -----

def test_reply_language(chat):
    r = chat(route("Sindorim", "Gangnam", lang="en"))
    assert (r["lang"], r["text"]) == ("en", "Sindorim → Gangnam · 51 min · Transfers: 2 (fastest)")
    assert r["route"]["start"] == {"id": "101", "name": "Sindorim"}

    # 사용자가 쓴 언어를 모르면(역 이름만 보냄) 앱 언어로, 앱 언어가 ko·en이 아니면 영어로 답한다
    assert chat(route(station="강남", lang=None), lang="ko")["lang"] == "ko"
    r = chat(route(station="강남", lang=None), lang="ja")
    assert (r["lang"], r["text"]) == ("en", "Where are you starting from? (Destination: Gangnam)")


def test_phrase_card_has_meaning_only_in_english(chat):
    korean = "한국어를 잘 못해요. 영어로 말씀해 주실 수 있나요?"
    card = chat(nano.Answer(intent="phrase", lang="en", phrase_id="no_korean"))["phrases"][0]
    assert card == {"id": "no_korean", "korean": korean, "meaning": "I don't speak Korean well. Could you speak English?"}
    card = chat(nano.Answer(intent="phrase", lang="ko", phrase_id="no_korean"))["phrases"][0]
    assert card == {"id": "no_korean", "korean": korean, "meaning": None}


@pytest.mark.parametrize("written_in", ["ja", "zh-Hans", "zh-Hant", "vi", "other"])
def test_other_languages_get_a_fixed_notice(chat, written_in):
    before = Context(end="208", criteria="time", asked="start")
    r = chat(route("신도림", "강남", lang=written_in), before, lang="ja")  # 모델이 길찾기라고 해도 믿지 않는다
    assert (r["intent"], r["topic"], r["lang"], r["route"]) == ("out_of_scope", "unsupported_language", "en", None)
    assert r["context"] == before.model_dump()
    assert chat(route(lang=written_in), lang="ko")["text"] == "아직은 한국어와 영어만 이해할 수 있어요. 한국어나 영어로 물어봐 주세요."


# ----- 모델을 쓸 수 없을 때 -----

def test_model_unavailable_is_503(network, monkeypatch):
    def broken(network, message):
        raise nano.NanoUnavailable("실행기가 없습니다")

    monkeypatch.setattr(nano, "understand", broken)
    with pytest.raises(AppError) as error:
        service.reply(network, "안녕하세요", "ko", Context())
    assert (error.value.status_code, error.value.code) == (503, "CHAT_UNAVAILABLE")
