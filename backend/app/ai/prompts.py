"""Gemini에 보내는 프롬프트. 경로 설명(type=route), 모임역 설명(type=meeting), 주변 시설 예시.

설계 원칙(AGENTS.md): 계산은 알고리즘, 설명은 AI.
경로·모임역 설명에는 서버가 계산한 값만 넘기고, 데이터에 없는 사실은 말하지 못하게 한다.
주변 시설만 예외로, 역 이름을 바탕으로 AI가 예시를 만든다 (맨 아래).
"""

import json

# 설명 언어 코드 → 프롬프트에 쓸 언어 이름
LANGUAGES = {
    "ko": "한국어 (Korean)",
    "en": "English",
    "ja": "日本語 (Japanese)",
    "zh-Hans": "简体中文 (Simplified Chinese)",
    "zh-Hant": "繁體中文 (Traditional Chinese)",
    "vi": "Tiếng Việt (Vietnamese)",
}

_COMMON_RULES = """\
- 반드시 {language}로만 답한다. 다른 언어를 섞지 않는다.
- 3문장 이내로 쓴다.
- 주어진 데이터 외의 정보(실제 서울 지하철 노선, 주변 시설, 출구, 요금, 실시간 운행·혼잡 정보 등)는 말하지 말 것.
- 역 이름은 데이터에 적힌 그대로 쓴다. 번역하거나 다른 글자로 옮겨 적지 않는다.
- 노선 번호는 답하는 언어의 자연스러운 표기로 쓴다 (예: 한국어 "1호선", English "Line 1", 日本語 "1号線").
- 시간·횟수는 데이터의 숫자를 그대로 쓰고, 새로 계산하거나 지어내지 않는다.
"""

_ROUTE_SYSTEM = """너는 외국인 여행자를 위한 지하철 길찾기 앱의 안내 문장을 쓴다.
서버가 계산한 경로 데이터(JSON)를 받아, 어떻게 타고 갈아타는지 쉽게 설명한다.
규칙:
{rules}- 환승역, 구간별 탑승 시간, 환승 시간, 전체 소요 시간, 환승 횟수를 근거로 설명한다.
"""

_MEETING_SYSTEM = """너는 외국인 여행자를 위한 지하철 앱에서 모임역 추천 이유를 쓴다.
서버가 계산한 모임역과 참가자별 이동 결과(JSON)를 받아, 왜 이 역이 추천되었는지 설명한다.
규칙:
{rules}- 데이터의 rule(추천 기준)과 참가자별 이동 시간·환승 횟수, 합계·최대 시간을 근거로 설명한다.
- 다른 역과 비교하는 말(예: "다른 역보다 몇 분 빠르다")은 데이터에 없으므로 하지 않는다.
- 이동 시간이 0분인 참가자는 이미 모임역에서 출발하는 사람이다.
"""

# 모임역 기준별로 실제 고르는 방법 (data/extra/ASSUMPTIONS.md "모임역 추천 확정 사항"과 같아야 한다)
_MEETING_RULES = {
    "time": "모든 참여자의 이동 시간 합이 가장 작은 역",
    "transfers": "모든 참여자의 환승 횟수 합이 가장 작은 역 (같으면 이동 시간 합이 작은 역)",
    "fairness": "가장 오래 걸리는 참여자의 이동 시간이 가장 짧은 역 (같으면 이동 시간 합이 작은 역)",
}


def _minutes(sec: int) -> int:
    return round(sec / 60)


def _system(template: str, lang: str) -> str:
    return template.format(rules=_COMMON_RULES.format(language=LANGUAGES[lang]))


def _user(kind: str, lang: str, data: dict) -> str:
    return f"다음 {kind}를 {LANGUAGES[lang]}로 설명해 줘.\n데이터(JSON):\n{json.dumps(data, ensure_ascii=False)}"


def route_prompt(route: dict, lang: str) -> tuple[str, str]:
    """POST /routes 응답 모양의 경로를 받아 (시스템 지시, 사용자 메시지)를 만든다.

    출발·도착 시각은 넣지 않는다 (요청마다 달라져 저장한 설명을 다시 쓸 수 없게 된다).
    이 설명 기능에는 요금과 방향을 전달하지 않는다. 방면은 앱이 API의 direction으로 표시한다.
    """
    data = {
        "start": route["start"]["name"],
        "end": route["end"]["name"],
        "total_minutes": _minutes(route["total_sec"]),
        "transfer_count": route["transfer_count"],
        "segments": [
            {
                "line": s["line"],
                "board": s["board"]["name"],
                "alight": s["alight"]["name"],
                "stops": len(s["stations"]) - 1,
                "ride_minutes": _minutes(s["ride_sec"]),
            }
            for s in route["segments"]
        ],
        "transfers": [
            {
                "station": t["station"]["name"],
                "from_line": t["from_line"],
                "to_line": t["to_line"],
                "transfer_minutes": _minutes(t["sec"]),
            }
            for t in route["transfers"]
        ],
    }
    return _system(_ROUTE_SYSTEM, lang), _user("지하철 경로", lang, data)


