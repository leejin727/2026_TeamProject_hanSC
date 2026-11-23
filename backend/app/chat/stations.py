"""역 이름 찾기: 사용자가 쓴 글자(오타·줄임말·소리 나는 대로 적은 영어 포함) → 데이터의 역.

챗봇 1단계 규칙(nano/rules.py)이 문장 속 낱말이 역인지 알아볼 때 이 파일의 함수를 부른다.
- 데이터의 이름과 정확히 같으면 그 역 (Found.station_id)
- 줄임말·오타·소리 나는 대로 적은 이름이면 후보 (Found.candidates).
  후보가 하나면 서버가 그 역으로 답하면서 어떻게 이해했는지 알려 주고, 여럿이면 어느 역인지 되묻는다 (service.py)

비슷한 정도는 파이썬 difflib의 ratio(0~1)로 잰다. 한국어는 자모로 풀어서 잰다 ("신도릠" ~ "신도림" = 0.875).
이 계산법을 고른 이유: rules.py의 기준값(0.75·0.8·0.88)과 en_confusables.txt가 여기에 맞춰져 있다.
(목록의 낱말 116개 중 89개가 이 계산으로 0.8 이상이고, 편집 거리로 재면 27개뿐이다. 2026-11-23 확인)

ratio가 높아도 오타로 보지 않는 것 세 가지 (흔한 말이 역으로 잡히는 일을 막는다):
1. ko_confusables.txt에 있는 흔한 말 ("잠시" ≠ 잠실)
2. 역 이름이 통째로 들어 있고 글자가 더 붙은 한국어 낱말 ("성수기" ≠ 성수)
3. 이름 길이에 비해 너무 많이 다른 말 ("몰라" ≠ 모란)
"""

import difflib
import re
import unicodedata
from collections import Counter
from dataclasses import dataclass, field
from functools import lru_cache
from pathlib import Path

from app.routing.graph_builder import Network

MIN_SIMILAR = 0.75   # 이보다 덜 비슷한 이름은 아예 보지 않는다 (rules.py에서 가장 낮은 기준과 같다)
MAX_CANDIDATES = 3   # 후보는 많아야 이만큼

# 데이터의 한국어 이름 → 사람들이 흔히 쓰는 다른 이름. 여기 있는 이름은 "후보"가 된다 (답할 때 어느 역으로 이해했는지 알려 준다).
# 숫자를 한글로 읽은 이름과, 이름 끝의 "입구"·"앞"을 뗀 이름도 여기 적는다.
ALIASES = {
    "고속터미널": ["고터", "고속버스터미널"],
    "남부터미널": ["남터"],
    "건대입구": ["건대", "건입", "건국대"],
    "성신여대입구": ["성신여대"],
    "한성대입구": ["한성대"],
    "태릉입구": ["태릉"],
    "효창공원앞": ["효창공원"],
    "동묘앞": ["동묘"],
    "동대문역사문화공원": ["동역사"],
    "종로3가": ["종로삼가"],
    "종로5가": ["종로오가"],
    "을지로3가": ["을지로삼가"],
    "이대": ["이화여대"],
    "교대": ["서울교대"],
}

# 역 이름과 글자 한두 개만 다른 흔한 한국어 말. 영어 쪽은 rules.py가 en_confusables.txt로 같은 일을 한다.
_KO_CONFUSABLES = frozenset(
    line.strip() for line in Path(__file__).with_name("ko_confusables.txt").read_text(encoding="utf-8").splitlines()
    if line.strip() and not line.startswith("#"))

# 영어 이름의 낱말 중 혼자서는 역을 가리키지 못하는 것. 이 밖의 낱말은 혼자 써도 후보가 된다 ("Konkuk" → 건대입구)
_GENERIC_WORDS = {
    "univ", "university", "of", "office", "market", "terminal", "bus", "express", "park", "stadium", "station",
    "national", "natl", "education", "women", "womens", "womans", "assembly", "culture", "history", "world", "cup",
    "seoul",
}


@dataclass
class Found:
    station_id: str | None = None                        # 데이터의 이름과 정확히 같은 역
    candidates: list[str] = field(default_factory=list)  # 아니면 비슷한 역들 (비슷한 순서)


def names(network: Network) -> dict[str, tuple[str, str]]:
    """{역 ID: (한국어 이름, 영어 이름)}. 데이터에 적힌 그대로다 ("서울역", "Seoul Station")."""
    return network.names


_STATION_WORD = re.compile(r"(?<=.)\s*(?:역|station|stn\.?)$")


def normalize(text: str) -> str:
    """비교하기 좋게 다듬는다: 소문자, 끝의 "역"·"station" 떼기, 빈칸·기호 지우기.

    예: "Seoul Station" → "seoul", "서울역" → "서울", "Jongno 3-ga" → "jongno3ga", "종로 3가" → "종로3가"
    """
    low = unicodedata.normalize("NFKC", text).lower().strip()
    return re.sub(r"[^0-9a-z가-힣]", "", _STATION_WORD.sub("", low))


