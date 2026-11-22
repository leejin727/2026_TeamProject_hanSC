# 챗봇 (나노 의도 판단 모델)

> 2026-11-23 · **1단계까지 됨**: 모델을 서버에 넣었고, 메시지 하나를 이해한 결과(`Answer`)까지 나온다.
> 답 만들기와 `POST /chat`(2단계), 앱 화면(3단계)은 아직 없다. 팀 결정은 `data/extra/ASSUMPTIONS.md`의 "챗봇"이 우선이다.

## 1. 한눈에

```
사용자 메시지 "신도릠에서 교대까지 빨리 가는 길"
  ① 규칙 (nano/rules.py + stations.py)   문장에서 역을 찾고 출발·도착을 나눈다 → "◆에서 ◆까지 ㉑빨리 ㉔가는 길"
  ② 나노 모델 (C++ 실행기)                 무엇을 묻는지 고른다 → 길찾기, 기준 time
  ③ Answer                                 intent=route, start="신도릠", end="교대", criteria="time"
  (2단계) 답 만들기                         길찾기는 기존 경로 계산, 나머지는 미리 써 둔 문구
```

- Gemini 같은 외부 AI를 부르지 않는다. 모델은 답 문장을 만들지 않고, 무엇을 묻는지만 고른다.
- 모델은 역 이름을 외우지 않는다. 규칙이 역 자리를 `◆`로 바꿔서 넣기 때문에, 역이 바뀌어도 모델은 그대로 쓴다.
- 문장 하나에 1ms 남짓 걸린다 (처음 한 번은 실행기를 띄우느라 10~25ms).

## 2. 파일

| 위치 | 내용 |
|---|---|
| `backend/app/chat/nano/` | 받은 그대로 두는 폴더 (v5, 2026-11-19). **안의 파일은 고치지 않는다.** 새 판을 받으면 폴더째 바꾼다 |
| ├ `__init__.py` | 서버가 부르는 입구 `understand()`, 결과 모양 `Answer`, 실행기 띄우기 |
| ├ `rules.py` | 규칙: 역 찾기, 출발·도착 나누기, 언어 고르기, 개인정보 가리기, 힌트 표시(①~㉕) |
| ├ `subfit_nano.bin` | 모델 (828KB) |
| ├ `subfit_nano.cpp` | 실행기 소스 (C++, 외부 라이브러리 없음) |
| ├ `bin/` | 미리 빌드한 실행기 5종 (맥 M·인텔, 리눅스 x86·ARM, 윈도우) |
| └ `en_confusables.txt` | 역 이름과 헷갈리는 영어 낱말 |
| `backend/app/chat/stations.py` | 역 이름 찾기 (우리가 쓴 것, 5장) |
| `backend/app/chat/ko_confusables.txt` | 역 이름과 헷갈리는 흔한 한국어 말 253개 |
| `backend/app/chat/settings.py` | 기준값: 확신 0.8 미만이면 되묻기, 실행기 시간 제한 2초 |
| `backend/tests/test_chat_nano.py` | 테스트 |

학습 원본(`SF5_d128L4.pt`)과 학습 코드는 저장소에 없다. 그래서 여기서 모델을 다시 학습할 수는 없다.

## 3. 써 보기

`backend/` 폴더에서 `python`을 켜고:

```python
from app.chat import nano, stations
from app.config import DATA_DIR
from app.routing.graph_builder import load_network

network = load_network(DATA_DIR)
answer = nano.understand(network, "신도릠에서 교대까지 빨리 가는 길")
print(answer.intent, answer.start.written, answer.end.written, answer.criteria)
# route 신도릠 교대 time

print(stations.find(network, "신도릠"))  # Found(station_id=None, candidates=['101'])  ← 오타라서 후보
print(stations.find(network, "교대"))    # Found(station_id='207', candidates=[])     ← 이름이 정확히 같음
```

실행기만 따로 시험하려면 (맥 M 기준. 규칙을 거친 문장을 넣어야 한다):

```bash
cd backend/app/chat/nano
echo "◆에서 ◆까지 ㉔어떻게 가?" | bin/subfit_nano-macos-aarch64 subfit_nano.bin
# route	0.8912	none	0.9921	new	0.9924      ← 의도·확신, 기준·확신, 흐름·확신
```

