"""서버 설정. 저장소 최상위의 .env 파일에서 값을 읽는다.

값이 비어 있어도 서버는 켜진다. 그 값이 필요한 기능이 아래 get_... 함수를 부를 때
비어 있으면 MissingSettingError가 난다.
"""

import os
from pathlib import Path

from dotenv import load_dotenv

# 이 파일 위치: backend/app/config.py → 세 단계 위가 저장소 최상위.
# 서버를 어느 폴더에서 켜든 항상 같은 .env와 data/ 폴더를 읽는다.
ROOT = Path(__file__).resolve().parents[2]
ENV_FILE = ROOT / ".env"
DATA_DIR = ROOT / "data"  # 노선 데이터: raw/stations.xlsx + extra/*.csv

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


def get_gemini_facility_api_key() -> str:
    """주변 시설(AI 예시)용 키. 설명용 키와 사용량을 나누려고 따로 둔다 (팀 결정 2026-11-18).
    비어 있어도 GEMINI_API_KEY로 대신 쓰지 않는다."""
    return _require("GEMINI_FACILITY_API_KEY")


# 설계서에는 gemini-3.7-flash로 적었지만, 2026-10-08부터 지원 종료 예정(deprecated)이고 요청이
# gemini-3.8-flash로 자동으로 넘어간다. 3.8-flash는 응답이 약 7.5초 걸려 당시 5초 제한(AI 설명 목표)을 넘었다.
# 그래서 공식 권장·무료 티어인 flash 계열 중 가장 빠른(약 1초) 모델을 기본값으로 쓴다 (2026-11-16 확인).
DEFAULT_GEMINI_MODEL = "gemini-3.5-flash-lite"


def get_gemini_model() -> str:
    """.env의 GEMINI_MODEL. 비어 있으면 DEFAULT_GEMINI_MODEL."""
    return os.getenv("GEMINI_MODEL", "").strip() or DEFAULT_GEMINI_MODEL
