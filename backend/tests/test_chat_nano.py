"""챗봇 1단계 테스트: 역 이름 찾기(app/chat/stations.py)와 나노 모델 연동(app/chat/nano).

- 역 찾기 테스트는 모델 없이 돈다.
- 진짜 모델 실행기를 돌리는 테스트(model 픽스처)는 이 컴퓨터에서 실행기가 안 되면 건너뛴다.
  결과에 "skipped"가 보이면 실행기를 확인한다 (docs/chatbot.md).
"""

import os

import pytest

from app.chat import nano, settings, stations
from app.chat.nano import rules
from app.config import DATA_DIR
from app.routing.graph_builder import load_network


@pytest.fixture(scope="module")
def network():
    return load_network(DATA_DIR)


@pytest.fixture(scope="module")
def model(network):
    """진짜 모델 실행기를 띄운다."""
    try:
        nano.understand(network, "안녕하세요")
    except nano.NanoUnavailable as e:
        pytest.skip(f"나노 모델 실행기를 쓸 수 없음: {e}")
    yield
    nano._runner().close()


# ----- 역 이름 찾기 (stations.py) -----

@pytest.mark.parametrize("text, expected", [
    ("Seoul Station", "seoul"),
    ("서울역", "서울"),
    ("Jongno 3-ga", "jongno3ga"),
    ("종로 3가", "종로3가"),
    (" Konkuk Univ. ", "konkukuniv"),
    ("Gangnam stn.", "gangnam"),
    ("역", "역"),  # "역" 한 글자뿐이면 떼지 않는다
])
def test_normalize(text, expected):
    assert stations.normalize(text) == expected


@pytest.mark.parametrize("name, station_id", [
    ("신도림", "101"), ("신도림역", "101"), ("Sindorim", "101"), ("sindorim station", "101"),
    ("서울역", "104"), ("Seoul Station", "104"),
    ("Jongno 3(sam)-ga", "107"), ("Jongno 3-ga", "107"), ("jongno sam-ga", "107"),  # 영어 이름은 적는 법이 여럿
    ("Konkuk Univ.", "202"), ("Konkuk University", "202"),
    ("Dongdaemun History and Culture Park", "403"),
    ("동대문", "115"), ("Yeongdeungpo", "103"),  # 다른 역 이름의 앞부분이어도 정확히 같은 역이 먼저
])
def test_data_name_gives_the_station(network, name, station_id):
    assert stations.find(network, name) == stations.Found(station_id=station_id)


@pytest.mark.parametrize("name, candidates", [
    ("고터", ["303"]), ("건대", ["202"]), ("종로오가", ["108"]), ("서울교대", ["207"]),  # 줄임말
    ("gyodae", ["207"]),             # 한국어 이름을 소리 나는 대로 적은 영어
    ("konkuk", ["202"]),             # 영어 이름 속 낱말 하나
    ("신도릠", ["101"]), ("교댸", ["207"]), ("여신내", ["614"]), ("sindolim", ["101"]),  # 오타
    ("종로", ["107", "108"]), ("jongno", ["107", "108"]),  # 이름의 앞부분: 두 역이 모두 후보
])
def test_other_names_are_candidates_to_confirm(network, name, candidates):
    assert stations.find(network, name) == stations.Found(candidates=candidates)


@pytest.mark.parametrize("name", [
    "성수기", "옥수수", "동대문구",   # 역 이름에 글자가 더 붙은 다른 낱말
    "몰라",                           # 모란과 ratio는 0.8이지만 자모 2개가 다르다
    "잠시", "식당", "만원", "문장",   # 역 이름과 한 글자 차이인 흔한 말 (ko_confusables.txt)
    "서울대입구",                     # 데이터에 없는 역
    "xyz", "",
])
def test_not_a_station(network, name):
    assert stations.find(network, name) == stations.Found()


def test_best_gives_similarity_to_rules(network):
    assert stations.best(network, "신도림", 0.8) == (1.0, ["101"])
    assert stations.best(network, "신도릠", 0.8) == (0.875, ["101"])
    assert stations.best(network, "교댸", 0.75) == (0.75, ["207"])
    assert stations.best(network, "교댸", 0.8) == (0.0, [])  # 기준에 못 미치면 0


# ----- 문장에서 역 찾기 (rules.py + stations.py) -----

def mentions(network, text):
    return [(m.written, m.station_id or m.candidates, m.role) for m in rules.find_mentions(network, text)]