## 4. 모델이 고르는 것

모델은 세 가지를 고른다: 의도(26가지), 기준(`none`·`time`·`transfers`), 흐름(`new`·`follow`·`reverse`).
아래 "뜻"은 라벨 이름과 `rules.py`의 낱말 묶음을 보고 우리가 적은 것이다 (모델과 함께 받은 설명에는 라벨 이름만 있다).

| 모델 라벨 | 뜻 | `Answer` |
|---|---|---|
| `route` | 길찾기 | `intent="route"` + `start`·`end`·`criteria`·`follow_up`·`reverse` |
| `faq_ticket` `faq_gate` `faq_transfer_ticket` `faq_direction_sign` `faq_announcement` `faq_last_train` `faq_lost_item` `faq_help_desk` | 이용 안내: 표·교통카드, 개찰구, 환승할 때 표, 방면 표지판, 안내방송, 막차·첫차, 분실물, 안내센터 | `intent="faq"`, `faq_id="ticket"` 등 |
| `phrase_list` | 쓸 수 있는 한국어 문장 목록 | `intent="phrase"` |
| `phrase_which_side` `phrase_transfer_where` `phrase_buy_ticket_help` `phrase_lost_item` `phrase_feel_sick` `phrase_no_korean` | 역무원에게 보여 줄 한국어 문장 하나 | `intent="phrase"`, `phrase_id="which_side"` 등 |
| `help_lost` | 길을 잃음 | `intent="help"` |
| `emergency_sick` `emergency_theft` | 아픔, 도난 | `intent="emergency"`, `phrase_id="feel_sick"` 또는 `"lost_item"` |
| `oos_realtime` `oos_real_seoul` `oos_unrelated` `oos_abuse` `oos_station_facility` | 답하지 않는 것: 실시간 정보, 실제 서울, 관계없는 말, 욕설, 역 안 시설 | `intent="out_of_scope"`, `kind="realtime"` 등 |
| `greet` `thanks` | 인사, 감사 | `intent="greet"` / `"thanks"` |
| (확신이 0.8 미만) | 이해하지 못함 | `intent="out_of_scope"`, `kind="not_understood"` |

- `follow_up=True`는 "그럼 환승 없이는?"처럼 앞 대화를 이어 묻는 것, `reverse=True`는 "반대로는?"이다. 이때 역은 앞 대화에서 가져와야 한다.
- `start`·`end`에는 사용자가 **쓴 글자**만 들어 있다 (`answer.start.written`). 어느 역인지는 `stations.find()`로 다시 찾는다.
- `lang`은 사용자가 쓴 언어다: `ko` `en` `ja` `zh-Hans` `zh-Hant` `vi` `other`, 역 이름·숫자뿐이면 `None`.

## 5. 역 이름 찾기 (`stations.py`)

모델과 함께 받은 폴더에는 이 부분이 없어서 우리가 새로 썼다. `rules.py`가 부르는 함수 이름과 모양에 맞췄다.

| 사용자가 쓴 것 | 결과 | 까닭 |
|---|---|---|
| `신도림` `신도림역` `Sindorim` `Jongno 3-ga` `Konkuk University` | 그 역 (`station_id`) | 데이터의 이름과 같다 |
| `고터` `건대` `종로오가` `서울교대` | 후보 (`candidates`) | 줄임말 (`ALIASES`) |
| `Gyodae` `konkuk` | 후보 | 소리 나는 대로 적은 영어, 영어 이름 속 낱말 하나 |
| `신도릠` `교댸` `sindolim` | 후보 | 오타 |
| `종로` | 후보 2개 (종로3가, 종로5가) | 이름의 앞부분 |
| `성수기` `몰라` `잠시` `식당` | 역 아님 | 아래 세 가지 |

후보는 바로 정하지 않고 사용자에게 "○○역이 맞나요?"라고 되묻는 데 쓴다 (2단계).

비슷한 정도는 파이썬 `difflib`의 ratio로 잰다 (한국어는 자모로 풀어서). 그런데 ratio만 보면 흔한 말이 역으로 잡혀서, 다음은 오타로 보지 않는다.

1. `ko_confusables.txt`에 있는 흔한 말: "잠시만요" ≠ 잠실, "식당에" ≠ 신당
2. 역 이름에 글자가 더 붙은 한국어 낱말: "성수기" ≠ 성수, "옥수수" ≠ 옥수
3. 이름 길이에 비해 너무 많이 다른 말: "몰라" ≠ 모란

