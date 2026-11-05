"""PostgreSQL 접속.

접속 주소는 설정 모듈(app/config.py)이 .env의 DATABASE_URL에서 읽는다.
값이 비어 있으면 MissingSettingError, DB가 꺼져 있거나 주소가 틀리면 psycopg.OperationalError가 난다.
"""

import psycopg

from app.config import get_database_url


def connect() -> psycopg.Connection:
    """DB 연결을 하나 연다. with 문으로 쓴다.

        with connect() as conn:
            conn.execute("SELECT 1")

    with 블록이 오류 없이 끝나면 바뀐 내용을 확정(commit)하고, 오류가 나면 전부 취소(rollback)한다.
    어느 쪽이든 끝나면 연결을 닫는다.
    """
    return psycopg.connect(get_database_url())
