# SubFit — AI 코딩 도구 공통 규칙

이 파일은 Claude Code와 Codex가 함께 읽는 프로젝트 규칙이다. 사용자는 개발 초보 2인 팀이므로, **변경 내용과 이유를 쉬운 한국어로 설명**한다.

## 프로젝트 개요

외국인을 위한 AI 기반 다국어 지하철 길찾기 + 모임역 추천 Android 앱 (명지대 컴퓨터공학 팀프로젝트).
핵심 기능 3가지: ① 길찾기(최단 시간·최소 환승) ② 다국어 안내(AI가 환승 과정을 문장으로 설명) ③ 모임역 추천(2~4명) + 추천 이유 설명.
부가 기능: 챗봇 (길찾기와 지하철 이용 안내를 글로 묻고 답하기, `POST /chat`, 2026-11-23 추가).

## 문서 위치와 우선순위

1. `data/extra/ASSUMPTIONS.md` — 데이터 가정과 팀 결정 사항 (**가장 우선**)
2. `docs/api-spec.md` — API 명세 (초안)
3. `docs/chatbot.md` — 챗봇 (모델, 역 이름 찾기, 답 만들기, 한계)
4. `docs/concept-design.md`, `docs/proposal.md` — 제출한 설계서 사본 (배경·요구사항 참고용)

설계서에는 "서울 열린데이터광장 실제 지하철 데이터"로 되어 있지만 **현재는 교수님 제공 가상 노선 데이터를 쓴다.** 둘이 다르면 ASSUMPTIONS.md를 따른다.

## 기술 스택

| 구분 | 기술 | 위치 |
|---|---|---|
| 앱 | Flutter (Android 11 이상) | `app/` |
| 서버 | FastAPI (Python) | `backend/` |
| DB | PostgreSQL | `backend/app/db/` |
| AI | Google Gemini API (서버에서만 호출) | `backend/app/` |
| 경로 계산 | Dijkstra | `backend/app/routing/` |
| 챗봇 | 직접 만든 나노 모델 (C++ 실행기, 외부 AI 없음) | `backend/app/chat/` |

## 폴더 담당 (담당자 폴더 밖을 고쳐야 하면 먼저 사용자에게 알린다)

- 이진: `backend/` (routing 제외), `data/`, `docs/`, `scripts/`
- 표혜정: `app/`, `backend/app/routing/`

## 데이터 규칙 (반드시 지킬 것)

- `data/raw/stations.xlsx`는 교수님 원본이다. **절대 수정하지 않는다.**
- 원본 열: 출발역, 도착역, 시간(초), 거리(미터), 비용(원). 구간은 양방향, 두 방향 값은 같다.
- **역 번호 앞자리로 노선을 추정하지 않는다** (예: 409–608 구간은 8호선). 노선은 항상 `data/extra/line_stations.csv` 기준.
- 1·6호선은 순환선이다 (`data/extra/lines.csv`).
- 환승역은 노선별로 다른 노드로 나눈다. 예: `113@1`, `113@8`. 환승 시간은 `data/extra/transfers.csv` (현재 1회당 300초).
- 역 이름은 `data/extra/station_names.csv`. 실제 서울 역명을 빌렸지만 **위치·연결은 가상**이다.
- 데이터 관련 코드를 바꾼 뒤에는 `python scripts/validate_data.py`를 실행해 통과를 확인한다.

## 설계 원칙

