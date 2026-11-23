# SubFit

외국인을 위한 AI 기반 다국어 지하철 길찾기 및 모임역 추천 앱 (명지대 컴퓨터공학 팀프로젝트 2조)

## 폴더 구조

| 폴더 | 내용 | 담당 |
|---|---|---|
| `app/` | Flutter 앱 (Android) | 표혜정 |
| `backend/` | FastAPI 서버, DB, Gemini 연동, 챗봇 | 이진 |
| `backend/app/routing/` | Dijkstra 경로·모임역 계산 | 표혜정 |
| `data/raw/` | 교수님 원본 데이터 (**수정 금지**) | - |
| `data/extra/` | 팀이 만든 보조 데이터 (노선 순서, 역 이름, 환승) | 이진 |
| `data/chat/` | 챗봇 답 문구 (한국어·영어) | 이진 |
| `scripts/` | 데이터 검증 등 보조 스크립트 | - |
| `docs/` | 설계서, API 명세 | 공동 |

데이터 가정은 `data/extra/ASSUMPTIONS.md` 참고.

## 데이터 검증

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r scripts/requirements.txt
python scripts/validate_data.py
```

## 서버 실행과 테스트

가상환경은 저장소 최상위 `.venv` 하나를 같이 쓴다. `.venv`가 없으면 위 "데이터 검증"의 첫 줄로 먼저 만든다.

**처음 한 번** (저장소 최상위 폴더에서)

```bash
source .venv/bin/activate
pip install -r backend/requirements.txt
cp .env.example .env    # .env가 아직 없을 때만. 값이 비어 있어도 서버는 켜진다
```

**서버 실행** (`backend/` 폴더에서)

```bash
source .venv/bin/activate    # 저장소 최상위에서
cd backend
uvicorn app.main:app --reload
```

- 브라우저에서 http://localhost:8000/docs 를 열면 API 목록과 테스트 화면이 나온다.
- `--reload`: 코드를 저장하면 서버가 자동으로 다시 켜진다. 끌 때는 `Ctrl + C`.

**테스트** (`backend/` 폴더에서)

```bash
source .venv/bin/activate    # 저장소 최상위에서
cd backend
pytest
```

## DB 만들기와 데이터 넣기

PostgreSQL이 켜져 있어야 한다. 표 구조와 설명은 `docs/db-schema.md`.

**처음 한 번** (저장소 최상위 폴더에서)

```bash
createdb subfit    # DB가 아직 없을 때만
```

`.env`의 `DATABASE_URL`이 이 DB를 가리키는지 확인한다 (예: `postgresql://localhost:5432/subfit`).

**표 만들기 + 데이터 넣기** (저장소 최상위 폴더에서, 데이터가 바뀔 때마다)

```bash
source .venv/bin/activate
python scripts/load_db.py
```

- 위 "데이터 검증"과 "서버 실행과 테스트"의 패키지(`scripts/requirements.txt`, `backend/requirements.txt`)가 둘 다 설치되어 있어야 한다.
- 몇 번을 실행해도 결과가 같다. 끝에 `✅ 적재 완료, 검증 통과`가 나오면 성공이다.
- 주변 시설 AI 예시(`data/extra/ai_facilities.json`)도 함께 넣는다. 이 파일을 새로 만들거나 채울 때만 아래를 실행한다 (`.env`의 `GEMINI_FACILITY_API_KEY` 사용, 이미 있는 것은 건너뜀, 멈춰도 다시 실행하면 이어서 만듦).

  ```bash
  python scripts/generate_facilities.py --lang ko en   # 언어 생략하면 6개 전부
  ```

## 협업 규칙

- `main` 브랜치에 직접 push하지 않는다. 작업은 브랜치 → PR → 상대방 승인 → 병합.
- 브랜치 이름: `feature/기능`, `fix/버그`, `docs/문서`
- 커밋 메시지: `feat:` 기능, `fix:` 버그 수정, `docs:` 문서, `chore:` 설정·기타
- API 키는 `.env`에만 저장한다.