@pytest.mark.parametrize("text, expected", [
    ("신도림에서교대까지", [("신도림", "101", "start"), ("교대", "207", "end")]),
    ("신도릠에서 교대까지 어떻게 가?", [("신도릠", ["101"], "start"), ("교대", "207", "end")]),
    ("궁금한데상뵹까지 어떻게 가", [("상뵹", ["704"], "end")]),
    ("고터 가는 법", [("고터", ["303"], "end")]),
    ("지금 신당역인데 합정 가려면", [("신당역", "618", "start"), ("합정", "605", "end")]),
    ("Sindorim to Gangnam fastest?", [("Sindorim", "101", "start"), ("Gangnam", "208", "end")]),
    ("how do i get from Gyodae to Apgujeong", [("Gyodae", ["207"], "start"), ("Apgujeong", "123", "end")]),
    ("i'm at Seoul Station, going to Konkuk Univ.", [("Seoul Station", "104", "start"), ("Konkuk Univ.", "202", "end")]),
])
def test_stations_in_a_sentence(network, text, expected):
    assert mentions(network, text) == expected


@pytest.mark.parametrize("text", [
    "성수기에 가면 좋아?", "옥수수 먹고 싶다", "삼성페이 돼요?", "서울 지하철 요금 얼마야", "서울역사박물관 가는 법",
    "몰라요", "잠시만요", "맛있는 식당에 가고 싶어", "미안", "거꾸로 가는 건?",
    "um how do i go there", "the changes are single", "ticket office where", "world cup tickets",
])
def test_ordinary_words_are_not_stations(network, text):
    assert mentions(network, text) == []


# ----- 모델 연동 (nano.understand) -----

def test_runner_file_for_this_computer_is_ready():
    exe = nano.binary_path()
    assert exe.exists(), f"이 컴퓨터용 실행기가 없음: {exe.name}"
    assert os.name == "nt" or os.access(exe, os.X_OK), "실행 권한이 없음 (chmod +x)"
    assert nano.MODEL_FILE.exists()


@pytest.mark.parametrize("text, start, end, criteria, lang", [
    ("신도림에서 압구정까지 어떻게 가?", "신도림", "압구정", None, "ko"),
    ("교대에서 잠실까지 제일 빨리 가는 길", "교대", "잠실", "time", "ko"),
    ("Gangnam to Mia with no transfers", "Gangnam", "Mia", "transfers", "en"),
])
def test_understand_route(network, model, text, start, end, criteria, lang):
    answer = nano.understand(network, text)
    assert (answer.intent, answer.start.written, answer.end.written) == ("route", start, end)
    assert (answer.criteria, answer.lang, answer.follow_up) == (criteria, lang, False)


def test_understand_follow_up(network, model):
    answer = nano.understand(network, "그럼 반대로는?")
    assert (answer.intent, answer.follow_up, answer.reverse) == ("route", True, True)
    assert answer.start is None and answer.end is None  # 역은 앞 대화에서 가져와야 한다


@pytest.mark.parametrize("text, intent, detail", [
    ("교통카드는 어디서 사요?", "faq", "ticket"),
    ("i feel dizzy and sick", "emergency", "feel_sick"),
    ("화장실 어디에 있어요", "out_of_scope", "station_facility"),
    ("오늘 날씨 어때", "out_of_scope", "unrelated"),
    ("thanks a lot!", "thanks", None),
])
def test_understand_other_intents(network, model, text, intent, detail):
    answer = nano.understand(network, text)
    assert (answer.intent, answer.faq_id or answer.phrase_id or answer.kind) == (intent, detail)


class FakeRunner:
    """모델 실행기 대신 정해진 답을 준다."""

    def __init__(self, confidence):
        self.confidence = confidence

    def ask(self, model_text):
        return {"intent": ("route", self.confidence), "criteria": ("none", 1.0), "flow": ("new", 1.0)}


def test_low_confidence_is_not_understood(network, monkeypatch):
    monkeypatch.setattr(nano, "_runner", lambda: FakeRunner(settings.NANO_MIN_CONFIDENCE - 0.01))
    answer = nano.understand(network, "신도림에서 압구정까지")
    assert (answer.intent, answer.kind) == ("out_of_scope", "not_understood")

    monkeypatch.setattr(nano, "_runner", lambda: FakeRunner(settings.NANO_MIN_CONFIDENCE))
    assert nano.understand(network, "신도림에서 압구정까지").intent == "route"


def test_missing_runner_raises_unavailable(network, monkeypatch, tmp_path):
    monkeypatch.setenv("SUBFIT_NANO_BIN", str(tmp_path / "no-such-file"))
    monkeypatch.setattr(nano, "_shared", None)  # 이미 띄워 둔 실행기를 쓰지 않게
    with pytest.raises(nano.NanoUnavailable):
        nano.understand(network, "안녕하세요")
