"""POST /meeting-station 테스트.

모임역 알고리즘(find_meeting_station)은 아직 없다 (표혜정 님 담당).
그래서 응답 모양은 가짜 알고리즘(fake_algorithm)으로 확인하고, 진짜가 없을 때는 501인지 확인한다.
"""

from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.api import meeting
from app.main import app

REQUEST = {"start_station_ids": ["101", "416", "805"], "criteria": "time", "lang": "en"}

# 명세 3장 예시 값. 101·416·805에서 모란(705)까지 최단 시간 경로로 실제 계산한 값이다.
# (모란은 time 기준 "이동 시간 합 최소"의 정답이기도 하다)
SPEC_EXAMPLE = {
    "criteria": "time",
    "station": {"id": "705", "name": "Moran"},
    "participants": [
        {"start": {"id": "101", "name": "Sindorim"}, "travel_sec": 4540, "transfer_count": 2},
        {"start": {"id": "416", "name": "Nowon"}, "travel_sec": 900, "transfer_count": 0},
        {"start": {"id": "805", "name": "Jangji"}, "travel_sec": 810, "transfer_count": 0},
    ],
    "nearby_facilities": [],
}
TO_MORAN = {"101": (4540, 2), "416": (900, 0), "805": (810, 0)}


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:  # with 문으로 열어야 노선도를 읽는 시작 동작이 실행된다
        yield c


@pytest.fixture
def algorithm(monkeypatch):
    """명세 6장 모양(MeetingResult)을 돌려주는 가짜 알고리즘. 받은 입력을 calls에 남긴다."""
    calls = []

    def fake_algorithm(network, starts, criteria):
        calls.append((starts, criteria))
        participants = [
            SimpleNamespace(start=s, travel_sec=TO_MORAN[s][0], transfer_count=TO_MORAN[s][1]) for s in starts
        ]
        return SimpleNamespace(station="705", participants=participants)

    monkeypatch.setattr(meeting, "find_meeting_station", fake_algorithm)
    return calls


def post(client, **changes):
    return client.post("/meeting-station", json={**REQUEST, **changes})


def error(response):
    err = response.json()["error"]
    return response.status_code, err["code"], err.get("details")


# ----- 정상 -----

def test_response_matches_spec_example(client, algorithm):
    response = post(client)
    assert response.status_code == 200
    assert response.json() == SPEC_EXAMPLE
    assert algorithm == [(["101", "416", "805"], "time")]


def test_keeps_request_order_and_lang(client, algorithm):
    body = post(client, start_station_ids=["805", "101"], lang="ko").json()
    assert [p["start"]["id"] for p in body["participants"]] == ["805", "101"]
    assert body["station"] == {"id": "705", "name": "모란"}


def test_same_start_station_twice_is_allowed(client, algorithm):
    assert post(client, start_station_ids=["101", "101"], criteria="fairness").status_code == 200
    assert algorithm == [(["101", "101"], "fairness")]


def test_not_implemented_until_algorithm_exists(client):
    assert error(post(client)) == (501, "NOT_IMPLEMENTED", None)


# ----- 입력 오류 (알고리즘을 부르기 전에 막는다) -----

@pytest.mark.parametrize("starts", [[], ["101"], ["101", "102", "103", "104", "105"]])
def test_participant_count_must_be_2_to_4(client, algorithm, starts):
    details = {"count": len(starts), "min": 2, "max": 4}
    assert error(post(client, start_station_ids=starts)) == (400, "INVALID_PARTICIPANT_COUNT", details)
    assert algorithm == []


def test_unknown_station(client, algorithm):
    response = post(client, start_station_ids=["101", "999"])
    assert error(response) == (400, "STATION_NOT_FOUND", {"station_id": "999"})
    assert algorithm == []


def test_unsupported_lang(client, algorithm):
    assert error(post(client, lang="ja")) == (400, "UNSUPPORTED_LANGUAGE", {"lang": "ja", "supported": ["ko", "en"]})


def test_invalid_criteria_and_numeric_ids(client, algorithm):
    assert error(post(client, criteria="cheap")) == (422, "INVALID_REQUEST", {"field": "criteria"})
    # 역 ID는 문자열이다 (명세 0장). 숫자로 보내면 422
    assert error(post(client, start_station_ids=[101, 416])) == (422, "INVALID_REQUEST", {"field": "start_station_ids"})
    assert algorithm == []
