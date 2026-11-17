"""POST /explain 테스트.

진짜 Gemini와 진짜 DB는 부르지 않는다. 그래서 API 키나 PostgreSQL이 없는 컴퓨터에서도 통과한다.
- Gemini: client._get_client를 가짜(FakeGemini)로 바꾼다
- 캐시: load_cached/save_cached를 메모리 사전으로 바꾼다 (가짜 설명이 실제 DB에 저장되지 않게)
"""

import logging
from types import SimpleNamespace

import httpx2
import pytest
from fastapi.testclient import TestClient

from app.ai import client as ai_client
from app.ai import explain as ai_explain
from app.main import app

ROUTE_REQUEST = {"start_station_id": "101", "end_station_id": "207", "criteria": "time", "lang": "en"}
FAKE_TEXT = "From Sindorim, take Line 1 to Apgujeong and transfer to Line 3."


class FakeGemini:
    """genai.Client에서 쓰는 부분(client.models.generate_content)만 흉내 낸다."""

    def __init__(self, error: Exception | None = None):
        self.models = self
        self.error = error
        self.calls = []

    def generate_content(self, model, contents, config):
        self.calls.append({"model": model, "contents": contents, "system": config.system_instruction})
        if self.error:
            raise self.error
        return SimpleNamespace(text=FAKE_TEXT)


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:  # with 문으로 열어야 노선도를 읽는 시작 동작이 실행된다
        yield c


@pytest.fixture(autouse=True)
def cache(monkeypatch):
    store = {}
    monkeypatch.setattr(ai_explain, "load_cached", lambda key, lang: store.get((key, lang)))
    monkeypatch.setattr(ai_explain, "save_cached", lambda key, lang, type_, text: store.setdefault((key, lang), text))
    return store


@pytest.fixture
def gemini(monkeypatch):
    fake = FakeGemini()
    monkeypatch.setattr(ai_client, "_get_client", lambda: fake)
    return fake


def explain(client, type_="route", request=ROUTE_REQUEST, lang="en"):
    return client.post("/explain", json={"type": type_, "request": request, "lang": lang})


def error(response):
    err = response.json()["error"]
    return response.status_code, err["code"], err.get("details")


# ----- 정상 + 캐시 -----

def test_first_call_not_cached_then_cached(client, gemini):
    first = explain(client)
    assert first.status_code == 200
    assert first.json() == {"explanation": FAKE_TEXT, "cached": False}

    second = explain(client)
    assert second.json() == {"explanation": FAKE_TEXT, "cached": True}
    assert len(gemini.calls) == 1  # 두 번째는 Gemini를 부르지 않는다


def test_departure_time_does_not_change_cache(client, gemini):
    explain(client, request={**ROUTE_REQUEST, "departure_time": "2026-11-04T18:30:00+09:00"})
    second = explain(client, request={**ROUTE_REQUEST, "departure_time": "2026-11-05T09:00:00+09:00"})
    assert second.json()["cached"] is True
    assert len(gemini.calls) == 1


def test_different_lang_is_separate_cache(client, gemini):
    explain(client, lang="en")
    assert explain(client, lang="ja").json()["cached"] is False
    assert len(gemini.calls) == 2


def test_prompt_uses_server_calculated_route(client, gemini):
    # 앱이 결과를 조작해 보내도(total_sec) 무시하고, 서버가 다시 계산한 값(42분, 압구정 환승)으로 설명한다
    explain(client, request={**ROUTE_REQUEST, "total_sec": 1}, lang="ja")
    call = gemini.calls[0]
    assert '"total_minutes": 42' in call["contents"]
    assert "Apgujeong" in call["contents"]
    assert "2026" not in call["contents"]  # 출발·도착 시각은 넣지 않는다
    assert "日本語" in call["system"] and "3문장" in call["system"]


# ----- 오류 -----

def test_timeout_returns_503(client, monkeypatch):
    fake = FakeGemini(error=httpx2.ReadTimeout("timed out"))
    monkeypatch.setattr(ai_client, "_get_client", lambda: fake)
    assert error(explain(client)) == (503, "AI_UNAVAILABLE", None)


