"""서버 설정. 저장소 최상위의 .env 파일에서 값을 읽는다.

값이 비어 있어도 서버는 켜진다. 그 값이 필요한 기능이 아래 get_... 함수를 부를 때
비어 있으면 MissingSettingError가 난다.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

# 이 파일 위치: backend/app/config.py → 세 단계 위가 저장소 최상위.
# 서버를 어느 폴더에서 켜든 항상 같은 .env를 읽는다.
ENV_FILE = Path(__file__).resolve().parents[2] / ".env"

# .env가 없어도 오류 없이 넘어간다. 이미 설정된 환경변수가 있으면 그 값이 우선이다.
load_dotenv(ENV_FILE)


class MissingSettingError(RuntimeError):
    """필요한 설정 값이 .env에 없을 때 나는 오류."""


def _require(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        # 값이 아니라 이름만 메시지에 넣는다 (비밀 값이 로그에 남지 않게).
        raise MissingSettingError(
            f"{name} 값이 비어 있습니다. 저장소 최상위 .env 파일에 {name}=... 을 채우고 "
            f"서버를 다시 켜세요. (.env가 없으면 .env.example을 복사해 만드세요)"
        )
    return value


def get_database_url() -> str:
    return _require("DATABASE_URL")


def get_gemini_api_key() -> str:
    return _require("GEMINI_API_KEY")
