# 모임역 추천 구현 및 연동 안내

기준: GitHub main 커밋 ad73f9ad59b5af59b1e2b0b4f231098df4d81ae1 (2026-11-17 확인).
이 폴더는 최신 백엔드·데이터·테스트의 로컬 사본입니다. 원격 GitHub에는 변경하지 않았습니다.

## 기존 코드와 달라진 점
최신 프로젝트는 역 ID를 문자열로 사용하고, 기존 /routes 결과에는 cost_won이 있습니다.
이 계약은 유지합니다. 새 모임역 기능은 요금을 읽거나 누적하지 않고 응답에도 포함하지 않습니다.
원본 CSV·Excel과 graph_builder.py, models.py는 변경하지 않았습니다.
실제 transfers.csv의 환승 35개는 모두 300초이며, 모임역 함수에서 추가 환승시간을 덧붙이지 않습니다.

## 공통 탐색
dijkstra.search(network,start,criteria,end=None)는 노드별 최선 기록, 이전 노드와 이동 간선,
역별 선택한 도착 노드를 SearchResult로 반환합니다.
기존 find_route는 end를 지정해 목적지에서 종료합니다. 모임역은 end 없이 전체 탐색을 수행합니다.
출발역의 모든 호선 노드를 0으로 우선순위 큐에 넣습니다.
탐색 후보를 꺼냈을 때 오래된 탐색 기록은 건너뛰고, 개선된 최선 기록만 다시 등록합니다.
역별로 우선순위 큐에서 처음 확정된 노드가 해당 역의 최선 기록과 도착 노드입니다.
restore_route는 저장된 이전 노드를 따라 경로를 복원합니다. 추천 점수에 쓰인 도착 노드를 그대로 전달합니다.

## 추천 기준
| criteria | 개인 경로의 탐색 기록 | 추천역 비교 순서 |
|---|---|---|
| time | (누적 소요 시간, 환승 횟수) | 시간 합계 → 숫자 역 번호 |
| transfers | (환승 횟수, 누적 소요 시간) | 환승 합계 → 해당 경로 시간 합계 → 숫자 역 번호 |
| fairness | (누적 소요 시간, 환승 횟수) | 최대 시간 → 시간 합계 → 숫자 역 번호 |

fairness는 minimax이며 시간 차이나 분산을 최소화하지 않습니다.
time 기준에서 역별 시간 합계가 같을 때 환승 합계를 새 추천 목적으로 추가하지 않습니다.
최종 동점은 문자열 사전순이 아니라 숫자 역 번호 순으로 결정합니다 (예: 2 < 10).
후보는 network.names 전체이며 역 개수를 고정하지 않습니다.
중복 출발역은 전체 탐색을 재사용하되 입력 순서대로 각각의 참여자로 합산합니다.
공통으로 도달할 후보가 없으면 NoMeetingStationError, API에서는 404 NO_MEETING_STATION입니다.

find_meeting_station은 한 기준을 계산하고,
find_meeting_stations는 기본적으로 세 기준을 함께 계산합니다.
요청 안에서 (출발역,모드)별 탐색을 한 번만 수행합니다.
time과 fairness는 같은 탐색 기록을 공유합니다. 요청 간 영구 캐시는 없습니다.

복잡도: 서로 다른 출발역 k개, 노드 V개, 간선 E개, 후보역 S개일 때
한 모드 탐색은 O(k(V+E)log V), 후보 평가는 O(참여자 수 × S)입니다.
경로 복원은 최종 추천역에 대해서만 수행합니다.

## API
POST /meeting-station
```json
{"start_station_ids":["101","101","207"],"criteria":"transfers","lang":"ko"}
```
역 ID는 기존 API처럼 문자열이어야 합니다.
criteria는 time/transfers/fairness, lang은 ko/en입니다.
기존 명세의 station, participants, nearby_facilities 필드를 유지하고 상세 경로와 합계를 확장합니다.
참여자별 stations는 환승으로 인한 연속 중복을 생략하며 실제 재방문은 유지합니다.
0초 경로는 stations에 출발역 하나만 있고 segments와 transfers는 빈 목록입니다.
응답 전체 예시는 docs/meeting-example.json에 저장합니다.

오류:
- 잘못된 JSON·형식·criteria: 422 INVALID_REQUEST
- 참여자 수 2~4 범위 밖: 400 INVALID_PARTICIPANT_COUNT
- 없는 역: 400 STATION_NOT_FOUND
- 지원하지 않는 언어: 400 UNSUPPORTED_LANGUAGE
- 공통 후보 없음: 404 NO_MEETING_STATION

기존 /routes의 SAME_STATION 동작은 유지하지만, 모임역 참여자의 출발역=추천역은 허용합니다.
Flutter는 기존 명세의 요청 필드를 그대로 보내고 participants를 입력 순서대로 표시하면 됩니다.
HTTP API는 한 기준씩 받습니다. 현재 모임역 UI 구현은 이번 작업 범위에서 수정하지 않았습니다.
여러 기준이 필요한 Python 호출에서는 find_meeting_stations로 탐색 기록을 공유할 수 있습니다.

