"""SubFit 서버의 시작점. 실행: backend 폴더에서 `uvicorn app.main:app --reload`"""

from fastapi import FastAPI

from app.errors import register_error_handlers

app = FastAPI(title="SubFit API")
register_error_handlers(app)


@app.get("/health")
def health() -> dict[str, str]:
    """서버가 켜져 있는지 확인하는 용도."""
    return {"status": "ok"}
