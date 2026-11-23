"""SubFit 서버의 시작점. 실행: backend 폴더에서 `uvicorn app.main:app --reload`"""

import logging
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request

from app.api import chat, explain, facilities, meeting, routes, stations
from app.config import DATA_DIR
from app.errors import register_error_handlers
from app.routing.graph_builder import load_network

# 처리 시간 로그를 서버 터미널에 보이게 한다 (uvicorn 자체 로그와는 따로 찍힌다).
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
logger = logging.getLogger("subfit")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """서버가 켜질 때 한 번 실행된다. 노선도를 읽어 메모리에 두고 모든 요청에서 같이 쓴다."""
    app.state.network = load_network(DATA_DIR)
    yield


app = FastAPI(title="SubFit API", lifespan=lifespan)
register_error_handlers(app)
app.include_router(stations.router)
app.include_router(facilities.router)
app.include_router(routes.router)
app.include_router(meeting.router)
app.include_router(explain.router)
app.include_router(chat.router)


@app.middleware("http")
async def log_process_time(request: Request, call_next):
    """모든 요청의 처리 시간을 로그에 남긴다. 예: POST /routes 200 3.1ms"""
    start = time.perf_counter()
    status = 500  # 예상 못 한 오류로 응답 없이 끝나면 500으로 기록한다
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        ms = (time.perf_counter() - start) * 1000
        logger.info("%s %s %d %.1fms", request.method, request.url.path, status, ms)


@app.get("/health")
def health() -> dict[str, str]:
    """서버가 켜져 있는지 확인하는 용도."""
    return {"status": "ok"}