## 재현
프로젝트 루트:
```text
python -m pip install -r backend/requirements.txt -r scripts/requirements.txt
python scripts/validate_data.py
cd backend
python -m pytest -q
python -m tests.verify_full_network
uvicorn app.main:app --reload
```

기존 회귀 테스트를 유지하고 작은 그래프의 모든 단순 노드 경로 열거 결과와 추천을 비교합니다.
64개 출발 조합 × 3기준 = 192개 사례에서 모든 후보역 점수를 대조합니다.
실제 노선에서도 여러 입력의 모든 후보역을 기존 단일 목적지 탐색과 비교합니다.
API 테스트는 실제 연결된 엔드포인트에서 정상·오류·중복·추천 불가 응답을 검증합니다.
외부 Gemini 호출과 PostgreSQL 연결은 모임역 계산에 사용하지 않습니다.

## 변경 파일
- backend/app/routing/dijkstra.py: 전체 탐색과 경로 복원 공통화, 기존 인터페이스 유지
- backend/app/routing/meeting.py: 세 기준 추천, 요청 안의 탐색 재사용, 요금 없는 결과 자료형
- backend/app/api/meeting.py, backend/app/main.py: 기존 오류·역 이름 형식으로 API 연결
- backend/tests/test_meeting.py, backend/tests/test_meeting_api.py: 추천·효율·API 테스트
- docs/api-spec.md, docs/meeting-algorithm.md, docs/meeting-example.json: 확정 계약과 예시
- data/extra/ASSUMPTIONS.md, AGENTS.md: 사용자가 확정한 모임역 규칙 기록
- .github/workflows/routing-tests.yml: 서버 전체 테스트 포함 및 feature 브랜치 적용

새 의존성은 추가하지 않았습니다. 기존 requirements.txt의 패키지로 검증합니다.
방향 표기는 기존대로 null, nearby_facilities는 기존 명세대로 빈 목록입니다.

## 실행한 검증 결과 (2026-11-17)
- 기존 경로 unittest: 21개 통과.
- 신규 추천 unittest: 14개 통과. 모든 단순 노드 경로 열거로 192개 작은 그래프 추천 사례 대조 포함.
- 신규 API pytest: 14개 통과 (실제 모임역 라우터와 공통 오류 처리기를 별도 FastAPI 앱에 연결).
- 기존 verify_full_network: 24,642개 경로의 시간·환승 기록, 반환 경로 및 기존 요금 결과 검사 통과.
- 전체 pytest: 기존 app.main → AI → psycopg 로딩 중 Windows 애플리케이션 제어 정책이 DLL을 차단하여 수집 실패. 전체 서버 통합 통과로 보고하지 않음.
- 공식 scripts/validate_data.py: pandas → NumPy DLL 로딩 차단으로 실행 실패. 일반 실행 환경에서도 동일.
- 원본 CSV 4개와 stations.xlsx의 Git blob SHA가 기준 커밋과 일치함.
- 새 Python 패키지는 요구사항에 추가하지 않았으며 기존 requirements에 따라 별도 work 환경에 설치함.

## Flutter 연동 확인
기존 meeting_input_screen.dart는 선택한 기준 하나와 입력 문자열을 결과 화면에 넘기며,
meeting_result_screen.dart는 예시 역·시간을 고정 표시합니다. 아직 HTTP 연결은 없습니다.
화면을 변경하지 않았습니다. 다음 매핑으로 연결하면 됩니다:
- fastest → time
- fewestTransfers → transfers
- fairest → fairness
자유 입력한 역 이름을 그대로 ID로 보내지 말고 GET /stations로 받은 실제 역 ID를 선택해 전송해야 합니다.
현재 화면은 한 기준을 선택하므로 한 API 요청당 출발역별 한 모드만 탐색합니다.
서버에서 세 기준을 함께 계산할 경우 find_meeting_stations가 두 모드 탐색 기록을 재사용합니다.

## 실제 데이터 확인 예
입력 ["101","101","207"]:
| 기준 | 추천역 | 전체 시간 합계(초) | 환승 합계 | 최대 시간(초) |
|---|---|---:|---:|---:|
| time | 101 신도림 | 2510 | 1 | 2510 |
| transfers | 123 압구정 | 2690 | 0 | 1730 |
| fairness | 303 고속터미널 | 3940 | 2 | 1430 |

docs/meeting-example.json은 실제 API 처리 함수를 실행하여 저장한 전체 응답입니다.
응답 이름은 기존 station_names.csv를 사용합니다.

## 사용자 확인 및 반영
변경 파일 ZIP은 기준 커밋 이후 같은 파일을 수정한 팀원의 작업과 비교한 후 적용해야 합니다.
로컬 사본에는 Flutter 전체 프로젝트가 포함되어 있지 않습니다.
GitHub에는 아직 커밋·푸시하지 않았습니다.
정상적인 Python 실행 환경 또는 GitHub Actions에서 공식 데이터 검증 및 전체 pytest 재실행이 필요합니다.
