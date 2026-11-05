# SubFit 서버 API 명세 (초안)

> 작성 2026-11-04 · 아직 서버 코드는 없음. 이 문서를 보고 앱에서 가짜 데이터(mock)를 만들 수 있게 하는 것이 목표.
> 데이터 규칙은 `data/extra/ASSUMPTIONS.md`가 우선이다. **(가안)** 표시는 팀 결정 전 임시 값이며, 끝의 [논의 필요](#7-논의-필요)에서 확정한다.
> 예시 값은 모두 실제 데이터(`stations.xlsx` + `data/extra/*.csv`)로 계산한 값이다.

## 0. 공통 사항

| API | 하는 일 | 응답 목표 |
|---|---|---|
| `GET /stations` | 역 목록 | – |
| `POST /routes` | 경로 계산 (최단 시간 / 최소 환승) | 2초 이하 |
| `POST /meeting-station` | 모임역 추천 (2~4명) | – |
| `POST /explain` | 경로·모임역 결과를 AI가 문장으로 설명 | 5초 이하 |

경로 계산과 AI 설명은 일부러 나눠 두었다. 앱은 `/routes` 결과를 먼저 화면에 그리고, 설명은 `/explain`으로 따로 받는다. 그래서 AI가 실패해도 경로는 보인다.

**값 표기 규칙**

| 항목 | 형식 | 예 |
|---|---|---|
| 역 ID | 문자열 | `"101"` |
| 역 객체 | `{"id", "name"}` — `name`은 요청한 `lang`의 이름 | `{"id": "101", "name": "Sindorim"}` |
| 노선 | 정수 1~9 | `3` |
| 시간 | 초 단위 정수, 필드 이름이 `_sec`로 끝남 | `2510` |
| 시각 | ISO 8601, 한국 시간 `+09:00` | `"2026-11-04T18:30:00+09:00"` |
| 비용 | 원 단위 정수 `cost_won` | `4190` |

- 역 번호는 이름표일 뿐이다. **앞자리로 노선을 추정하지 않는다** (ASSUMPTIONS.md). 노선은 항상 응답의 `line`과 `lines` 값을 쓴다.
- 환승역도 API에서는 ID가 하나다 (예: `"123"`). 노선별로 나눈 노드(`123@1`, `123@3`)는 서버 안에서만 쓰고 앱에는 나오지 않는다.
- 비용은 지나간 구간 비용을 단순히 더한 값이다. **실제 지하철 요금이 아니며** 실제 요금 규칙은 적용하지 않는다 (ASSUMPTIONS.md).
- 거리(미터)는 원본에 있지만 API 응답에는 넣지 않는다 (팀 결정 2026-11-05).
- 모든 구간은 양방향이고 두 방향의 시간·비용이 같다 (ASSUMPTIONS.md). 예: 207→101 최단 시간 경로는 2장 첫 예시를 거꾸로 탄 경로다. `total_sec` 2510과 `cost_won` 4190은 같고, `direction`만 반대쪽이다 (3호선 구간은 `107` 종로3가 방면).
- 역 이름은 실제 서울 역명을 빌려 왔지만 위치와 순서는 실제와 관계없는 가상 배치다 (ASSUMPTIONS.md).

**`lang` 값**

| 쓰는 곳 | 허용 값 | 비고 |
|---|---|---|
| 역 이름 (`/stations`, `/routes`, `/meeting-station`) | `ko`, `en` | 필수. 데이터에 이 두 언어만 있다. |
| AI 설명 (`/explain`) | ISO 639-1 두 글자 코드 (`en`, `ja`, `vi` …) | 지원 목록은 논의 필요 6 |

---

## 1. GET /stations — 역 목록

**요청**

```
GET /stations?lang=en
```

**응답 200**

```json
{
  "stations": [
    {"id": "101", "name": "Sindorim", "lines": [1, 2]},
    {"id": "102", "name": "Guro", "lines": [1]},
    {"id": "123", "name": "Apgujeong", "lines": [1, 3]}
  ]
}
```

- 실제로는 111개 역 전체를 역 ID 오름차순으로 준다. 위는 3개만 보인 것이다.
- `lines`는 그 역을 지나는 노선 목록(오름차순)이다. 2개 이상이면 환승역이다.
- `lang=ko`이면 `"name": "신도림"`처럼 한국어 이름이 온다.
- 💡 mock 만들기: `data/extra/station_names.csv`(이름)와 `line_stations.csv`(노선)만 있으면 전체 목록을 만들 수 있다.

---

## 2. POST /routes — 경로 계산

**요청**

```json
{
  "start_station_id": "101",
  "end_station_id": "207",
  "criteria": "time",
  "lang": "en",
  "departure_time": "2026-11-04T18:30:00+09:00"
}
```

| 필드 | 필수 | 설명 |
|---|---|---|
| `start_station_id` | O | 출발역 ID |
| `end_station_id` | O | 도착역 ID. 출발역과 같으면 오류 `SAME_STATION` |
| `criteria` | O | `"time"` 최단 시간 / `"transfers"` 최소 환승 |
| `lang` | O | `ko` 또는 `en` |
| `departure_time` | X | 출발 시각. 없으면 서버의 현재 시각 **(가안, 논의 필요 5)** |

최소 환승 경로는 같은 그래프에서 환승에 큰 가중치를 주어 계산한다 (개념설계서 4.2.5).

**응답 200 — 최단 시간 (`criteria: "time"`)**: 신도림 → 1호선 → 압구정 환승 → 3호선 → 교대

```json
{
  "criteria": "time",
  "start": {"id": "101", "name": "Sindorim"},
  "end": {"id": "207", "name": "Seoul Nat'l Univ. of Education"},
  "departure_time": "2026-11-04T18:30:00+09:00",
  "arrival_time": "2026-11-04T19:11:50+09:00",
  "total_sec": 2510,
  "transfer_count": 1,
  "cost_won": 4190,
  "segments": [
    {
      "line": 1,
      "board": {"id": "101", "name": "Sindorim"},
      "alight": {"id": "123", "name": "Apgujeong"},
      "direction": null,
      "stations": [
        {"id": "101", "name": "Sindorim"},
        {"id": "123", "name": "Apgujeong"}
      ],
      "ride_sec": 480
    },
    {
      "line": 3,
      "board": {"id": "123", "name": "Apgujeong"},
      "alight": {"id": "207", "name": "Seoul Nat'l Univ. of Education"},
      "direction": {"id": "207", "name": "Seoul Nat'l Univ. of Education"},
      "stations": [
        {"id": "123", "name": "Apgujeong"},
        {"id": "304", "name": "Sinsa"},
        {"id": "303", "name": "Express Bus Terminal"},
        {"id": "302", "name": "Jamwon"},
        {"id": "301", "name": "Nambu Bus Terminal"},
        {"id": "207", "name": "Seoul Nat'l Univ. of Education"}
      ],
      "ride_sec": 1730
    }
  ],
  "transfers": [
    {"station": {"id": "123", "name": "Apgujeong"}, "from_line": 1, "to_line": 3, "sec": 300}
  ]
}
```

| 필드 | 설명 |
|---|---|
| `segments` | 한 노선을 연속으로 타는 구간 목록. 탄 순서대로 |
| `segments[].board` / `alight` | 그 구간의 탑승역 / 하차역 |
| `segments[].direction` | "○○ 방면"의 ○○에 들어갈 역. 문구는 앱이 언어에 맞게 만든다 (`ko`: "교대 방면", `en`: "toward …"). 예시는 **진행 방향 종점 (가안)**. 순환선(1·6호선)은 아직 `null` **(논의 필요 1)** |
| `segments[].stations` | 그 구간에서 지나는 역 전체. 탑승역과 하차역도 포함 |
| `segments[].ride_sec` | 그 구간의 탑승 시간 (구간 시간의 합) |
| `transfers` | 환승 목록. `sec`은 `transfers.csv` 값 (지금은 모두 300) |
| `transfer_count` | 환승 횟수 (`transfers` 개수와 같음) |
| `total_sec` | 탑승 시간 합 + 환승 시간 합. 예: 480 + 300 + 1730 = 2510 |
| `cost_won` | 지나간 구간 비용의 합 (실제 요금 아님). 환승에는 비용을 더하지 않는다 **(가안, 논의 필요 10)** |
| `arrival_time` | `departure_time` + `total_sec`. 시간표가 없어 기다리는 시간은 넣지 않음 **(가안, 논의 필요 5)** |

**응답 200 — 최소 환승 (`criteria: "transfers"`)**: 같은 출발·도착역. 2호선 하나로 가며 환승이 없다.

```json
{
  "criteria": "transfers",
  "start": {"id": "101", "name": "Sindorim"},
  "end": {"id": "207", "name": "Seoul Nat'l Univ. of Education"},
  "departure_time": "2026-11-04T18:30:00+09:00",
  "arrival_time": "2026-11-04T19:23:20+09:00",
  "total_sec": 3200,
  "transfer_count": 0,
  "cost_won": 2560,
  "segments": [
    {
      "line": 2,
      "board": {"id": "101", "name": "Sindorim"},
      "alight": {"id": "207", "name": "Seoul Nat'l Univ. of Education"},
      "direction": {"id": "217", "name": "Gangbyeon"},
      "stations": [
        {"id": "101", "name": "Sindorim"},
        {"id": "201", "name": "Mullae"},
        {"id": "202", "name": "Konkuk Univ."},
        {"id": "203", "name": "Seongsu"},
        {"id": "204", "name": "Ttukseom"},
        {"id": "205", "name": "Hanyang Univ."},
        {"id": "206", "name": "Seocho"},
        {"id": "207", "name": "Seoul Nat'l Univ. of Education"}
      ],
      "ride_sec": 3200
    }
  ],
  "transfers": []
}
```

💡 mock용 값 하나 더: `107`(종로3가) → `207`(교대)는 두 기준 모두 3호선 하나로 간다. `total_sec` 4060, `transfer_count` 0, `cost_won` 5700, 역 11개.

---

## 3. POST /meeting-station — 모임역 추천

**요청**

```json
{
  "start_station_ids": ["101", "416", "805"],
  "criteria": "time",
  "lang": "en"
}
```

| 필드 | 필수 | 설명 |
|---|---|---|
| `start_station_ids` | O | 사람별 출발역 ID. **2~4개**. 범위 밖이면 오류 `INVALID_PARTICIPANT_COUNT` |
| `criteria` | O | `"time"` 최단시간 / `"transfers"` 최소환승 / `"fairness"` 공평성. 기준별 계산식은 **논의 필요 2** |
| `lang` | O | `ko` 또는 `en` |

**응답 200**

```json
{
  "criteria": "time",
  "station": {"id": "705", "name": "Moran"},
  "participants": [
    {"start": {"id": "101", "name": "Sindorim"}, "travel_sec": 4540, "transfer_count": 2},
    {"start": {"id": "416", "name": "Nowon"}, "travel_sec": 900, "transfer_count": 0},
    {"start": {"id": "805", "name": "Jangji"}, "travel_sec": 810, "transfer_count": 0}
  ],
  "nearby_facilities": []
}
```

| 필드 | 설명 |
|---|---|
| `station` | 추천 모임역 1개 (TOP3 비교는 향후 기능) |
| `participants` | 사람별 결과. **요청한 `start_station_ids` 순서 그대로** |
| `participants[].travel_sec` | 그 사람의 출발역 → 모임역 이동 시간 (환승 시간 포함) |
| `participants[].transfer_count` | 그 사람의 환승 횟수 |
| `nearby_facilities` | 주변 인프라. 지금은 데이터가 없어서 **항상 빈 목록 `[]`**. 항목 형식은 논의 필요 4 |

예시의 사람별 시간은 각자 모란(705)까지 가는 최단 시간 경로로 계산한 실제 값이다. 모란을 고른 것은 "세 사람 이동 시간의 합이 가장 작은 역"으로 해 본 **예시일 뿐**이다. 실제 추천 역은 기준별 계산식이 정해져야 확정된다.

---

## 4. POST /explain — AI 설명

`/routes` 또는 `/meeting-station`의 응답을 그대로 받아서, 요청한 언어로 설명 문장을 돌려준다.

**요청**

```jsonc
{
  "type": "route",          // "route" = /routes 결과, "meeting" = /meeting-station 결과
  "lang": "en",             // 설명 언어
  "result": { /* POST /routes 응답 본문을 그대로 넣는다 (2장 예시) */ }
}
```

**응답 200**

```json
{
  "type": "route",
  "lang": "en",
  "text": "From Sindorim, take Line 1 and get off at Apgujeong (about 8 min). At Apgujeong, transfer to Line 3 (about 5 min) and take the train toward Seoul Nat'l Univ. of Education. Ride 5 stops and get off at Seoul Nat'l Univ. of Education (about 29 min). The whole trip takes about 42 min with 1 transfer.",
  "cached": false
}
```

| 필드 | 설명 |
|---|---|
| `text` | 설명 문장. Gemini가 만들기 때문에 같은 입력이어도 표현이 조금씩 다를 수 있다 |
| `cached` | 저장해 둔 설명을 다시 쓴 경우 `true`. 앱 화면에는 쓰지 않아도 된다 |

`type: "meeting"`이면 `result`에 `/meeting-station` 응답을 넣는다. 응답 형식은 같고, `text`에는 추천 이유가 들어간다.

서버 동작 (AGENTS.md 설계 원칙):
- Gemini에는 `result`에 있는 정보만 넘긴다. 프롬프트에 "주어진 데이터 외의 정보(실제 서울 지하철 노선, 주변 시설 등)는 말하지 말 것"을 넣는다.
- 같은 결과 + 같은 언어의 설명은 저장해 두고 다시 쓴다 (`cached: true`).
- Gemini 호출이 실패하거나 시간이 초과되면 `503 AI_UNAVAILABLE`을 준다. 이때 앱은 경로 화면을 그대로 두고 설명 칸에만 오류를 보여 주면 된다.

---

## 5. 오류 응답

모든 API의 오류는 같은 모양으로 온다.

```json
{
  "error": {
    "code": "STATION_NOT_FOUND",
    "message": "존재하지 않는 역입니다: 999",
    "details": {"station_id": "999"}
  }
}
```

| 필드 | 설명 |
|---|---|
| `code` | 앱이 오류 종류를 구분할 때 쓰는 고정 값 |
| `message` | 개발자가 확인하는 용도의 한국어 문장. **사용자에게는 앱이 `code`를 보고 사용자 언어로 된 문구를 보여 준다** |
| `details` | 추가 정보 (선택). 오류마다 다르다 |

| HTTP | `code` | 언제 | 해당 API | `details` 예 |
|---|---|---|---|---|
| 400 | `STATION_NOT_FOUND` | 없는 역 ID | `/routes`, `/meeting-station` | `{"station_id": "999"}` |
| 400 | `SAME_STATION` | 출발역 = 도착역 | `/routes` | `{"station_id": "101"}` |
| 400 | `INVALID_PARTICIPANT_COUNT` | 출발역이 2개 미만이거나 4개 초과 | `/meeting-station` | `{"count": 5, "min": 2, "max": 4}` |
| 400 | `UNSUPPORTED_LANGUAGE` | 지원하지 않는 `lang` **(가안, 논의 필요 9)** | 전체 | `{"lang": "ja", "supported": ["ko", "en"]}` |
| 404 | `NOT_FOUND` | 없는 주소로 요청 (예: `GET /route`) | 전체 | 없음 |
| 405 | `METHOD_NOT_ALLOWED` | 주소는 있지만 허용하지 않는 방식 (예: `GET /routes`) | 전체 | 없음 |
| 422 | `INVALID_REQUEST` | 필수 값 누락, 타입 오류, `criteria`·`type`의 잘못된 값, JSON 형식 오류 | 전체 | `{"field": "criteria"}` |
| 503 | `AI_UNAVAILABLE` | Gemini 호출 실패·시간 초과 | `/explain` | 없음 |
| 500 | `INTERNAL_ERROR` | 그 밖의 서버 오류 | 전체 | 없음 |

구현 메모 (서버 담당): FastAPI는 입력 검증 오류를 `{"detail": [...]}`, 없는 주소를 `{"detail": "Not Found"}` 모양으로 돌려준다. `backend/app/errors.py`의 오류 처리기가 이것들과 예상 못 한 오류를 모두 위 형식으로 바꾼다. 코드에서 직접 오류를 낼 때는 `AppError(400, "STATION_NOT_FOUND", "...", {"station_id": "999"})`를 쓴다.

---

## 6. 알고리즘 함수 인터페이스 (`backend/app/routing`)

> `backend/app/routing`은 **표혜정 담당 폴더**다. 이 장은 API 쪽에서 필요한 모양을 적은 **제안**이며, 담당자가 확인한 뒤 확정한다.

**역할 나누기**

| 누가 | 하는 일 |
|---|---|
| routing (`find_route`, `find_meeting_station`) | 역 ID와 숫자만 다룬다: 경로, 구간별 시간, 환승, 비용, 방향 역 |
| API 층 (`backend/app`) | 입력 검사(없는 역, 출발=도착, 인원 수, `lang`), 역 이름 붙이기, `arrival_time` 계산, 오류 응답 만들기 |

routing 함수는 **검사를 통과한 입력만 받는다**고 가정한다. 그래서 routing에서는 입력 오류를 따로 처리하지 않아도 된다.

```python
from dataclasses import dataclass
from typing import Literal

StationId = str  # 예: "101". 노선별 노드("123@1")는 routing 안에서만 쓴다.
RouteCriteria = Literal["time", "transfers"]
MeetingCriteria = Literal["time", "transfers", "fairness"]


@dataclass
class Segment:
    line: int                    # 노선 번호
    stations: list[StationId]    # 탑승역 ~ 하차역 (양 끝 포함, 탄 순서대로)
    direction: StationId | None  # "○○ 방면"의 ○○ 역. 순환선은 None (논의 필요 1)
    ride_sec: int                # 이 구간 탑승 시간의 합


@dataclass
class Transfer:
    station: StationId
    from_line: int
    to_line: int
    sec: int                     # transfers.csv의 transfer_sec


@dataclass
class RouteResult:
    segments: list[Segment]
    transfers: list[Transfer]    # 개수 = 환승 횟수
    total_sec: int               # ride_sec 합 + 환승 sec 합
    cost_won: int                # 지나간 구간 비용의 합


def find_route(start: StationId, end: StationId, criteria: RouteCriteria) -> RouteResult:
    ...


@dataclass
class ParticipantResult:
    start: StationId
    travel_sec: int
    transfer_count: int


@dataclass
class MeetingResult:
    station: StationId
    participants: list[ParticipantResult]  # 입력 starts 순서 그대로


def find_meeting_station(starts: list[StationId], criteria: MeetingCriteria) -> MeetingResult:
    ...
```

**함수 결과 → API 응답 연결**

| API 응답 필드 | 어디서 오나 |
|---|---|
| `segments[].board` / `alight` | `Segment.stations[0]` / `Segment.stations[-1]` + 이름 |
| `segments[].direction` | `Segment.direction` + 이름 (`None`이면 `null`) |
| `transfer_count` | `len(RouteResult.transfers)` |
| `arrival_time` | API 층에서 `departure_time + total_sec`로 계산 |
| 모든 `name` | API 층에서 `station_names.csv`의 `lang` 이름으로 붙임 |

예시 확인용: `find_route("101", "207", "time")`은 2장 첫 번째 예시와 같은 값(1호선 480초 → 압구정 환승 300초 → 3호선 1730초, 합계 2510초, 비용 4190)을 돌려줘야 한다.

---

## 7. 논의 필요

ASSUMPTIONS.md에 아직 없는 내용이라 이 문서에서 정하지 않았다. 정해지면 ASSUMPTIONS.md에 적고, 이 목록과 위 **(가안)** 표시를 고친다.

1. **방향 표기** (AGENTS.md 미확정 항목): "○○ 방면"의 ○○에 어떤 역을 넣을지. 예시는 진행 방향 종점(가안)이다. 순환선(1·6호선)은 종점이 없어서 지금은 `null`로 두었다. 다음 역, 주요 역, 내선/외선 중 무엇을 쓸지 정해야 한다.
2. **모임역 기준별 계산식** (AGENTS.md 미확정 항목): `time`·`transfers`·`fairness`가 각각 무엇을 가장 작게 만드는지. 사람별 이동 시간을 최단 시간 경로와 최소 환승 경로 중 무엇으로 잴지, 점수가 같을 때 어떻게 고를지도 함께 정해야 한다.
3. **모임역 입력 예외**: 여러 사람이 같은 출발역을 넣어도 되는지. 출발역 중 하나가 모임역으로 추천되어도 되는지 (그러면 그 사람은 0초).
4. **주변 인프라**: 가상 노선이라 실제 주변 시설 데이터가 없다. Gemini가 지어내서도 안 된다. 데이터를 어디서 가져올지, 항목 형식(이름, 종류 등)을 어떻게 할지 정해야 한다. 정할 때까지는 `[]`.
5. **도착 예정 시각**: 시간표 데이터가 없어 기다리는 시간 없이 `출발 시각 + total_sec`로 계산한다. 이대로 둘지, `departure_time`이 없을 때 서버 현재 시각을 써도 되는지.
6. **`/explain` 지원 언어**: 지원할 언어 목록과 코드 형식 (예: 중국어 간체·번체를 `zh-CN`, `zh-TW`로 나눌지).
7. **`/explain` 역 이름 표기**: 설명 언어가 ko·en이 아닐 때(예: `vi`) 역 이름을 영어 이름 그대로 쓸지, AI가 그 언어로 옮겨 적게 할지. AI가 옮겨 적으면 데이터에 없는 표기를 AI가 만드는 셈이다.
8. **`/explain` 입력 신뢰**: 앱이 보낸 `result`를 서버가 그대로 믿을지, 다시 계산해서 확인할지. 조작된 값으로 Gemini가 호출되는 것(비용 낭비)을 막는 문제와 설명 캐시 키를 정하는 문제가 여기에 걸려 있다.
9. **지원하지 않는 `lang`**: 역 이름 API에 `ja`처럼 없는 언어가 오면 오류로 할지(가안: `UNSUPPORTED_LANGUAGE`), 영어 이름으로 대신 보여 줄지.
10. **환승 비용**: 환승할 때는 비용을 더하지 않았다. transfers.csv에 비용 열이 없고, ASSUMPTIONS.md에는 "구간 비용의 합"이라고만 적혀 있어서 이렇게 해석했다. 이대로 확정할지.
11. **모임역 비용 표시**: 모임역 응답의 사람별 결과에 비용(`cost_won`)도 넣을지. ASSUMPTIONS.md에는 경로 비용만 적혀 있다.
12. **순환선 여부 전달**: 지금 앱은 API로 어떤 노선이 순환선인지 알 수 없고, `direction: null`만 보인다. `GET /stations`에 노선 정보(순환선 여부)를 함께 줄지.
13. **6장 함수 인터페이스**: routing 담당(표혜정) 확인.
