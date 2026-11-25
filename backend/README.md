# SubFit 서버 (FastAPI)

설치·실행·테스트 방법은 최상위 [README.md](../README.md)의 "서버 실행과 테스트"를 본다.

| 위치 | 내용 | 담당 |
|---|---|---|
| `app/main.py` | 서버 시작점, `GET /health`, 시작할 때 노선도 한 번 읽기, 요청별 처리 시간 로그 | 이진 |
| `app/config.py` | 저장소 최상위 `.env`에서 설정 읽기, 데이터 폴더 위치(`DATA_DIR`) | 이진 |
| `app/errors.py` | 공통 오류 응답 (`docs/api-spec.md` 5장) | 이진 |
| `app/api/` | API 엔드포인트: `stations.py`(`GET /stations`), `routes.py`(`POST /routes`), `meeting.py`(`POST /meeting-station`), `explain.py`(`POST /explain`), `facilities.py`(`GET /stations/{id}/facilities`), `chat.py`(`POST /chat`), `common.py`(언어·역 검사, 역 이름 붙이기) | 이진 |
| `app/ai/` | AI: `client.py`(Gemini 호출, 12초 제한, 설명용·시설용 키 따로), `prompts.py`(경로·모임역·주변 시설 프롬프트), `explain.py`(재계산 → 캐시 → Gemini → 저장), `facilities.py`(주변 시설 AI 예시: 한국어로 만들고 다른 언어는 번역 → 저장) | 이진 |
| `app/chat/` | 챗봇 (Gemini를 부르지 않음): `nano/`(직접 만든 의도 판단 모델과 규칙. 받은 그대로 두고 고치지 않음), `stations.py`(문장 속 역 이름 찾기, 오타·줄임말 포함), `service.py`(답 만들기: 길찾기는 기존 경로 계산, 나머지는 `data/chat/replies.json`의 문구), `settings.py`(기준값). 설명: `docs/chatbot.md` | 이진 |
| `app/db/` | PostgreSQL 접속 `connection.py`, 테이블 정의 `schema.sql` (설명: `docs/db-schema.md`) | 이진 |
| `app/routing/` | Dijkstra 경로·모임역 계산 | 표혜정 |
| `tests/` | pytest 테스트 | 이진 |