def test_missing_api_key_returns_503_and_logs_cause(client, monkeypatch, caplog):
    caplog.set_level(logging.WARNING, logger="subfit")
    monkeypatch.setenv("GEMINI_API_KEY", "")
    monkeypatch.setattr(ai_client, "_client", None)  # 진짜 _get_client가 키를 다시 읽게 한다
    response = explain(client)
    assert error(response) == (503, "AI_UNAVAILABLE", None)
    assert "GEMINI_API_KEY" not in response.text  # 원인은 응답이 아니라
    assert "GEMINI_API_KEY" in caplog.text        # 서버 로그에만 남긴다


def test_unknown_station_returns_400(client, gemini):
    response = explain(client, request={**ROUTE_REQUEST, "end_station_id": "999"})
    assert error(response) == (400, "STATION_NOT_FOUND", {"station_id": "999"})
    assert gemini.calls == []


def test_invalid_lang_type_and_request(client, gemini):
    code, name, details = error(explain(client, lang="fr"))
    assert (code, name, details["field"]) == (400, "VALIDATION_ERROR", "lang")
    code, name, details = error(explain(client, type_="map"))
    assert (code, name, details["field"]) == (400, "VALIDATION_ERROR", "type")
    response = explain(client, request={**ROUTE_REQUEST, "criteria": "fastest"})
    assert error(response) == (400, "VALIDATION_ERROR", {"field": "request.criteria"})
    assert gemini.calls == []


# ----- 모임역 설명 (type=meeting) -----

MEETING_REQUEST = {"start_station_ids": ["101", "416", "805"], "criteria": "time", "lang": "en"}


def test_meeting_first_call_not_cached_then_cached(client, gemini):
    first = explain(client, type_="meeting", request=MEETING_REQUEST)
    assert first.status_code == 200
    assert first.json() == {"explanation": FAKE_TEXT, "cached": False}
    assert explain(client, type_="meeting", request=MEETING_REQUEST).json()["cached"] is True
    assert len(gemini.calls) == 1


def test_meeting_prompt_uses_server_calculated_result(client, gemini):
    # 앱이 결과를 조작해 보내도(station) 무시하고, 서버가 다시 계산한 모란(705)으로 설명한다.
    # 값은 docs/api-spec.md·ASSUMPTIONS.md의 확인용 정답: 4540초(76분)·900초(15분)·810초(14분), 합 6250초(104분)
    explain(client, type_="meeting", request={**MEETING_REQUEST, "station": "101"}, lang="ko")
    call = gemini.calls[0]
    assert '"meeting_station": "Moran"' in call["contents"]
    assert '"rule": "모든 참여자의 이동 시간 합이 가장 작은 역"' in call["contents"]
    assert '"total_travel_minutes": 104' in call["contents"]
    assert '"max_travel_minutes": 76' in call["contents"]
    assert '{"start": "Sindorim", "travel_minutes": 76, "transfer_count": 2}' in call["contents"]
    assert "cost" not in call["contents"]  # 비용·주변 시설은 넘기지 않는다
    assert "추천 이유" in call["system"] and "한국어" in call["system"]


@pytest.mark.parametrize("criteria, station", [("fairness", "Meokgol"), ("transfers", "Moran")])
def test_meeting_prompt_follows_criteria(client, gemini, criteria, station):
    explain(client, type_="meeting", request={**MEETING_REQUEST, "criteria": criteria})
    assert f'"meeting_station": "{station}"' in gemini.calls[0]["contents"]
    assert f'"criteria": "{criteria}"' in gemini.calls[0]["contents"]


def test_meeting_request_errors(client, gemini):
    # /meeting-station과 같은 검사를 한다
    response = explain(client, type_="meeting", request={**MEETING_REQUEST, "start_station_ids": ["101"]})
    assert error(response) == (400, "INVALID_PARTICIPANT_COUNT", {"count": 1, "min": 2, "max": 4})
    response = explain(client, type_="meeting", request={**MEETING_REQUEST, "start_station_ids": ["101", "999"]})
    assert error(response) == (400, "STATION_NOT_FOUND", {"station_id": "999"})
    response = explain(client, type_="meeting", request={**MEETING_REQUEST, "criteria": "cheap"})
    assert error(response) == (400, "VALIDATION_ERROR", {"field": "request.criteria"})
    assert gemini.calls == []