고칠 일이 생기면:
- 줄임말을 더하려면 `stations.py`의 `ALIASES`에 적는다.
- 어떤 말이 자꾸 역으로 잡히면 `ko_confusables.txt`에 한 줄 더한다.

## 6. 실행기

서버는 컴퓨터 종류에 맞는 실행기를 `nano/bin/`에서 골라 한 번 띄워 두고 계속 쓴다.

| 파일 | 컴퓨터 | 확인 (2026-11-23) |
|---|---|---|
| `subfit_nano-macos-aarch64` | 맥 (M 칩) | 됨. 소스로 직접 빌드한 것과 답이 같음 |
| `subfit_nano-macos-x86_64` | 맥 (인텔) | 로제타로 실행해 봄 |
| `subfit_nano-linux-x86_64` | 리눅스 | 이 컴퓨터에서는 못 함. GitHub 자동 검사가 리눅스에서 돌 때 확인됨 |
| `subfit_nano-linux-aarch64` | 리눅스 (ARM) | 확인 못 함 |
| `subfit_nano-windows-x86_64.exe` | 윈도우 | 확인 못 함 |

- 실행기를 못 쓰면 `understand()`가 `NanoUnavailable` 오류를 낸다. 챗봇만 안 되고 길찾기·모임역 등 나머지는 그대로 된다.
- `pytest` 결과에 `skipped`가 보이면 그 컴퓨터에서 실행기가 안 된 것이다 (`pytest -rs`로 까닭을 볼 수 있다).
- 실행기가 안 되는 컴퓨터에서는 소스로 빌드해서 쓸 수 있다.

```bash
cd backend/app/chat/nano
g++ -O2 -std=c++17 -o subfit_nano subfit_nano.cpp      # 윈도우: g++ -O2 -std=c++17 -static -o subfit_nano.exe subfit_nano.cpp
```

그다음 `.env`에 `SUBFIT_NANO_BIN=빌드한 파일의 전체 경로`를 적는다. 빌드한 파일은 커밋하지 않는다.

## 7. 확인한 것과 한계 (2026-11-23)

**확인한 것**
- 직접 만든 한국어·영어 문장 127개 중 123개(96.9%)의 의도를 맞게 골랐다. 우리가 지어낸 문장이라 참고용이다.
- 모델과 함께 받은 안내문에는 "처음 보는 사람 말투 320문장에서 전체 정답 90.6%, 의도 93.8%"라고 적혀 있다. 그 문장들은 받지 못해서 다시 확인하지 못했다.
- 영어 사전 낱말 21만 개 중 역으로 잘못 잡히는 것은 26개(드문 낱말), 자주 쓰는 한국어 말 5만 개 중에는 3개다.

**한계**
- **한국어·영어만 믿을 수 있다.** 일본어 "切符はどこで買えますか"(표는 어디서 사나요)를 길찾기로 고르고 확신도 0.97이다. 확신 기준으로는 걸러지지 않으므로, 2단계에서 `lang`을 보고 걸러야 한다.
- **역 이름과 똑같은 낱말은 역으로 잡힌다.** "동작이 안 돼요" → 동작역, "미아가 됐어요" → 미아역, "약수 마시고 싶어" → 약수역. `rules.py`의 동작이다.
- **목록에 없는 드문 말은 여전히 오타 후보로 잡힐 수 있다.** 후보는 되묻는 용도라 틀린 답이 바로 나가지는 않는다.
- **역 찾기는 모델을 만든 쪽의 것과 다를 수 있다.** 원래 코드가 없어 새로 썼기 때문이다. 받은 정답률이 그대로 나온다고 보장할 수 없다.
- 확신 기준 0.8은 우리가 정한 값이다 (`settings.py`에 근거).

## 8. 다음 단계

- **2단계**: 답 만들기(`service.py`), 고정 문구(`data/chat/`, 한국어·영어), `POST /chat`. 이어 묻기는 앱이 직전 출발·도착역을 함께 보내는 방식으로 하고, 대화 내용은 서버에 남기지 않는다.
- **3단계**: 앱의 챗봇 화면 (`app/`, 표혜정 담당 폴더).