def find(network: Network, name: str) -> Found:
    """사용자가 쓴 이름 하나 → 역. 정확히 같은 역이 하나면 station_id, 아니면 비슷한 역을 candidates에."""
    index = _index(network)
    norm = normalize(name)
    exact = index.official.get(norm, ())
    if len(exact) == 1:
        return Found(station_id=next(iter(exact)))
    return Found(candidates=[sid for _, sid in index.similar(norm)[:MAX_CANDIDATES]])


def best(network: Network, norm: str, need: float, strict: bool = True) -> tuple[float, list[str]]:
    """normalize()를 거친 글자와 가장 비슷한 역 → (비슷한 정도, 그 역들). need에 못 미치면 (0.0, []).

    strict는 rules.py가 넘기는 값이다. 지금은 이름 전체끼리 비교하는 한 가지 방법만 있어서 쓰지 않는다.
    """
    scored = _index(network).similar(norm)
    if not scored or scored[0][0] < need:
        return 0.0, []
    top = scored[0][0]
    return top, [sid for score, sid in scored if score == top]


# ───────────────────────── 이름을 비교하기 좋은 꼴로 모아 두기 ─────────────────────────

class _Index:
    """노선도 하나의 역 이름 모음.

    official: 데이터의 이름 그대로(다듬은 것) → 역.  other: 줄임말·낱말 하나·소리 나는 대로 적은 이름 → 역.
    """

    def __init__(self, network: Network):
        self.official: dict[str, set[str]] = {}
        self.other: dict[str, set[str]] = {}
        for sid, (ko, en) in network.names.items():
            official = _official_forms(ko, en)
            for form in official:
                self.official.setdefault(form, set()).add(sid)
            for form in _other_forms(ko, en) - official:
                self.other.setdefault(form, set()).add(sid)
        # 오타 비교용: (한글인가, 이름, 비교할 글자, 글자별 개수, 역 ID). 한국어는 자모로 풀어서 비교한다
        self.forms = []
        for forms in (self.official, self.other):
            for form, sids in forms.items():
                korean = _has_hangul(form)
                text = _jamo(form) if korean else form
                self.forms.extend((korean, form, text, Counter(text), sid) for sid in sids)
        self.similar = lru_cache(maxsize=4096)(self._similar)  # 같은 낱말을 여러 번 물어보므로 기억해 둔다

    def _similar(self, norm: str) -> tuple[tuple[float, str], ...]:
        """MIN_SIMILAR 이상 비슷한 역들 (비슷한 정도, 역 ID). 비슷한 순서, 같으면 역 번호 순서."""
        official = self.official.get(norm, set())
        exact = official | self.other.get(norm, set())
        if exact:  # 이름(줄임말 포함)이 정확히 같은 역이 있으면 그 역만
            return tuple((1.0, sid) for sid in sorted(exact, key=lambda sid: (sid not in official, sid)))
        if not norm or norm in _KO_CONFUSABLES:
            return ()
        korean = _has_hangul(norm)
        text = _jamo(norm) if korean else norm
        count = Counter(text)
        scores: dict[str, float] = {}
        for form_korean, form, form_text, form_count, sid in self.forms:
            if form_korean != korean:
                continue
            if korean and form in norm:
                # 역 이름 뒤에 붙은 글자가 조사인지는 rules.py의 정확히 찾기 단계가 이미 가려냈다.
                # 거기서 역이 아니라고 한 낱말("성수기", "옥수수")을 오타로 다시 살리지 않는다.
                continue
            score = _similarity(text, count, form_text, form_count)
            if score > scores.get(sid, 0.0) and _typo_sized(text, form_text):
                scores[sid] = score
        return tuple(sorted(((score, sid) for sid, score in scores.items()), key=lambda x: (-x[0], x[1])))


def _similarity(a: str, a_count: Counter, b: str, b_count: Counter) -> float:
    """difflib ratio. MIN_SIMILAR에 못 미치면 0 (길이·글자 개수만 봐도 뻔할 때는 계산도 하지 않는다)."""
    total = len(a) + len(b)
    if 2 * min(len(a), len(b)) < MIN_SIMILAR * total:
        return 0.0
    if 2 * sum((a_count & b_count).values()) < MIN_SIMILAR * total:
        return 0.0
    ratio = difflib.SequenceMatcher(None, a, b, autojunk=False).ratio()
    return ratio if ratio >= MIN_SIMILAR else 0.0


