import pytest
from fastapi.testclient import TestClient
from fastapi import FastAPI
from pathlib import Path
from app.api.meeting import router
from app.errors import register_error_handlers
from app.routing.graph_builder import load_network

# 실제 라우터·공통 오류 처리기만 검증한다. 전체 서버 회귀는 기존 test_api.py가 담당한다.
app = FastAPI()
app.include_router(router)
register_error_handlers(app)
from app.routing.graph_builder import Network

@pytest.fixture
def client():
    app.state.network = load_network(Path(__file__).resolve().parents[2] / "data")
    with TestClient(app) as c:
        yield c

def post(client, **updates):
    body={"start_station_ids":["101","207"],"criteria":"time","lang":"en"}
    body.update(updates)
    return client.post("/meeting-station",json=body)

@pytest.mark.parametrize("criteria",["time","transfers","fairness"])
def test_meeting_success(client,criteria):
    response=post(client,criteria=criteria)
    assert response.status_code==200
    data=response.json()
    assert data["criteria"]==criteria
    assert [p["start"]["id"] for p in data["participants"]]==["101","207"]
    assert data["total_travel_sec"]==sum(p["travel_sec"] for p in data["participants"])
    assert data["total_transfer_count"]==sum(p["transfer_count"] for p in data["participants"])
    assert data["max_travel_sec"]==max(p["travel_sec"] for p in data["participants"])
    assert "cost_won" not in response.text
    assert data["nearby_facilities"]==[]
    for p in data["participants"]:
        assert p["stations"][0]==p["start"]
        assert p["stations"][-1]==data["station"]
        assert p["travel_sec"]==sum(s["ride_sec"] for s in p["segments"])+sum(t["sec"] for t in p["transfers"])

@pytest.mark.parametrize("starts",[[],["101"],["101"]*5])
def test_count(client,starts):
    r=post(client,start_station_ids=starts)
    assert r.status_code==400
    assert r.json()["error"]["code"]=="INVALID_PARTICIPANT_COUNT"

@pytest.mark.parametrize("starts",[None,"101",[101,"207"],[True,"207"],[None,"207"]])
def test_bad_format(client,starts):
    r=post(client,start_station_ids=starts)
    assert r.status_code==422
    assert r.json()["error"]["code"]=="INVALID_REQUEST"

def test_language_and_station(client):
    assert post(client,lang="ja").json()["error"]["code"]=="UNSUPPORTED_LANGUAGE"
    assert post(client,start_station_ids=["999","101"]).json()["error"]["code"]=="STATION_NOT_FOUND"
    assert post(client,criteria="variance").status_code==422

def test_duplicate_and_localized_names(client):
    r=post(client,start_station_ids=["101","101"],lang="ko").json()
    assert r["station"]=={"id":"101","name":"신도림"}
    assert len(r["participants"])==2
    assert r["total_travel_sec"]==r["total_transfer_count"]==0

def test_no_common_station(client):
    # 실제 연결 지점까지 검사하며 계산 함수를 가짜 결과로 대체하지 않는다.
    original=app.state.network
    app.state.network=Network({("1",1):[],("2",2):[]},{"1":("가","A"),"2":("나","B")})
    try:
        r=post(client,start_station_ids=["1","2"])
        assert r.status_code==404
        assert r.json()["error"]["code"]=="NO_MEETING_STATION"
    finally:
        app.state.network=original
