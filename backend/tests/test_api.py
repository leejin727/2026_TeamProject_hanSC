"""GET /stations, POST /routes 테스트 (docs/api-spec.md 1·2·5장)."""

import logging
from datetime import datetime

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.routing.dijkstra import NoRouteError

DEPARTURE = "2026-11-04T18:30:00+09:00"


@pytest.fixture(scope="module")
def client():
    # with 문으로 열어야 서버 시작 동작(lifespan: 노선도 읽기)이 실행된다
    with TestClient(app) as c:
        yield c


def route(client, start="101", end="207", criteria="time", lang="en", **extra):
    body = {"start_station_id": start, "end_station_id": end, "criteria": criteria, "lang": lang, **extra}
    return client.post("/routes", json=body)


def error(response):
    """오류 응답을 (HTTP 상태, code, details)로 줄인다."""
    err = response.json()["error"]
    return response.status_code, err["code"], err.get("details")


def st(station_id, name):
    return {"id": station_id, "name": name}


SINDORIM = st("101", "Sindorim")
APGUJEONG = st("123", "Apgujeong")
SNUE = st("207", "Seoul Nat'l Univ. of Education")

# docs/api-spec.md 2장 첫 예시. direction은 표기 방식이 정해질 때까지 서버가 항상 null을 준다.
SPEC_TIME_EXAMPLE = {
    "criteria": "time",
    "start": SINDORIM,
    "end": SNUE,
    "departure_time": "2026-11-04T18:30:00+09:00",
    "arrival_time": "2026-11-04T19:11:50+09:00",
    "total_sec": 2510,
    "transfer_count": 1,
    "cost_won": 4190,
    "segments": [
        {
            "line": 1, "board": SINDORIM, "alight": APGUJEONG, "direction": None,
            "stations": [SINDORIM, APGUJEONG], "ride_sec": 480,
        },
        {
            "line": 3, "board": APGUJEONG, "alight": SNUE, "direction": None,
            "stations": [
                APGUJEONG, st("304", "Sinsa"), st("303", "Express Bus Terminal"),
                st("302", "Jamwon"), st("301", "Nambu Bus Terminal"), SNUE,
            ],
            "ride_sec": 1730,
        },
    ],
    "transfers": [{"station": APGUJEONG, "from_line": 1, "to_line": 3, "sec": 300}],
}


# ----- GET /stations -----

def test_stations_en(client):
    r = client.get("/stations", params={"lang": "en"})
    assert r.status_code == 200
    stations = r.json()["stations"]
    assert len(stations) == 111
    assert [s["id"] for s in stations] == sorted(s["id"] for s in stations)
    by_id = {s["id"]: s for s in stations}
    assert by_id["101"] == {**SINDORIM, "lines": [1, 2]}
    assert by_id["102"] == {"id": "102", "name": "Guro", "lines": [1]}
    assert by_id["123"] == {**APGUJEONG, "lines": [1, 3]}


def test_stations_ko(client):
    stations = client.get("/stations", params={"lang": "ko"}).json()["stations"]
    assert stations[0] == {"id": "101", "name": "신도림", "lines": [1, 2]}


def test_stations_lang_errors(client):
    assert error(client.get("/stations", params={"lang": "ja"})) == (
        400, "UNSUPPORTED_LANGUAGE", {"lang": "ja", "supported": ["ko", "en"]})
    assert error(client.get("/stations")) == (422, "INVALID_REQUEST", {"field": "lang"})


# ----- POST /routes: 정상 -----

def test_route_time_matches_spec_example(client):
    # 101→207 최단 시간: 총 2510초, 비용 4190원, 환승 1회
    r = route(client, departure_time=DEPARTURE)
    assert r.status_code == 200
    assert r.json() == SPEC_TIME_EXAMPLE


def test_route_transfers(client):
    # 101→207 최소 환승: 2호선 하나로 3200초, 환승 0회
    data = route(client, criteria="transfers", departure_time=DEPARTURE).json()
    assert (data["total_sec"], data["transfer_count"], data["cost_won"]) == (3200, 0, 2560)
    assert data["arrival_time"] == "2026-11-04T19:23:20+09:00"
    assert data["transfers"] == []
    assert [(s["line"], s["board"]["id"], s["alight"]["id"], len(s["stations"])) for s in data["segments"]] == [
        (2, "101", "207", 8)]


def test_route_names_follow_lang(client):
    data = route(client, lang="ko").json()
    assert data["start"] == {"id": "101", "name": "신도림"}
    assert data["transfers"][0]["station"]["name"] != APGUJEONG["name"]  # 영어 이름이 아니라 한국어 이름


def test_route_without_departure_time(client):
    # 출발 시각을 안 보내면 서버 현재 한국 시각을 쓴다
    data = route(client).json()
    assert data["departure_time"].endswith("+09:00")
    elapsed = datetime.fromisoformat(data["arrival_time"]) - datetime.fromisoformat(data["departure_time"])
    assert elapsed.total_seconds() == data["total_sec"] == 2510


# ----- POST /routes: 오류 (명세 5장) -----

def test_unknown_station(client):
    assert error(route(client, end="999")) == (400, "STATION_NOT_FOUND", {"station_id": "999"})
    assert error(route(client, start="999", end="999")) == (400, "STATION_NOT_FOUND", {"station_id": "999"})


def test_same_station(client):
    assert error(route(client, end="101")) == (400, "SAME_STATION", {"station_id": "101"})


def test_no_route(client, monkeypatch):
    # 지금 데이터는 모든 역이 이어져 있어 경로 없음이 나지 않으므로, 이 테스트에서만 가짜 계산 함수로 바꾼다
    def no_route(*args):
        raise NoRouteError("테스트용")

    monkeypatch.setattr("app.api.routes.find_route", no_route)
    assert error(route(client)) == (404, "NO_ROUTE", {"start_station_id": "101", "end_station_id": "207"})


def test_invalid_criteria_and_lang(client):
    assert error(route(client, criteria="fastest")) == (422, "INVALID_REQUEST", {"field": "criteria"})
    assert error(route(client, lang="ja")) == (
        400, "UNSUPPORTED_LANGUAGE", {"lang": "ja", "supported": ["ko", "en"]})


def test_station_id_must_be_string(client):
    assert error(route(client, start=101)) == (422, "INVALID_REQUEST", {"field": "start_station_id"})


# ----- 처리 시간 로그 -----

def test_request_time_is_logged(client, caplog):
    caplog.set_level(logging.INFO, logger="subfit")
    route(client)
    messages = [r.getMessage() for r in caplog.records if r.name == "subfit"]
    assert any(m.startswith("POST /routes 200 ") and m.endswith("ms") for m in messages), messages