def _typo_sized(text: str, name: str) -> bool:
    """오타라고 볼 만큼만 다른가: 이름 글자 4개에 1개꼴까지 (짧은 이름은 1개). 이름의 앞부분만 쓴 것은 괜찮다.

    ratio만 보면 짧은 이름에서 전혀 다른 말이 걸린다. 예: "몰라" ~ "모란"은 ratio 0.8이지만 자모 2개가 다르다.
    """
    return name.startswith(text) or _edits(text, name) <= max(1, len(name) // 4)


def _edits(a: str, b: str) -> int:
    """a를 b로 고치는 횟수 (글자 하나 넣기·빼기·바꾸기 = 1번)."""
    row = list(range(len(b) + 1))
    for i, ch_a in enumerate(a, 1):
        new_row = [i]
        for j, ch_b in enumerate(b, 1):
            new_row.append(min(row[j] + 1, new_row[-1] + 1, row[j - 1] + (ch_a != ch_b)))
        row = new_row
    return row[-1]


_cache: tuple[Network, _Index] | None = None


def _index(network: Network) -> _Index:
    """노선도마다 한 번만 만든다 (서버는 노선도를 하나만 쓴다)."""
    global _cache
    if _cache is None or _cache[0] is not network:
        _cache = (network, _Index(network))
    return _cache[1]


def _official_forms(ko: str, en: str) -> set[str]:
    """데이터의 이름과 같은 것으로 치는 꼴들.

    영어 이름은 적는 법이 여럿이다: "Jongno 3(sam)-ga" = "Jongno 3-ga" = "Jongno sam-ga",
    "Konkuk Univ." = "Konkuk University", "History & Culture" = "History and Culture"
    """
    low = en.lower()
    written = {low, re.sub(r"\([^)]*\)", "", low), re.sub(r"\d+\(([^)]*)\)", r"\1", low)}
    written |= {re.sub(r"\buniv\b\.?", "university", w).replace("nat'l", "national").replace("&", "and")
                for w in written}
    return {normalize(ko)} | {normalize(w) for w in written}


def _other_forms(ko: str, en: str) -> set[str]:
    """줄임말, 한국어 이름을 소리 나는 대로 적은 영어("교대" → "gyodae"), 영어 이름 속 낱말 하나("konkuk")."""
    forms = {normalize(alias) for alias in ALIASES.get(ko, [])}
    forms.add(_romanize(normalize(ko)))
    words = [normalize(w) for w in en.lower().split()]
    if len(words) > 1:
        forms |= {w for w in words if len(w) >= 4 and w.isalpha() and w not in _GENERIC_WORDS}
    return forms


# ───────────────────────── 한글 다루기 ─────────────────────────

_CHO = "ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ"
_JUNG = "ㅏㅐㅑㅒㅓㅔㅕㅖㅗㅘㅙㅚㅛㅜㅝㅞㅟㅠㅡㅢㅣ"
_JONG = ("", *"ㄱㄲㄳㄴㄵㄶㄷㄹㄺㄻㄼㄽㄾㄿㅀㅁㅂㅄㅅㅆㅇㅈㅊㅋㅌㅍㅎ")
# 국어의 로마자 표기법 글자 (소리 바뀜은 따지지 않고 글자마다 옮긴다. 나머지 차이는 오타 비교가 메운다)
_ROMAN_CHO = ("g", "kk", "n", "d", "tt", "r", "m", "b", "pp", "s", "ss", "", "j", "jj", "ch", "k", "t", "p", "h")
_ROMAN_JUNG = ("a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo", "u", "wo", "we", "wi",
               "yu", "eu", "ui", "i")
_ROMAN_JONG = ("", "k", "k", "k", "n", "n", "n", "t", "l", "k", "m", "l", "l", "l", "p", "l", "m", "p", "p", "t", "t",
               "ng", "t", "t", "k", "t", "p", "t")


def _has_hangul(text: str) -> bool:
    return any("가" <= ch <= "힣" for ch in text)


def _split(ch: str) -> tuple[int, int, int] | None:
    """한글 한 글자 → (초성, 중성, 종성) 번호. 한글이 아니면 None."""
    code = ord(ch) - 0xAC00
    return (code // 588, code % 588 // 28, code % 28) if 0 <= code < 11172 else None


def _jamo(text: str) -> str:
    """한글을 자모로 푼다. 초성과 받침을 같은 글자로 쳐서, 자판을 친 순서와 같게 한다 ("신도림" → "ㅅㅣㄴㄷㅗㄹㅣㅁ")."""
    out = []
    for ch in text:
        parts = _split(ch)
        out.append(_CHO[parts[0]] + _JUNG[parts[1]] + _JONG[parts[2]] if parts else ch)
    return "".join(out)


def _romanize(text: str) -> str:
    out = []
    for ch in text:
        parts = _split(ch)
        out.append(_ROMAN_CHO[parts[0]] + _ROMAN_JUNG[parts[1]] + _ROMAN_JONG[parts[2]] if parts else ch)
    return "".join(out)
