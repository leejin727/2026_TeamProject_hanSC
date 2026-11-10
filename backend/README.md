# SubFit 서버 (FastAPI)

설치·실행·테스트 방법은 최상위 [README.md](../README.md)의 "서버 실행과 테스트"를 본다.

| 위치 | 내용 | 담당 |
|---|---|---|
| `app/main.py` | 서버 시작점, `GET /health`, 시작할 때 노선도 한 번 읽기, 요청별 처리 시간 로그 | 이진 |
| `app/config.py` | 저장소 최상위 `.env`에서 설정 읽기, 데이터 폴더 위치(`DATA_DIR`) | 이진 |
| `app/errors.py` | 공통 오류 응답 (`docs/api-spec.md` 5장) | 이진 |
| `app/api/` | API 엔드포인트: `stations.py`(`GET /stations`), `routes.py`(`POST /routes`), `common.py`(언어·역 검사, 역 이름 붙이기) | 이진 |
| `app/db/` | PostgreSQL 접속 `connection.py`, 테이블 정의 `schema.sql` (설명: `docs/db-schema.md`) | 이진 |
| `app/routing/` | Dijkstra 경로·모임역 계산 | 표혜정 |
| `tests/` | pytest 테스트 | 이진 |