- **계산은 알고리즘, 설명은 AI.** 경로·모임역·방향·소요 시간은 코드로 계산하고, Gemini는 그 결과만 받아 문장으로 설명한다.
- 경로·모임역 설명용 Gemini 프롬프트에는 "주어진 데이터 외의 정보(실제 서울 지하철 노선, 주변 시설 등)는 말하지 말 것"을 넣는다.
- 예외: 주변 시설(`GET /stations/{id}/facilities`)은 실제 데이터가 없어서, 역 이름만 빌려 Gemini가 **예시**를 만든다 (팀 결정 2026-11-18, ASSUMPTIONS.md). 응답에 `ai_generated: true`를 넣고, 앱은 "AI가 만든 예시이며 실제와 다를 수 있음"을 함께 보여 준다. 키는 `GEMINI_FACILITY_API_KEY`를 따로 쓴다.
- 경로 계산 API와 AI 설명 API는 분리한다. 성능 목표: 경로 2초 이하, AI 설명 12초 이하 (처음 5초에서 2026-11-18 변경: Gemini 응답이 5~11초 걸리는 때가 있어서. 앱은 경로를 먼저 보여 주고 설명만 따로 기다린다).
- 같은 경로 + 같은 언어의 AI 설명은 저장해 재사용한다 (비용 절감, 총 예산 5만 원).
- 챗봇(`POST /chat`)은 Gemini를 부르지 않는다. 무엇을 묻는지는 나노 모델이 고르고, 경로는 기존 계산 코드가 계산하고, 답은 `data/chat/replies.json`의 고정 문구다. 대화 내용은 저장하지 않고 로그에도 남기지 않는다. `backend/app/chat/nano/` 안의 파일은 받은 그대로 두고 **고치지 않는다** (ASSUMPTIONS.md "챗봇").

## 아직 확정되지 않은 사항 — 임의로 정하지 말고 사용자에게 물어볼 것

- 부가 기능 범위 (첫차·막차, 실시간 도착)

확정되면 ASSUMPTIONS.md에 기록되고 이 목록에서 지운다.

## 보안

- API 키와 DB 비밀번호는 `.env`에만 둔다. 코드, 커밋, 로그, 앱(Flutter)에 넣지 않는다.
- 새 환경변수가 필요하면 `.env.example`에 **이름만** 추가한다.
- Gemini 키는 서버에서만 쓴다. 앱은 우리 서버 API만 호출한다.

## Git 규칙

- **세션을 시작하면 먼저 현재 브랜치와 `git status`를 확인해 사용자에게 알려 준다.** main 브랜치라면 작업 전에 새 브랜치를 만들자고 안내한다:
  `git switch main` → `git pull` → `git switch -c feature/작업이름`
- main에 직접 커밋하지 않는다.
- 브랜치 이름: `feature/…`, `fix/…`, `docs/…`
- 커밋 메시지: `feat:` 기능, `fix:` 버그 수정, `docs:` 문서, `chore:` 설정·기타 + 한국어 설명
- **push, merge, 브랜치 삭제, `--force`, `reset --hard` 같은 명령은 AI가 실행하지 않는다.** 필요하면 명령어를 알려 주고 사용자가 직접 실행하게 한다.
- 커밋 전에 `.env`나 `.venv`가 포함되지 않았는지 확인한다.

## 작업 방식

- 여러 파일을 바꾸는 작업은 **계획을 먼저 보여 주고 승인받은 뒤** 진행한다.
- 한 번에 하나의 작은 기능만 다룬다.
- 새 패키지를 추가할 때는 이유를 설명하고 의존성 파일(`requirements.txt`, `pubspec.yaml`)에 기록한다.
- 확실하지 않은 라이브러리 사용법은 추측하지 말고 그렇다고 말한다.
- 작업이 끝나면 무엇을 바꿨는지, 어떻게 실행·확인하는지 알려 준다.

## 실행 명령

```bash
# 데이터 검증 (저장소 최상위에서)
source .venv/bin/activate
python scripts/validate_data.py

# 서버 패키지 설치 (저장소 최상위에서, 처음 한 번)
pip install -r backend/requirements.txt

# 서버 실행 (backend/에서) → http://localhost:8000/docs
cd backend && uvicorn app.main:app --reload

# 서버 테스트 (backend/에서)
cd backend && pytest

# DB 표 만들기 + 데이터 넣기 (저장소 최상위에서, PostgreSQL 켜져 있어야 함, 여러 번 실행해도 됨)
# 표 구조: docs/db-schema.md
python scripts/load_db.py

# 앱 실행
cd app && flutter run
```
