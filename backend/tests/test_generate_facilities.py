"""scripts/generate_facilities.py 테스트 (주변 시설 미리 만들기).

진짜 Gemini는 부르지 않는다. 한국어를 만드는 generate_korean()과 번역하는 translate()를 가짜로 바꾸고,
기다리는 시간(time.sleep)은 0으로 만든다. 저장 파일은 pytest 임시 폴더에 쓴다.
"""

import json
import sys
from pathlib import Path

import pytest

from app.ai.client import AIUnavailableError
from app.config import MissingSettingError

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import generate_facilities as gen  # noqa: E402

OLD = [{"category": "cafe", "name": "예전 카페", "detail": "1번 출구 · 도보 1분"}]
OTHERS = ["en", "ja", "zh-Hans", "zh-Hant", "vi"]


@pytest.fixture
def output(monkeypatch, tmp_path):
    path = tmp_path / "ai_facilities.json"
    monkeypatch.setattr(gen, "OUTPUT", path)
    monkeypatch.setattr(gen.time, "sleep", lambda sec: None)
    return path


def fake(monkeypatch, fail=lambda kind, name, n: False, error=AIUnavailableError("503 UNAVAILABLE")):
    """가짜 generate_korean·translate. fail(언어, 역 이름, 그 역·언어의 몇 번째 시도)가 True면 error를 낸다.

    한국어는 "<한국어 역 이름> 카페", 번역은 "<번역한 한국어 가게 이름> → <언어>"라서,
    번역이 어느 한국어 목록에서 나왔는지 결과로 확인할 수 있다.
    """
    calls = []

    def generate_korean(name_ko):
        calls.append(("ko", name_ko))
        if fail("ko", name_ko, calls.count(("ko", name_ko))):
            raise error
        return [{**OLD[0], "name": f"{name_ko} 카페"}]

    def translate(korean, name_en, lang):
        calls.append((lang, name_en))
        if fail(lang, name_en, calls.count((lang, name_en))):
            raise error
        return [{**k, "name": f"{k['name']} → {lang}"} for k in korean]

    monkeypatch.setattr(gen, "generate_korean", generate_korean)
    monkeypatch.setattr(gen, "translate", translate)
    return calls


def read(output):
    return json.loads(output.read_text(encoding="utf-8"))


def test_makes_only_missing_korean_first_and_translates_it(monkeypatch, output):
    output.write_text(json.dumps({"101": {"ko": OLD}}, ensure_ascii=False), encoding="utf-8")  # 이미 있는 것
    calls = fake(monkeypatch)

    assert gen.main(["--lang", "en", "ko"]) == 0
    assert len(calls) == 1 + 110 * 2  # 101은 영어만, 나머지 110개 역은 한국어 + 영어
    assert calls.index(("ko", "구로")) < calls.index(("en", "Guro"))  # 역마다 한국어가 먼저
    data = read(output)
    assert data["101"]["ko"] == OLD  # 원래 있던 한국어는 그대로 두고
    assert data["101"]["en"][0]["name"] == "예전 카페 → en"  # 그 한국어를 번역한다
    assert data["102"]["en"][0]["name"] == "구로 카페 → en"
    assert list(data) == sorted(data) and len(data) == 111  # 역 번호 순서
    assert list(data["102"]) == ["ko", "en"]  # 언어는 정해진 순서 (요청 순서와 상관없이)

    assert gen.main(["--lang", "ko", "en"]) == 0  # 다시 실행하면 만들 것이 없다
    assert len(calls) == 1 + 110 * 2


def test_rebuild_only_the_given_stations(monkeypatch, output):
    before = {"101": {"ko": OLD}, "701": {"ko": OLD, "en": OLD, "ja": OLD}}
    output.write_text(json.dumps(before, ensure_ascii=False), encoding="utf-8")
    calls = fake(monkeypatch)

    assert gen.main(["--stations", "701", "705", "--rebuild"]) == 0
    assert calls == [("ko", "먹골"), *[(lang, "Meokgol") for lang in OTHERS],
                     ("ko", "모란"), *[(lang, "Moran") for lang in OTHERS]]
    data = read(output)
    assert data["101"] == {"ko": OLD}  # 고르지 않은 역은 그대로
    assert data["701"]["ko"][0]["name"] == "먹골 카페"  # 파일에 있어도 새로 만들고
    assert {lang: items[0]["name"] for lang, items in data["701"].items() if lang != "ko"} == {
        lang: f"먹골 카페 → {lang}" for lang in OTHERS}  # 모든 언어가 같은 한국어 목록에서 나온다
    assert list(data["705"]) == ["ko", *OTHERS]


def test_unknown_station_is_refused(monkeypatch, output):
    calls = fake(monkeypatch)
    assert gen.main(["--stations", "701", "999"]) == 2
    assert calls == [] and not output.exists()


def test_retries_then_skips_and_continues(monkeypatch, output):
    # 신도림(101) 한국어는 계속 실패, 구로(102) 한국어는 두 번 실패 후 세 번째에 성공
    def fail(lang, name, n):
        return lang == "ko" and (name == "신도림" or (name == "구로" and n <= 2))

    calls = fake(monkeypatch, fail)
    assert gen.main(["--lang", "ko", "en", "--stations", "101", "102"]) == 1  # 남은 것이 있으면 1
    assert calls.count(("ko", "신도림")) == 1 + len(gen.RETRY_WAITS)  # 처음 + 다시 시도
    assert ("en", "Sindorim") not in calls  # 번역할 한국어가 없으니 번역은 부르지 않는다
    assert calls.count(("ko", "구로")) == 3
    data = read(output)
    assert "101" not in data and data["102"]["en"][0]["name"] == "구로 카페 → en"


def test_stops_after_failing_many_in_a_row(monkeypatch, output):
    calls = fake(monkeypatch, fail=lambda *_: True)  # 사용량 한도에 걸린 상황
    assert gen.main(["--lang", "ko"]) == 1
    assert len(calls) == gen.MAX_FAILS_IN_A_ROW * (1 + len(gen.RETRY_WAITS))  # 111개를 다 돌지 않는다
    assert not output.exists()


def test_bad_translations_in_a_row_do_not_stop(monkeypatch, output):
    # 번역 답이 틀린 것(항목 수가 다름, 한글 섞임 등)은 그 역만의 문제라, 연속으로 나와도 끝까지 간다
    bad = {"Sindorim", "Guro", "Yeongdeungpo", "Seoul Station"}
    calls = fake(monkeypatch, fail=lambda lang, name, n: lang == "ja" and name in bad,
                 error=ValueError("번역 답의 항목 수(4)가 한국어(5)와 다릅니다"))
    assert gen.main(["--lang", "ja"]) == 1
    data = read(output)
    assert len(data) == 111 and all("ko" in v for v in data.values())  # 번역 원본인 한국어는 모두 저장
    assert sum("ja" in v for v in data.values()) == 111 - len(bad)  # 틀린 4개만 빠진다
    assert len(calls) == 111 + (111 - len(bad)) + len(bad) * (1 + len(gen.RETRY_WAITS))


def test_missing_key_stops_at_once(monkeypatch, output):
    def generate_korean(name_ko):
        raise MissingSettingError("GEMINI_FACILITY_API_KEY가 .env에 없습니다")

    monkeypatch.setattr(gen, "generate_korean", generate_korean)
    assert gen.main(["--lang", "ko"]) == 1
    assert not output.exists()
