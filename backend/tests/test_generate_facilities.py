"""scripts/generate_facilities.py 테스트 (주변 시설 미리 만들기).

진짜 Gemini는 부르지 않는다. 시설 하나를 만드는 generate()를 가짜로 바꾸고,
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

ITEMS = [{"category": "cafe", "name": "Cafe", "detail": "Exit 1 · 1 min walk"}]


@pytest.fixture
def output(monkeypatch, tmp_path):
    path = tmp_path / "ai_facilities.json"
    monkeypatch.setattr(gen, "OUTPUT", path)
    monkeypatch.setattr(gen.time, "sleep", lambda sec: None)
    return path


def fake_generate(monkeypatch, fail=lambda name_en, lang, n: False, error=AIUnavailableError("503 UNAVAILABLE")):
    """fail(영어 역 이름, 언어, 그 역·언어의 몇 번째 시도인지)가 True면 error를 낸다."""
    calls = []

    def generate(name_ko, name_en, lang):
        calls.append((name_en, lang))
        if fail(name_en, lang, calls.count((name_en, lang))):
            raise error
        return [{**ITEMS[0], "name": f"{name_en} {lang}"}]

    monkeypatch.setattr(gen, "generate", generate)
    return calls


def test_makes_only_missing_and_saves_in_order(monkeypatch, output):
    output.write_text(json.dumps({"101": {"ko": ITEMS}}), encoding="utf-8")  # 이미 있는 것
    calls = fake_generate(monkeypatch)

    assert gen.main(["--lang", "en", "ko"]) == 0
    assert len(calls) == 111 * 2 - 1  # 101/ko는 건너뛴다
    data = json.loads(output.read_text(encoding="utf-8"))
    assert data["101"]["ko"] == ITEMS  # 원래 있던 것은 그대로
    assert data["101"]["en"] == [{**ITEMS[0], "name": "Sindorim en"}]
    assert list(data) == sorted(data) and len(data) == 111  # 역 번호 순서
    assert list(data["102"]) == ["ko", "en"]  # 언어는 정해진 순서 (요청 순서와 상관없이)

    assert gen.main(["--lang", "ko", "en"]) == 0  # 다시 실행하면 만들 것이 없다
    assert len(calls) == 111 * 2 - 1


def test_retries_then_skips_and_continues(monkeypatch, output):
    # 신도림(101)은 계속 실패, 구로(102)는 두 번 실패 후 세 번째에 성공
    def fail(name_en, lang, n):
        return name_en == "Sindorim" or (name_en == "Guro" and n <= 2)

    calls = fake_generate(monkeypatch, fail)
    assert gen.main(["--lang", "ko"]) == 1  # 남은 것이 있으면 1
    assert calls.count(("Sindorim", "ko")) == 1 + len(gen.RETRY_WAITS)  # 처음 + 다시 시도
    assert calls.count(("Guro", "ko")) == 3
    data = json.loads(output.read_text(encoding="utf-8"))
    assert "101" not in data and len(data) == 110  # 실패한 역만 빠지고 나머지는 저장


def test_stops_after_failing_many_in_a_row(monkeypatch, output):
    calls = fake_generate(monkeypatch, fail=lambda *_: True)  # 사용량 한도에 걸린 상황
    assert gen.main(["--lang", "ko"]) == 1
    assert len(calls) == gen.MAX_FAILS_IN_A_ROW * (1 + len(gen.RETRY_WAITS))  # 111개를 다 돌지 않는다
    assert not output.exists()


def test_bad_answers_in_a_row_do_not_stop(monkeypatch, output):
    # 답이 틀린 것(한글 섞임 등)은 그 역만의 문제라, 연속으로 나와도 멈추지 않고 끝까지 간다
    bad = {"Sindorim", "Guro", "Yeongdeungpo", "Namyeong"}
    calls = fake_generate(monkeypatch, fail=lambda name_en, *_: name_en in bad,
                          error=ValueError("ja로 요청했는데 한글이 섞인 답이 왔습니다"))
    assert gen.main(["--lang", "ja"]) == 1
    data = json.loads(output.read_text(encoding="utf-8"))
    assert len(data) == 111 - len(bad)  # 틀린 4개만 빠지고 나머지는 저장
    assert len(calls) == len(bad) * (1 + len(gen.RETRY_WAITS)) + (111 - len(bad))


def test_missing_key_stops_at_once(monkeypatch, output):
    def generate(*args):
        raise MissingSettingError("GEMINI_FACILITY_API_KEY가 .env에 없습니다")

    monkeypatch.setattr(gen, "generate", generate)
    assert gen.main(["--lang", "ko"]) == 1
    assert not output.exists()
