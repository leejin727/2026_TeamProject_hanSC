"""모든 오류를 같은 모양으로 돌려주는 공통 처리기 (docs/api-spec.md 5장).

    {"error": {"code": "STATION_NOT_FOUND", "message": "...", "details": {...}}}

- code: 앱이 오류 종류를 구분하는 고정 값
- message: 개발자가 보는 한국어 문장
- details: 추가 정보. 없으면 응답에서 빠진다
"""

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class AppError(Exception):
    """API 코드에서 직접 내는 오류. 예:

    raise AppError(400, "STATION_NOT_FOUND", "존재하지 않는 역입니다: 999", {"station_id": "999"})
    """

    def __init__(self, status_code: int, code: str, message: str, details: dict | None = None):
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details


def error_response(
    status_code: int,
    code: str,
    message: str,
    details: dict | None = None,
    headers: dict | None = None,
) -> JSONResponse:
    error = {"code": code, "message": message}
    if details:
        error["details"] = details
    return JSONResponse(status_code=status_code, content={"error": error}, headers=headers)


async def handle_app_error(request: Request, exc: AppError) -> JSONResponse:
    return error_response(exc.status_code, exc.code, exc.message, exc.details)


async def handle_validation_error(request: Request, exc: RequestValidationError) -> JSONResponse:
    """필수 값 누락, 타입 오류, JSON 형식 오류 등. FastAPI 기본 {"detail": [...]} 대신 쓴다."""
    errors = exc.errors()
    first = errors[0] if errors else {}
    # loc 예: ("body", "criteria") → "criteria". 맨 앞은 위치(body/query 등)라 뺀다.
    # JSON 형식 오류는 ("body", 12)처럼 숫자뿐이라 field가 비고 details도 빠진다.
    field = ".".join(part for part in first.get("loc", ())[1:] if isinstance(part, str))
    message = "요청 값이 올바르지 않습니다"
    if field:
        message += f" ({field})"
    message += f": {first.get('msg', '')}"
    return error_response(422, "INVALID_REQUEST", message, {"field": field} if field else None)


# 프레임워크가 내는 HTTP 오류 중 이름을 붙인 것들
HTTP_ERRORS = {
    404: ("NOT_FOUND", "존재하지 않는 주소입니다"),
    405: ("METHOD_NOT_ALLOWED", "이 주소에서 허용하지 않는 요청 방식입니다"),
}


async def handle_http_error(request: Request, exc: StarletteHTTPException) -> JSONResponse:
    """없는 주소(404), 허용하지 않는 방식(405) 등 FastAPI가 직접 내는 오류."""
    fallback_code = "INTERNAL_ERROR" if exc.status_code >= 500 else "INVALID_REQUEST"
    code, message = HTTP_ERRORS.get(exc.status_code, (fallback_code, str(exc.detail)))
    # 405 응답의 Allow 헤더(허용하는 방식 목록) 등을 그대로 유지한다.
    return error_response(exc.status_code, code, message, headers=exc.headers)


async def handle_unexpected_error(request: Request, exc: Exception) -> JSONResponse:
    """예상하지 못한 모든 오류. 사용자에게는 짧은 문구만 준다.
    오류 내용(traceback)은 이 처리기 다음에 서버 터미널에 따로 출력된다."""
    return error_response(500, "INTERNAL_ERROR", "서버 내부 오류입니다. 서버 터미널의 오류 내용을 확인하세요.")


def register_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(AppError, handle_app_error)
    app.add_exception_handler(RequestValidationError, handle_validation_error)
    app.add_exception_handler(StarletteHTTPException, handle_http_error)
    app.add_exception_handler(Exception, handle_unexpected_error)
