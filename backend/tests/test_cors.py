"""웹(크롬)에서 실행한 앱이 서버를 부를 수 있는지 (CORS 설정, app/main.py)."""

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_chat_preflight_is_allowed():
    # 브라우저가 POST /chat을 보내기 전에 먼저 보내는 확인 요청(OPTIONS)과 같은 모양
    response = client.options(
        "/chat",
        headers={
            "Origin": "http://localhost:5000",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "content-type",
        },
    )

    assert response.status_code == 200
    assert response.headers.get("access-control-allow-origin") == "*"