def meeting_prompt(result: dict, lang: str) -> tuple[str, str]:
    """POST /meeting-station 응답 모양(api-spec.md 3장)의 결과로 프롬프트를 만든다.

    비용(모임역에는 없음), 방면, 주변 시설(데이터 없음)은 넣지 않는다.
    """
    data = {
        "criteria": result["criteria"],
        "rule": _MEETING_RULES[result["criteria"]],
        "meeting_station": result["station"]["name"],
        "total_travel_minutes": _minutes(result["total_travel_sec"]),
        "max_travel_minutes": _minutes(result["max_travel_sec"]),
        "total_transfer_count": result["total_transfer_count"],
        "participants": [
            {
                "start": p["start"]["name"],
                "travel_minutes": _minutes(p["travel_sec"]),
                "transfer_count": p["transfer_count"],
            }
            for p in result["participants"]
        ],
    }
    return _system(_MEETING_SYSTEM, lang), _user("모임역 추천 결과", lang, data)


# ----- 주변 시설 (AI 예시) -----
# 위의 경로·모임역 설명과 달리, 여기서는 데이터에 없는 내용을 AI가 "만든다".
# 노선도가 가상이라 실제 시설 데이터가 없어서, 역 이름만 빌려 예시를 만들기로 했다 (ASSUMPTIONS.md 팀 결정 2026-11-18).
# 앱은 "AI가 만든 예시이며 실제와 다를 수 있음"을 함께 보여 준다.

FACILITY_CATEGORIES = ("cafe", "restaurant", "convenience_store", "pharmacy", "restroom")

_FACILITIES_SYSTEM = """너는 외국인 여행자를 위한 지하철 앱에서 역 주변 시설 예시를 만든다.
이 앱의 노선도는 가상이고 역 이름만 실제 서울 지하철역에서 빌렸다.
같은 이름의 실제 서울 역 주변을 떠올려, 그럴듯한 예시 시설을 만든다. 정확하지 않아도 되는 예시다.
규칙:
- name과 detail은 반드시 {language}로 쓴다. 가게 이름이 고유명사면 그 언어에서 자연스러운 표기를 쓴다.
- category마다 정확히 1개씩, 모두 5개: cafe(카페), restaurant(음식점), convenience_store(편의점), pharmacy(약국), restroom(공중화장실).
- name은 시설 이름(20자 이내), detail은 위치 안내 한 줄이다. 형식 예: 한국어 "2번 출구 · 도보 3분", English "Exit 2 · 3 min walk".
- 공중화장실은 "역 안 · 대합실"처럼 역 안 위치로 써도 된다.
- 광고 문구, 전화번호, 가격, 영업시간, 위험하거나 불쾌한 내용은 쓰지 않는다.
"""

# 한국어가 아닌 언어는 프롬프트도 영어로만 준다 (한글이 한 글자도 없게).
# 한국어 프롬프트를 주면 답에 한글이 섞이는 일이 잦았다 (2026-11-18, 예: ja "スターバックス 千호역점").
_FACILITIES_SYSTEM_OTHER = """You create example facilities near a subway station for a subway app for foreign travelers.
The app's subway map is fictional; only the station names are borrowed from real Seoul subway stations.
Imagine the area around the real Seoul station with the same name and make plausible example facilities. They do not have to be accurate.
Rules:
- Write name and detail only in {language}. Never use Korean letters (Hangul) anywhere, including shop names and station names.
{place_names}- Exactly one facility per category, five in total: cafe, restaurant, convenience_store, pharmacy, restroom.
- name is the facility name (up to 20 characters). detail is a one-line location like "Exit 2 · 3 min walk", written in {language}.
- The restroom may be inside the station (like "Inside station · Concourse").
- No advertising, phone numbers, prices, opening hours, or harmful or offensive content.
"""

# 일본어는 한국 지명을 한자로 옮기다가 모르는 글자만 한글로 남기는 일이 많아서 가타카나로 쓰게 한다.
# (이 줄을 넣기 전 실패한 역 3곳에서 6번 중 1번 성공 → 넣은 뒤 6번 모두 성공, 남은 일본어 80개도 모두 성공)
# 중국어도 같은 실수가 가끔 있지만(예: "廣나루咖啡"), 비슷한 규칙을 넣어 봐도 나아지지 않아서 넣지 않았다.
_PLACE_NAMES = {
    "ja": "- Write Korean place names and station names in katakana only (e.g. Cheonho -> チョンホ, "
          "Jongno -> チョンノ). Do not convert Korean place names to kanji.\n",
}


def facilities_prompt(name_ko: str, name_en: str, lang: str) -> tuple[str, str]:
    """역 이름(한국어·영어)으로 주변 시설 예시를 만드는 프롬프트."""
    if lang == "ko":
        system = _FACILITIES_SYSTEM.format(language=LANGUAGES[lang])
        ask = f"다음 역 주변의 시설 예시 5개를 만들어 줘. name과 detail은 반드시 {LANGUAGES[lang]}로 써.\n역(JSON):"
        data = {"station_name_ko": name_ko}
    else:
        system = _FACILITIES_SYSTEM_OTHER.format(language=LANGUAGES[lang], place_names=_PLACE_NAMES.get(lang, ""))
        ask = f"Make 5 example facilities near this station. Write name and detail only in {LANGUAGES[lang]}.\nStation (JSON):"
        # 한국어 이름을 같이 주면 답이 한국어로 나오는 일이 잦아서 영어 이름만 준다
        data = {"station_name_en": name_en}
    return system, f"{ask}\n{json.dumps(data, ensure_ascii=False)}"
