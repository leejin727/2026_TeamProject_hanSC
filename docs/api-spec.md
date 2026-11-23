# SubFit 서버 API 명세 (초안)

> 작성 2026-11-04 · 구현됨: `GET /stations`, `POST /routes` (2026-11-11), `POST /explain`의 `type: "route"` (2026-11-16), `POST /meeting-station` (2026-11-17), `POST /explain`의 `type: "meeting"` (2026-11-17), `GET /stations/{station_id}/facilities` (2026-11-18), `POST /chat` (2026-11-23). 이 문서를 보고 앱에서 가짜 데이터(mock)를 만들 수 있게 하는 것이 목표.
> 데이터 규칙은 `data/extra/ASSUMPTIONS.md`가 우선이다. **(가안)** 표시는 팀 결정 전 임시 값이며, 끝의 [논의 필요](#7-논의-필요)에서 확정한다.
> 예시 값은 모두 실제 데이터(`stations.xlsx` + `data/extra/*.csv`)로 계산한 값이다.

## 0. 공통 사항

| API | 하는 일 | 응답 목표 |
|---|---|---|
| `GET /stations` | 역 목록 | – |
| `POST /routes` | 경로 계산 (최단 시간 / 최소 환승) | 2초 이하 |
| `POST /meeting-station` | 모임역 추천 (2~4명) | – |
| `POST /explain` | 경로·모임역 결과를 AI가 문장으로 설명 | 12초 이하 (2026-11-18, 처음 5초) |
| `GET /stations/{station_id}/facilities` | 역 주변 시설 (AI가 만든 예시, 4-1장) | 처음 12초 이하, 저장된 뒤 즉시 |
| `POST /chat` | 챗봇: 글로 묻고 답하기 (4-2장). Gemini를 부르지 않는다 | 2초 이하 |

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
- 모든 구간은 양방향이고 두 방향의 시간·비용이 같다 (ASSUMPTIONS.md). 예: 207→101 최단 시간 경로는 2장 첫 예시를 거꾸로 탄 경로다. `total_sec` 2510과 `cost_won` 4190은 같고, `direction`만 반대쪽이다 (3호선 구간은 `301` 남부터미널 방면).
- 역 이름은 실제 서울 역명을 빌려 왔지만 위치와 순서는 실제와 관계없는 가상 배치다 (ASSUMPTIONS.md).

**`lang` 값**

| 쓰는 곳 | 허용 값 | 비고 |
|---|---|---|
| 역 이름 (`/stations`, `/routes`, `/meeting-station`) | `ko`, `en` | 필수. 데이터에 이 두 언어만 있다. |
| AI 설명 (`/explain`의 `lang`) | `ko`, `en`, `ja`, `zh-Hans`(중국어 간체), `zh-Hant`(중국어 번체), `vi` | 필수. 설명 문장의 언어 |
| 챗봇 (`/chat`의 `lang`) | 위와 같은 6가지 | 필수. 첫 메시지는 앱의 언어 설정, 그 뒤로는 직전 응답의 `lang`. 답 문구는 `ko`·`en`만 있어서 나머지는 영어로 답한다 (4-2장) |

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
      "direction": {"id": "123", "name": "Apgujeong"},
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
      "direction": {"id": "304", "name": "Sinsa"},
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
| `segments[].direction` | 해당 이동 구간의 다음 역 객체(`stations[1]`). 최초 탑승·환승·순환선에 같은 규칙 적용. 앱은 `ko`: "신사 방면", `en`: "toward Sinsa"로 표시한다. 종착역행이 아니다. |
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
      "direction": {"id": "201", "name": "Mullae"},
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

## 3. POST /meeting-station — 모임역 추천 (2026-11-17 구현)

요청: `{"start_station_ids":["101","101","207"],"criteria":"transfers","lang":"ko"}`

2~4명의 문자열 역 ID를 받으며 중복 출발역과 출발역 자체의 추천을 허용한다.
`time`: 개인별 최단 시간의 합계. `transfers`: 개인별 최소 환승의 합계, 해당 경로의 시간 합계.
`fairness`: 개인별 최단 시간의 최대값, 시간 합계. 마지막 동점은 숫자 역 번호로 결정한다.

응답: `criteria`, `station: {id,name}`, `participants`, `total_travel_sec`, `total_transfer_count`, `max_travel_sec`, `nearby_facilities: []`.
참여자 결과: `start`, `travel_sec`, `transfer_count`, `stations`, `segments`, `transfers`. 순서는 요청한 `start_station_ids` 순서 그대로다.
구간·환승의 내부 형식은 /routes와 같으며 시간 단위는 초다. 요금 필드는 없다.
공통 후보가 없으면 `404 NO_MEETING_STATION`. 나머지 입력 오류는 기존 공통 오류 형식을 따른다.

[전체 설계 및 실행 방법](meeting-algorithm.md) · [실행으로 생성한 응답 예시](meeting-example.json)

---

## 4. POST /explain — AI 설명

`/routes` 또는 `/meeting-station`에 보냈던 **요청 본문**을 받아서, 요청한 언어로 설명 문장을 돌려준다. 앱이 받은 결과는 보내지 않는다. 서버가 같은 요청으로 다시 계산해서 그 값으로 설명한다 (조작된 값으로 Gemini를 부르는 것을 막는다).

**요청**

```jsonc
{
  "type": "route",          // "route" = /routes 요청, "meeting" = /meeting-station 요청
  "request": {              // POST /routes에 보낸 요청 본문 그대로 (2장)
    "start_station_id": "101",
    "end_station_id": "207",
    "criteria": "time",
    "lang": "en"            // 역 이름 언어 (ko·en)
  },
  "lang": "en"              // 설명 문장 언어 (0장 표: ko, en, ja, zh-Hans, zh-Hant, vi)
}
```

**응답 200**

```json
{
  "explanation": "Board Line 1 at Sindorim and ride for 8 minutes to Apgujeong. Transfer to Line 3 at Apgujeong, which takes 5 minutes, and ride for 29 minutes to reach Seoul Nat'l Univ. of Education. The total journey takes 42 minutes with 1 transfer.",
  "cached": false
}
```

| 필드 | 설명 |
|---|---|
| `explanation` | 설명 문장 (3문장 이내). Gemini가 만들기 때문에 같은 입력이어도 표현이 조금씩 다를 수 있다 |
| `cached` | 저장해 둔 설명을 다시 쓴 경우 `true`. 앱 화면에는 쓰지 않아도 된다 |

- 역 이름은 `request.lang`(ko·en)의 이름 그대로 쓴다. 설명 언어가 `ja`, `vi` 등이어도 AI가 역 이름을 옮겨 적지 않는다.
- `type: "meeting"`이면 `request`에 `/meeting-station` 요청 본문을 넣는다. `explanation`에는 추천 이유가 들어간다. 예: `{"type": "meeting", "request": {"start_station_ids": ["101", "416", "805"], "criteria": "time", "lang": "en"}, "lang": "en"}`
- 모임역 설명에는 기준별 고르는 방법(ASSUMPTIONS.md), 참가자별 이동 시간·환승 횟수, 합계·최대 시간만 넘긴다. 다른 역과의 비교, 비용, 주변 시설은 넘기지 않는다. 출발역 순서가 다르면 다른 요청으로 보고 설명을 따로 저장한다.

서버 동작 (AGENTS.md 설계 원칙):
- Gemini에는 서버가 다시 계산한 값(역 이름, 노선, 구간별·전체 시간, 환승 횟수)만 넘긴다. 출발·도착 시각, 비용, 방면은 넘기지 않는다 (방면은 앱이 `direction`으로 따로 보여 준다). 프롬프트에 "주어진 데이터 외의 정보(실제 서울 지하철 노선, 주변 시설 등)는 말하지 말 것"을 넣는다.
- 같은 요청 + 같은 설명 언어의 설명은 `ai_explanations` 표에 저장해 두고 다시 쓴다 (`cached: true`). 저장 키는 `sha256(type + 요청 JSON + lang)`이고, `departure_time`은 키에서 뺀다 (출발 시각만 다른 같은 경로는 설명을 같이 쓴다).
- 모델은 `.env`의 `GEMINI_MODEL` (비우면 `gemini-3.5-flash-lite`). 12초 안에 답이 없으면 끊는다 (처음 5초였으나 Gemini가 느린 때 대부분 실패해서 2026-11-18 변경). 앱은 이보다 조금 더 기다려야 한다 (현재 앱은 15초).
- Gemini 호출이 실패하거나 시간이 초과되면, 또는 서버에 API 키가 없으면 `503 AI_UNAVAILABLE`을 준다. 이때 앱은 경로 화면을 그대로 두고 설명 칸에만 오류를 보여 주면 된다.

**`/explain` 오류**

| 상황 | 응답 |
|---|---|
| `type`이 `route`·`meeting`이 아님, `lang`이 위 6개가 아님 | 400 `VALIDATION_ERROR` `{"field": "type" 또는 "lang", "supported": [...]}` |
| `request` 안의 값이 틀림 (예: `criteria: "fastest"`) | 400 `VALIDATION_ERROR` `{"field": "request.criteria"}` |
| `request`의 역이 없음, `request.lang`이 ko·en이 아님, 모임역 인원 수가 틀림 | `/routes`·`/meeting-station`과 같음 (400 `STATION_NOT_FOUND`, 400 `UNSUPPORTED_LANGUAGE`, 400 `INVALID_PARTICIPANT_COUNT`) |
| `type`, `request`, `lang` 중 빠진 값 | 422 `INVALID_REQUEST` |

---

## 4-1. GET /stations/{station_id}/facilities — 주변 시설 (AI 예시)

> 2026-11-18 추가. 가상 노선이라 실제 시설 데이터가 없어서, **실제 역 이름을 바탕으로 Gemini가 만든 예시**를 준다. 실제와 다를 수 있다 (ASSUMPTIONS.md "주변 시설"). 앱은 이 사실을 화면에 함께 보여 준다.

**요청**

```
GET /stations/705/facilities?lang=ko
```

`lang`은 필수: `ko`, `en`, `ja`, `zh-Hans`, `zh-Hant`, `vi` (시설 이름·위치 안내 언어). `/meeting-station`의 `nearby_facilities`는 계속 `[]`이고, 앱은 추천역을 받은 뒤 이 API를 따로 부른다 (모임역 계산은 빠르게 두고 AI는 따로).

**응답 200**

```json
{
  "station": {"id": "705", "name": "모란"},
  "facilities": [
    {"category": "cafe", "name": "모란커피", "detail": "2번 출구 · 도보 2분"},
    {"category": "restaurant", "name": "모란시장할매순대국", "detail": "4번 출구 · 도보 5분"},
    {"category": "convenience_store", "name": "CU 모란역점", "detail": "1번 출구 · 도보 1분"},
    {"category": "pharmacy", "name": "온누리약국", "detail": "3번 출구 · 도보 3분"},
    {"category": "restroom", "name": "역 안 공중화장실", "detail": "지하 1층 · 대합실 내"}
  ],
  "ai_generated": true,
  "cached": false
}
```

| 필드 | 설명 |
|---|---|
| `station` | 역 객체. `lang`이 `ko`면 한국어 이름, 그 밖에는 영어 이름 |
| `facilities[].category` | `cafe`, `restaurant`, `convenience_store`, `pharmacy`, `restroom` 중 하나. 항상 이 순서, 종류마다 최대 1개. 앱은 이 값으로 아이콘·종류 이름을 정한다 |
| `facilities[].name` / `detail` | 시설 이름 / 위치 안내 (`lang` 언어). AI가 만든 예시 |
| `ai_generated` | 항상 `true`. AI가 만든 예시라는 표시 |
| `cached` | 저장해 둔 예시를 다시 쓴 경우 `true`. 같은 역 + 같은 `lang`은 처음 한 번만 만든다 |

**오류:** 없는 역 → 400 `STATION_NOT_FOUND`, `lang`이 위 6개가 아님 → 400 `VALIDATION_ERROR`, `lang` 없음 → 422 `INVALID_REQUEST`, Gemini 실패·시간 초과·시설용 키(`GEMINI_FACILITY_API_KEY`) 없음·답 모양이 틀림 → 503 `AI_UNAVAILABLE` (저장하지 않으므로 다시 요청하면 새로 만든다).

---

## 4-2. POST /chat — 챗봇

> 2026-11-23 추가. 글로 묻고 답한다. **Gemini를 부르지 않는다.** 무엇을 묻는지는 직접 만든 작은 모델이 고르고, 경로는 `/routes`와 같은 계산을 쓰고, 답 문장은 미리 써 둔 문구(`data/chat/replies.json`)다. 모델과 역 이름 찾기는 `docs/chatbot.md`에 설명이 있다.

**요청**

```json
{"message": "신도림에서 강남까지 어떻게 가?", "lang": "ko", "context": null}
```

| 필드 | 설명 |
|---|---|
| `message` | 필수. 사용자가 쓴 글. 앞뒤 빈칸을 뗀 뒤 1~300자 |
| `lang` | 필수. `ko`, `en`, `ja`, `zh-Hans`, `zh-Hant`, `vi` 중 하나. 답은 **사용자가 쓴 언어**(한국어·영어)로 한다. 역 이름만 보냈을 때처럼 쓴 언어를 알 수 없으면 이 값을 따르고, 이 값이 `ko`·`en`이 아니면 영어로 답한다. 그래서 앱은 **첫 메시지에는 앱의 언어 설정을, 그 뒤로는 직전 응답의 `lang`을** 넣는다 (아래 "대화 언어") |
| `context` | 선택. **직전 응답의 `context`를 그대로** 넣는다. 첫 메시지이거나 대화를 새로 시작할 때는 빼거나 `null` |

**응답 200**

```json
{
  "intent": "route",
  "topic": "result",
  "lang": "ko",
  "text": "신도림 → 강남 · 51분 · 환승 2회 (최단 시간)",
  "route": {"criteria": "time", "start": {"id": "101", "name": "신도림"}, "end": {"id": "208", "name": "강남"},
            "total_sec": 3060, "transfer_count": 2, "cost_won": 4620, "…": "나머지 필드는 2장 응답과 같다"},
  "phrases": [],
  "options": [],
  "context": {"start": "101", "end": "208", "criteria": "time", "asked": null}
}
```

| 필드 | 설명 |
|---|---|
| `intent` | 답의 종류: `route`, `faq`, `phrase`, `help`, `emergency`, `out_of_scope`, `greet`, `thanks` |
| `topic` | 세부 종류 (아래 표). 앱은 이 값을 몰라도 화면을 그릴 수 있다 |
| `lang` | 답한 언어. `ko` 또는 `en` |
| `text` | 사용자에게 보여 줄 답. 줄바꿈(`\n`)이 들어 있을 수 있다 |
| `route` | 경로를 찾았을 때(`topic: "result"`)만 있고, 아니면 `null`. **2장 `POST /routes` 응답과 같은 모양**이다 |
| `phrases` | 역무원에게 보여 줄 한국어 문장 카드. 없으면 `[]`. 각각 `{"id", "korean", "meaning"}`이고, `meaning`은 영어로 답할 때만 뜻이 들어가며 한국어로 답할 때는 `null` |
| `options` | 어느 역인지 골라야 할 때(`topic: "choose_station"`)의 역 객체 목록. 없으면 `[]`. 사용자가 하나를 고르면 앱은 그 역 이름을 `message`로 보내면 된다 |
| `context` | 다음 요청에 그대로 돌려보낼 값. 앱은 안을 들여다볼 필요가 없다 |

| `intent` | `topic` | 뜻 |
|---|---|---|
| `route` | `result` | 경로를 찾았다 (`route` 있음) |
| | `ask_start`, `ask_end`, `ask_both` | 출발역 / 도착역 / 둘 다를 되묻는다 |
| | `choose_station` | 말한 이름에 맞는 역이 여럿이다 (`options` 있음) |
| | `same_station` | 출발역과 도착역이 같아서 도착역을 되묻는다 |
| | `no_route` | 두 역을 잇는 경로가 없다. 지금 데이터에서는 나지 않는다 |
| `faq` | `ticket`, `gate`, `transfer_ticket`, `direction_sign`, `announcement`, `last_train`, `lost_item`, `help_desk` | 이용 안내. `last_train`은 "첫차·막차 정보가 없다"고 답한다 |
| `phrase` | `list` / `which_side`, `transfer_where`, `buy_ticket_help`, `lost_item`, `feel_sick`, `no_korean` | 문장 카드 전체 / 하나 |
| `help` | `lost` | 길을 잃었을 때 안내 |
| `emergency` | `feel_sick`, `lost_item` | 아플 때(119) / 도난(112) 안내와 문장 카드 |
| `out_of_scope` | `realtime`, `real_seoul`, `unrelated`, `abuse`, `station_facility` | 답하지 않는 주제라는 안내 |
| | `not_understood` | 이해하지 못했다 (모델의 확신이 낮음) |
| | `unsupported_language` | 한국어·영어가 아닌 언어로 물었다. 모델이 이 언어들을 믿을 수 없게 판단해서, 의도와 상관없이 "한국어나 영어로 물어봐 주세요"라고 답한다 |
| `greet` / `thanks` | `hello` / `welcome` | 인사 / 감사 인사에 대한 답 |

**`context`와 이어 묻기**

서버는 대화를 기억하지 않는다. 메시지 내용을 저장하지 않고 로그에도 남기지 않는다. 이어 묻기에 필요한 값은 `context`에 담겨 오가며, 앱은 마지막 응답의 `context`만 들고 있으면 된다.

| 필드 | 설명 |
|---|---|
| `start`, `end` | 직전 길찾기의 출발·도착역 ID, 또는 지금까지 들은 역. 없으면 `null` |
| `criteria` | `time` 또는 `transfers`. 없으면 `null` |
| `asked` | 직전 답에서 되물은 역: `start`, `end`, 없으면 `null`. 다음 메시지가 역 이름뿐이면 이 자리에 넣는다 |

| 순서 | `message` | 답 (`topic`) | 응답의 `context` |
|---|---|---|---|
| 1 | 신도림에서 강남까지 어떻게 가? | 신도림 → 강남 · 51분 · 환승 2회 (`result`) | `{"start": "101", "end": "208", "criteria": "time", "asked": null}` |
| 2 | 그럼 환승 없이는? | 신도림 → 강남 · 58분 · 환승 0회 (`result`) | `criteria`가 `"transfers"`로 바뀜 |
| 3 | 반대로는? | 강남 → 신도림 · 58분 · 환승 0회 (`result`) | `start`와 `end`가 바뀜 |
| 새 대화 1 | 강남 가는 법 | 강남까지 가는 길을 찾을게요. 어디에서 출발하나요? (`ask_start`) | `{"start": null, "end": "208", "criteria": "time", "asked": "start"}` |
| 새 대화 2 | 신도림 | 신도림 → 강남 · 51분 · 환승 2회 (`result`) | `asked`가 `null`로 돌아감 |

- "그럼 …는?", "반대로는?" 같은 이어 묻는 말이거나 직전에 역을 되물었을 때만 `context`의 역·기준을 가져온다. 새 질문("잠실 가는 법")은 앞 대화의 출발역을 쓰지 않고 다시 묻는다.
- 역을 하나만 말하고 출발인지 도착인지 알 수 없으면 도착역으로 본다.
- 오타·줄임말인데 맞는 역이 하나면 그 역으로 답하고, `text` 첫 줄에 `‘신도릠’ → 신도림 (이 역으로 이해했어요)`를 덧붙인다 (팀 결정 2026-11-23). 여럿이면 `choose_station`.
- 길찾기가 아닌 답(`faq`, `greet` 등)은 `context`를 바꾸지 않고 그대로 돌려준다.
- **대화 언어:** 앱 언어가 한국어인데 영어로 물으면 답은 영어로 온다. 이어서 역 이름만 보내면("Sindorim", 역 선택 버튼) 서버는 쓴 언어를 알 수 없어 요청의 `lang`으로 답한다. 이때 앱의 언어 설정(`ko`)을 보내면 답이 한국어로 바뀌므로, 앱은 직전 응답의 `lang`(`en`)을 보낸다. 대화를 새로 시작하면 다시 앱의 언어 설정을 보낸다 (2026-11-23, 실제 서버로 확인).

**오류:** `message`가 비었거나 300자 초과, `lang`·`message` 없음, `context.criteria`·`context.asked` 값이 틀림 → 422 `INVALID_REQUEST`. `lang`이 위 6개가 아님 → 400 `VALIDATION_ERROR`. `context`의 역 ID가 없는 역 → 400 `STATION_NOT_FOUND`. 모델 실행기를 쓸 수 없음 → 503 `CHAT_UNAVAILABLE` (이때도 다른 API는 정상이다).

**한계:** "네"·"아니요"는 알아듣지 못한다 (그래서 예/아니요로 답할 질문은 하지 않는다). "사당 말고 이수로 바꿔줘"는 사당 → 이수 경로로 계산된다. 그 밖의 한계는 `docs/chatbot.md` 8장.

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
| 400 | `STATION_NOT_FOUND` | 없는 역 ID | `/routes`, `/meeting-station`, `/explain`, `/stations/{id}/facilities`, `/chat`(`context`의 역) | `{"station_id": "999"}` |
| 400 | `SAME_STATION` | 출발역 = 도착역 | `/routes` | `{"station_id": "101"}` |
| 400 | `INVALID_PARTICIPANT_COUNT` | 출발역이 2개 미만이거나 4개 초과 | `/meeting-station`, `/explain` | `{"count": 5, "min": 2, "max": 4}` |
| 400 | `UNSUPPORTED_LANGUAGE` | 역 이름 `lang`이 ko·en이 아님 **(가안, 논의 필요 9)** | 전체 (`/explain`은 `request.lang`) | `{"lang": "ja", "supported": ["ko", "en"]}` |
| 400 | `VALIDATION_ERROR` | `/explain`의 `type`·`lang`·`request` 값이 틀림 (4장), 주변 시설·챗봇의 `lang`이 틀림 (4-1·4-2장) | `/explain`, `/stations/{id}/facilities`, `/chat` | `{"field": "lang", "supported": [...]}` |
| 404 | `NOT_FOUND` | 없는 주소로 요청 (예: `GET /route`) | 전체 | 없음 |
| 404 | `NO_ROUTE` | 두 역을 잇는 경로가 없음. 지금 데이터는 모든 역이 이어져 있어 나지 않는다 | `/routes` | `{"start_station_id": "101", "end_station_id": "207"}` |
| 404 | `NO_MEETING_STATION` | 모든 참여자가 갈 수 있는 역이 없음. 지금 데이터에서는 나지 않는다 | `/meeting-station`, `/explain` | 없음 |
| 405 | `METHOD_NOT_ALLOWED` | 주소는 있지만 허용하지 않는 방식 (예: `GET /routes`) | 전체 | 없음 |
| 422 | `INVALID_REQUEST` | 필수 값 누락, 타입 오류(예: 숫자 역 ID), `criteria`의 잘못된 값, JSON 형식 오류 | 전체 | `{"field": "criteria"}` |
| 503 | `AI_UNAVAILABLE` | Gemini 호출 실패·시간 초과·과부하, 서버에 API 키 없음, 주변 시설 답 모양이 틀림 | `/explain`, `/stations/{id}/facilities` | 없음 |
| 503 | `CHAT_UNAVAILABLE` | 챗봇 모델 실행기를 쓸 수 없음 (그 컴퓨터용 실행기가 없거나 안 돌아감, `docs/chatbot.md` 7장) | `/chat` | 없음 |
| 500 | `INTERNAL_ERROR` | 그 밖의 서버 오류 | 전체 | 없음 |

구현 메모 (서버 담당): FastAPI는 입력 검증 오류를 `{"detail": [...]}`, 없는 주소를 `{"detail": "Not Found"}` 모양으로 돌려준다. `backend/app/errors.py`의 오류 처리기가 이것들과 예상 못 한 오류를 모두 위 형식으로 바꾼다. 코드에서 직접 오류를 낼 때는 `AppError(400, "STATION_NOT_FOUND", "...", {"station_id": "999"})`를 쓴다.

---

## 6. 알고리즘 함수 인터페이스 (`backend/app/routing`)

> `backend/app/routing`은 **표혜정 담당 폴더**다. 이 장의 모양은 표혜정·이진이 합의했다 (2026-11-05). 바꿀 때는 두 사람이 같이 정한다.
>
> 구현 위치: 결과 모양 `routing/models.py`, 노선도 읽기 `routing/graph_builder.py`(`load_network`), 경로 계산 `routing/dijkstra.py`(`find_route`), 모임역 계산 `routing/meeting.py`(`find_meeting_station`, 설계: [meeting-algorithm.md](meeting-algorithm.md))

**역할 나누기**

| 누가 | 하는 일 |
|---|---|
| routing (`find_route`, `find_meeting_station`) | 역 ID와 숫자만 다룬다: 경로, 구간별 시간, 환승, 비용, 방향 역 (각 이동 구간의 다음 역) |
| API 층 (`backend/app`) | 입력 검사(없는 역, 출발=도착, 인원 수, `lang`), 역 이름 붙이기, `arrival_time` 계산, 오류 응답 만들기 |

routing 함수는 **검사를 통과한 입력만 받는다**고 가정한다. 입력 오류는 API 층이 먼저 막고, routing이 내는 오류는 안전장치다.

| 상황 | routing 동작 |
|---|---|
| 없는 역 ID, 문자열이 아닌 역 ID (예: 숫자 `101`) | `UnknownStationError` |
| `criteria`가 `"time"`·`"transfers"`가 아님 | `ValueError` |
| 출발역 = 도착역 | 오류 없이 빈 결과 (`segments=[]`, `total_sec=0`, `cost_won=0`). API 층은 그 전에 `SAME_STATION`으로 막는다 |
| 경로 없음 | `NoRouteError`. 지금 데이터는 모든 역이 이어져 있어 나지 않는다 |

```python
from dataclasses import dataclass
from typing import Literal

StationId = str  # 예: "101". 역 번호는 이름표라 문자열로 다룬다
RouteCriteria = Literal["time", "transfers"]
MeetingCriteria = Literal["time", "transfers", "fairness"]

# 노선도는 서버를 켤 때 한 번 읽어 두고 모든 요청에서 같이 쓴다.
# 그래프 노드는 (역, 노선) 튜플(예: ("123", 1))이며 routing 안에서만 쓴다.
network = load_network(DATA_DIR)  # DATA_DIR = 저장소 최상위 data/ 폴더 (raw/stations.xlsx + extra/*.csv)


@dataclass
class Segment:
    line: int                    # 노선 번호
    stations: list[StationId]    # 탑승역 ~ 하차역 (양 끝 포함, 탄 순서대로)
    direction: StationId | None  # 탑승 직후 다음 역 ID
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
    cost_won: int                # 지나간 구간 비용의 합. 환승은 0원 (논의 필요 10)


def find_route(network: Network, start: StationId, end: StationId, criteria: RouteCriteria) -> RouteResult:
    ...


@dataclass
class ParticipantResult:
    start: StationId
    travel_sec: int
    transfer_count: int
    stations: list[StationId]
    segments: list[Segment]
    transfers: list[Transfer]


@dataclass
class MeetingResult:
    criteria: MeetingCriteria
    station: StationId
    station_names: tuple[str, str]
    total_travel_sec: int
    total_transfer_count: int
    max_travel_sec: int
    participants: list[ParticipantResult]  # 입력 starts 순서 그대로


def find_meeting_station(network: Network, starts: list[StationId], criteria: MeetingCriteria) -> MeetingResult:
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

예시 확인용: `find_route(network, "101", "207", "time")`은 2장 첫 번째 예시와 같은 값(1호선 480초 → 압구정 환승 300초 → 3호선 1730초, 합계 2510초, 비용 4190)을 돌려줘야 한다. 이 값과 2장의 다른 예시들은 `backend/tests/test_dijkstra.py`의 `SpecExampleTests`가 확인한다.

---

## 7. 논의 필요

ASSUMPTIONS.md에 아직 없는 내용이라 이 문서에서 정하지 않았다. 정해지면 ASSUMPTIONS.md에 적고, 이 목록과 위 **(가안)** 표시를 고친다. 다른 장에서 "논의 필요 N"으로 번호를 가리키므로, 확정된 항목도 지우지 않고 줄을 그어 번호를 유지한다.

1. ~~**방향 표기**~~ → 확정 (2026-11-17). 각 이동 구간의 다음 역을 방면으로 사용한다. 순환선도 동일하다 (ASSUMPTIONS.md "방면 안내 확정 사항").
2. ~~**모임역 기준별 계산식**~~ → 확정 (2026-11-17). ASSUMPTIONS.md "모임역 추천 확정 사항".
3. ~~**모임역 입력 예외**~~ → 확정 (2026-11-17). 같은 출발역 중복 허용, 출발역이 모임역이 되어도 됨 (그 사람은 0초).
4. ~~**주변 인프라**~~ → 확정 (2026-11-18). 실제 데이터 대신 역 이름을 바탕으로 Gemini가 만든 예시를 쓴다 (4-1장, ASSUMPTIONS.md "주변 시설"). `/meeting-station`의 `nearby_facilities`는 계속 `[]`.
5. **도착 예정 시각**: 시간표 데이터가 없어 기다리는 시간 없이 `출발 시각 + total_sec`로 계산한다. 이대로 둘지, `departure_time`이 없을 때 서버 현재 시각을 써도 되는지.
6. ~~**`/explain` 지원 언어**~~ → 확정 (2026-11-16). `ko`, `en`, `ja`, `zh-Hans`, `zh-Hant`, `vi` (0장, 4장).
7. **`/explain` 역 이름 표기**: 설명 언어가 ko·en이 아닐 때(예: `vi`) 역 이름을 영어 이름 그대로 쓸지, AI가 그 언어로 옮겨 적게 할지. AI가 옮겨 적으면 데이터에 없는 표기를 AI가 만드는 셈이다. 지금 구현은 `request.lang`의 이름을 그대로 쓴다 (옮겨 적지 않음).
8. ~~**`/explain` 입력 신뢰**~~ → 확정 (2026-11-16). 앱은 결과 대신 요청을 보내고 서버가 다시 계산한다. 캐시 키도 요청으로 만든다 (4장).
9. **지원하지 않는 `lang`**: 역 이름 API에 `ja`처럼 없는 언어가 오면 오류로 할지(가안: `UNSUPPORTED_LANGUAGE`), 영어 이름으로 대신 보여 줄지.
10. **환승 비용**: 환승할 때는 비용을 더하지 않았다. transfers.csv에 비용 열이 없고, ASSUMPTIONS.md에는 "구간 비용의 합"이라고만 적혀 있어서 이렇게 해석했다. 이대로 확정할지.
11. ~~**모임역 비용 표시**~~ → 확정 (2026-11-17). 모임역 응답에는 비용을 넣지 않는다 (ASSUMPTIONS.md).
12. **순환선 여부 전달**: 다음 역 방면은 순환선에도 제공한다. 별도의 순환선 표시용 메타데이터 전달은 추후 결정한다.
