# SubFit

외국인을 위한 AI 기반 다국어 지하철 길찾기 및 모임역 추천 앱 (명지대 컴퓨터공학 팀프로젝트 2조)

## 폴더 구조

| 폴더 | 내용 | 담당 |
|---|---|---|
| `app/` | Flutter 앱 (Android) | 표혜정 |
| `backend/` | FastAPI 서버, DB, Gemini 연동 | 이진 |
| `backend/app/routing/` | Dijkstra 경로·모임역 계산 | 표혜정 |
| `data/raw/` | 교수님 원본 데이터 (**수정 금지**) | - |
| `data/extra/` | 팀이 만든 보조 데이터 (노선 순서, 역 이름, 환승) | 이진 |
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

## 협업 규칙

- `main` 브랜치에 직접 push하지 않는다. 작업은 브랜치 → PR → 상대방 승인 → 병합.
- 브랜치 이름: `feature/기능`, `fix/버그`, `docs/문서`
- 커밋 메시지: `feat:` 기능, `fix:` 버그 수정, `docs:` 문서, `chore:` 설정·기타
- API 키는 `.env`에만 저장한다.
