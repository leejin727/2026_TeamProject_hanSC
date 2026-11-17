"""Gemini에 보내는 설명 프롬프트. 경로용(type=route)과 모임역용(type=meeting) 두 종류.

설계 원칙(AGENTS.md): 계산은 알고리즘, 설명은 AI.
Gemini에는 서버가 계산한 값만 넘기고, 데이터에 없는 사실은 말하지 못하게 한다.
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
