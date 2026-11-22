"""1단계 규칙: 문장에서 역 이름을 찾고(오타 포함), 출발·도착을 나누고, 언어를 고르고, 모델에 넣을 문장을 만든다.

모델(C++ 나노 모델)은 역 이름을 외우지 않는다. 규칙이 찾은 역 자리를 ◆로 바꿔서 넣는다.
예: "신도릠에서 교대까지 어떻게 가?" → 역: 신도림(후보)·교대 → 모델 입력 "◆에서 ◆까지 어떻게 가?"
그래서 역이 바뀌거나 늘어도 모델을 다시 학습할 필요가 없다.
"""

import re
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

from app.chat import stations
from app.routing.graph_builder import Network

STATION_MARK = "◆"   # 역 자리 (NFKC·소문자로 바뀌지 않는 기호)
PERSONAL_MARK = "◇"  # 개인정보 자리

# 카드 번호(13~19자리), 주민·외국인등록번호, 여권 번호(영문 1~2자 + 숫자 7~8자리)
PERSONAL_INFO = re.compile(
    r"\d{4}[ -]?\d{4}[ -]?\d{4}[ -]?\d{1,7}"
    r"|\d{6}[ -]?[1-8]\d{6}"
    r"|(?<![A-Za-z0-9])[A-Za-z]{1,2}\d{7,8}(?!\d)"
)


@dataclass
class Mention:
    """문장 속 역 하나."""

    start: int                 # 원문에서의 위치 [start, end)
    end: int
    written: str               # 사용자가 쓴 글자
    station_id: str | None     # 데이터의 이름과 정확히 한 역이 맞으면 그 역
    candidates: list[str] = field(default_factory=list)  # 아니면 후보 (오타 등)
    role: str = "station"      # start(출발) · end(도착) · station(모름)


def mask_personal(text: str) -> tuple[str, bool]:
    masked = PERSONAL_INFO.sub(PERSONAL_MARK, text)
    return masked, masked != text


# ───────────────────────── 역 찾기 ─────────────────────────

# 이름이 흔한 낱말과 같아서 "역"·"Station"을 붙였을 때만 역으로 보는 것. 예: "서울 지하철 요금" ≠ 서울역
_NEEDS_SUFFIX = {"서울", "seoul"}

# 한국어 역 이름 바로 뒤에 올 수 있는 글자 (조사·역·가는 등). 이 밖의 글자가 붙으면 다른 낱말로 본다.
# 예: "성수기"(성수+기) · "옥수수" · "청구서" · "삼성페이"는 역이 아니다
_KO_NEXT = set("역에까부으로은는이가갈을를도만와과랑하쪽방행출근앞쯤요인엔")

# 한국어 역 이름 뒤에 붙는 조사·말 (긴 것부터). 오타 비교 전에 떼어 낸다.
_KO_TAILS = sorted([
    "에서부터", "으로부터", "역에서", "역까지", "역으로", "역에", "역은", "역이", "역을", "역도", "역요", "역이요",
    "에서", "부터", "까지", "으로", "이랑", "하고", "에는", "에선", "가는", "가려면", "갈려면", "가고", "출발", "도착",
    "방면", "쪽으로", "쪽", "이요", "역", "로", "에", "은", "는", "이", "가", "을", "를", "도", "만", "와", "과", "랑", "행", "요",
    "입니다", "이에요", "에요", "인데", "근데", "는데", "에있어요", "에있는데", "에 있어요", "있어요", "갈때", "가면", "가야",
], key=len, reverse=True)

# 데이터에 없는 유명한 곳. 역 이름과 비슷해도 역으로 보지 않는다 (예: "Incheon" ≠ 신촌)
_PLACES_KO = {"인천", "인천공항", "김포", "김포공항", "공항", "이태원", "홍대", "홍대입구", "코엑스", "남산", "남산타워", "경복궁",
              "인사동", "북촌", "롯데월드", "롯데타워", "부산", "제주", "광화문", "시청", "동대문시장", "남대문", "명동성당",
              "에버랜드", "서울숲", "청계천", "한강공원", "남산", "서울대", "해운대", "용인"}
_PLACES_EN = {"incheon", "gimpo", "airport", "itaewon", "hongdae", "coex", "namsan", "gyeongbokgung", "insadong",
              "bukchon", "lotte", "busan", "jeju", "gwanghwamun", "namdaemun", "seoulforest", "everland", "cheonggyecheon"}
# 두 글자 오타는 이런 말이 붙어 있을 때만 역으로 본다 ("강냠에서" O, "먹고" X)
_KO_EVIDENCE = ("에서", "부터", "까지", "으로", "로", "에", "역", "가는", "가려면", "갈려면", "가고", "출발", "도착", "행", "방면", "쪽")
_KO_NEXT_WORD = ("가", "갈", "출발", "도착", "행", "방면", "역", "까지", "에서", "어떻게", "어케", "어캐")

# 역 이름과 비슷해 보여도 역으로 보지 않는 흔한 낱말 (오타 비교에서 뺀다)
_KO_COMMON = {"어디", "여기", "거기", "저기", "지금", "얼마", "어떻게", "이대로", "그대로", "안녕", "감사", "고마워",
              "언제", "오늘", "내일", "이거", "저거", "그거", "먹고", "하고", "있어", "없어", "싶어", "싶다", "주세요", "알려",
              "길잃음", "길잃었어", "잃음", "길찾기",
              # '~로'로 끝나는 부사: "거꾸로" ≈ 구로가 아니다
              "거꾸로", "그대로", "이대로", "제대로", "마음대로", "새로", "따로", "서로", "바로", "거기로", "여기로", "저기로",
              "어디로", "앞으로", "뒤로", "위로", "아래로", "반대로", "처음으로", "오른쪽으로", "왼쪽으로", "똑바로", "혼자서",
              "지하철", "전철", "기차", "열차", "환승", "출구", "화장실", "엘리베이터", "표", "교통카드", "역무원",
              "시간", "요금", "노선", "방향", "도와", "도움", "잃어버", "가방", "지갑", "핸드폰",
              # 역 이름의 일부인 흔한 낱말: "시장 가는 길"은 가락시장·영등포시장이 아니다
              "시장", "입구", "터미널", "구청", "공원", "경기장", "대학", "대학교", "사거리", "고속", "버스", "문화",
              "역사", "시청", "국회", "의사당", "월드컵", "앞", "동", "구", "역"}
_EN_COMMON = {
    "the", "and", "from", "to", "how", "get", "go", "going", "what", "where", "when", "which", "line", "lines",
    "station", "stations", "subway", "metro", "train", "trains", "transfer", "transfers", "ticket", "tickets",
    "please", "thanks", "thank", "hello", "help", "fastest", "fast", "route", "way", "take", "need", "want",
    "without", "with", "minimum", "minimal", "least", "fewest", "fewer", "about", "there", "here", "then",
    "instead", "again", "back", "return", "reverse", "other", "side", "platform", "exit", "exits", "elevator",
    "toilet", "restroom", "bathroom", "card", "cards", "money", "fare", "fares", "price", "cost", "time",
    "long", "much", "many", "lost", "sick", "stolen", "phone", "wallet", "staff", "english", "korean", "airport",
    "seoul", "real", "map", "show", "tell", "say", "sentence", "phrase", "nearest", "next", "last", "first",
    "start", "starting", "end", "ending", "station's", "minutes", "hours", "mins", "anyway", "also", "sorry",
    "change", "changing", "switch", "direct", "directly", "trip", "travel", "visit", "meet", "near", "around",
    # 여러 낱말 역 이름의 한 조각: 혼자 쓰이면 역이 아니다 ("ticket office" ≠ 영등포구청)
    "office", "market", "terminal", "park", "univ", "university", "stadium", "assembly", "bus", "culture", "history",
    "national", "education", "women", "womens", "world", "cup", "express", "nambu",
}
# 역 이름 묶음의 처음이나 끝에 올 수 없는 말 (기능어·채팅 말). 예: "um how"는 금호(geumho)가 아니다
_EN_LINK = {"to", "from", "the", "of", "and", "or", "a", "an", "at", "in", "on", "for", "via", "by", "with", "how", "what",
            "where", "when", "which", "who", "why", "do", "does", "did", "i", "i'm", "im", "me", "my", "you", "your", "is",
            "are", "was", "it", "this", "that", "can", "could", "would", "should", "will", "um", "uh", "hi", "hey", "ok",
            "okay", "so", "pls", "plz", "please", "thx", "thanks", "then", "instead", "there", "here", "need", "want", "go",
            "get", "take", "about", "now", "just", "lol", "yes", "no", "not", "if", "much", "long", "many", "be", "am"}

# 역 이름(로마자)과 비슷하지만 영어 낱말인 것 ("changes"≈창신, "single"≈신길). 오타 비교에서 뺀다.
_CONFUSABLES_FILE = Path(__file__).with_name("en_confusables.txt")
_EN_CONFUSABLES = {w.strip() for w in _CONFUSABLES_FILE.read_text(encoding="utf-8").splitlines()
                   if w.strip() and not w.startswith("#")}
EN_FUZZY_MULTI = 0.88  # 여러 낱말 묶음은 더 비슷해야 오타로 본다 ("world cup" ≠ 월드컵경기장)

_HANGUL_RUN = re.compile(r"[가-힣0-9]+")
_LATIN_WORD = re.compile(r"[a-z0-9][a-z0-9'’&.\-]*")

KO_FUZZY = 0.8   # 한국어 낱말이 역 이름과 이만큼 비슷하면 오타로 본다 (자모 단위)
KO_FUZZY_WITH_PARTICLE = 0.75  # 바로 뒤에 "에서"·"까지" 같은 말이 붙어 있을 때
EN_FUZZY = 0.8   # 영어 낱말 (5글자 이상만)


def find_mentions(network: Network, text: str) -> list[Mention]:
    """문장 속 역 이름을 모두 찾는다. 출발·도착(role)까지 정한다."""
    low = text.lower() if len(text.lower()) == len(text) else text
    found: list[Mention] = []
    _korean_exact(network, low, found)
    _korean_fuzzy(network, low, found)
    _english(network, low, found)
    found.sort(key=lambda m: m.start)
    for m in found:
        m.written = text[m.start:m.end]
    _assign_roles(low, found)
    return found


def _free(found: list[Mention], start: int, end: int) -> bool:
    return all(end <= m.start or start >= m.end for m in found)


def _korean_exact(network: Network, low: str, found: list[Mention]) -> None:
    """한국어 이름이 그대로 들어 있는 곳. 띄어쓰기를 안 해도 찾는다 ("신도림에서교대까지")."""
    names = stations.names(network)
    hits = []
    for run in _HANGUL_RUN.finditer(low):
        word = run.group()
        for sid, (ko, *_) in names.items():
            if len(ko) < 2:
                continue
            for k in _find_all(word, ko):
                s, e = run.start() + k, run.start() + k + len(ko)
                after = low[e:e + 1]
                has_suffix = after == "역"
                if ko in _NEEDS_SUFFIX and not has_suffix:
                    continue
                if after and "가" <= after <= "힣" and after not in _KO_NEXT:
                    continue  # "성수기", "옥수수": 다른 낱말
                if k == 0 and word.startswith(("이대로", "그대로", "구로구")) or word[k:] in _PLACES_KO:
                    continue
                at_word_start = k == 0 or low[s - 1:s].isspace()
                hits.append((not at_word_start, -len(ko), s, e + (1 if has_suffix else 0), sid))
    for _, _, s, e, sid in sorted(hits):
        if _free(found, s, e) and _preceded_ok(low, s, found):
            found.append(Mention(s, e, "", sid))
    # 줄임말 ("고터", "건입", "종로오가"): 데이터 이름이 아니므로 후보로 확인받는다
    for alias, sid in _korean_aliases(network):
        for k in _find_all(low, alias):
            e = k + len(alias) + (1 if low[k + len(alias):k + len(alias) + 1] == "역" else 0)
            after = low[k + len(alias):k + len(alias) + 1]
            if after and "가" <= after <= "힣" and after not in _KO_NEXT:
                continue
            if _free(found, k, e):
                found.append(Mention(k, e, "", None, [sid]))


def _korean_aliases(network: Network) -> list[tuple[str, str]]:
    by_name = {ko: sid for sid, (ko, _) in network.names.items()}
    return sorted(((stations.normalize(a), by_name[ko]) for ko, aliases in stations.ALIASES.items() if ko in by_name
                   for a in aliases if re.search(r"[가-힣]", a)), key=lambda x: -len(x[0]))


def _preceded_ok(low: str, s: int, found: list[Mention]) -> bool:
    """낱말 중간에서 찾은 이름은 앞이 조사·역으로 끝날 때만 인정한다. 예: "신도림에서|교대" O, "아이대학" X"""
    if s == 0 or not ("가" <= low[s - 1] <= "힣"):
        return True
    before = low[max(0, s - 4):s]
    if any(m.end == s for m in found):
        return True
    if len(low) >= s + 3 and any(m.start == s for m in found):
        return True
    # 앞이 조사·말끝으로 끝나면 띄어쓰기를 안 한 것으로 본다 ("저기요복정부터", "근데동대문역사문화공원")
    return before.endswith(("에서", "부터", "까지", "으로", "랑", "하고", "역", "로", "에", "와", "과", "서", "요", "데", "고",
                            "는", "은", "가", "이", "음", "아", "어", "기"))


def _find_all(word: str, part: str):
    i = word.find(part)
    while i >= 0:
        yield i
        i = word.find(part, i + 1)


_KO_SPLIT = re.compile(r"에서부터|에서|부터|까지|으로|근데|인데|는데|있어요|있는데")  # 띄어쓰기 없이 붙은 말을 나누는 곳 (역 이름 안에는 없는 말)
# 낱말 앞에 붙어 오는 군말 ("궁금한데상뵹까지" → "상뵹")
_KO_LEADS = ("궁금한데", "저기요", "저기", "혹시", "근데", "그럼", "그러면", "지금", "아", "음", "어")


def _korean_fuzzy(network: Network, low: str, found: list[Mention]) -> None:
    """한국어 오타: 아직 찾지 못한 부분에서 조사를 떼고 역 이름과 자모 단위로 비교한다.
    예: "신도릠에서" → 신도림(후보), "신도릠에서교대까지" → 신도릠 | 교대"""
    for word in re.finditer(r"[가-힣0-9]+", low):
        for s0, piece in _uncovered(found, word.start(), word.group()):
            for part in _split_keep(piece):
                ps, stem = s0 + part[0], part[1]
                if stem in _KO_COMMON:
                    continue
                for lead in _KO_LEADS:
                    if stem.startswith(lead) and len(stem) - len(lead) >= 2:
                        ps, stem = ps + len(lead), stem[len(lead):]
                        break
                m = _fuzzy_korean(network, low, ps, stem)
                if m:
                    found.append(m)


def _fuzzy_korean(network: Network, low: str, ps: int, word: str) -> Mention | None:
    """조사를 뗀 꼴과 떼지 않은 꼴을 둘 다 비교한다 ("종로오가"의 "가"는 조사가 아니다)."""
    stems = [(word, "")]
    stem, tail_used = word, ""
    for _ in range(2):  # 말끝이 두 겹일 수 있다: "여신내에있어요" → "여신내"
        for tail in _KO_TAILS:
            if stem.endswith(tail) and len(stem) - len(tail) >= 2:
                stem, tail_used = stem[: -len(tail)], tail_used or tail
                stems.append((stem, tail_used))
                break
    whole = re.sub(r"[\s?!.~…,]+", "", low) == word  # 메시지 전체가 이 낱말 하나 ("합졍")
    best = None
    for stem, tail in stems:
        if len(stem) < 2 or len(stem) > 9 or stem in _KO_COMMON or stem in _PLACES_KO:
            continue
        next_word = low[ps + len(word):].lstrip()
        evidence = whole or tail.startswith(_KO_EVIDENCE) or next_word.startswith(_KO_NEXT_WORD)
        if len(stem) == 2 and not evidence:
            continue
        if stations.normalize(stem) in _NEEDS_SUFFIX and not tail.startswith("역"):
            continue
        need = KO_FUZZY_WITH_PARTICLE if evidence else KO_FUZZY  # "교댸까지"처럼 조사가 붙으면 조금 너그럽게
        score, _ = stations.best(network, stations.normalize(stem), need, strict=True)
        if score >= need and (best is None or score > best[0]):
            best = (score, stem)
    if best is None:
        return None
    m = _mention(network, ps, ps + len(best[1]), best[1])
    if low[m.end:m.end + 1] == "역":
        m.end += 1
    return m


def _uncovered(found: list[Mention], start: int, text: str):
    """낱말에서 이미 찾은 역을 뺀 나머지 조각들 (위치, 글자)."""
    pieces, cur = [], start
    for m in sorted(found, key=lambda m: m.start):
        if m.end <= start or m.start >= start + len(text):
            continue
        if m.start > cur:
            pieces.append((cur, text[cur - start:m.start - start]))
        cur = max(cur, m.end)
    if cur < start + len(text):
        pieces.append((cur, text[cur - start:]))
    return pieces


def _split_keep(piece: str):
    """조사로 나눈 조각들 (조각 안 위치, 글자). 조사는 앞 조각에 붙여 둔다 (뒤에서 다시 뗀다)."""
    out, last = [], 0
    for m in _KO_SPLIT.finditer(piece):
        out.append((last, piece[last:m.end()]))
        last = m.end()
    if last < len(piece):
        out.append((last, piece[last:]))
    return out


def _english(network: Network, low: str, found: list[Mention]) -> None:
    """영어(로마자) 이름: 낱말 1~6개 묶음을 역 이름과 비교한다. 오타·소리 나는 대로 쓴 이름("Gyodae")도 찾는다."""
    words = list(_LATIN_WORD.finditer(low))
    spans = []
    for n in range(6, 0, -1):
        for i in range(len(words) - n + 1):
            group = words[i:i + n]
            first, last = group[0].group().strip(".'’-"), group[-1].group().strip(".'’-")
            if first in _EN_LINK or last in _EN_LINK:
                continue
            s, e = group[0].start(), group[-1].end()
            phrase = low[s:e]
            norm = stations.normalize(phrase)
            if len(norm) < 3 or norm.isdigit():
                continue
            if n == 1 and (first in _EN_COMMON or norm in _EN_COMMON):
                continue
            if any(w.group().strip(".'’-") in _PLACES_EN for w in group):
                continue
            if norm in _NEEDS_SUFFIX and not re.search(r"(station|stn|역)\s*$", phrase):
                continue
            score, _ = stations.best(network, norm, EN_FUZZY, strict=True)
            named = re.match(r"\s*(station|stn|역)\b", low[e:]) is not None  # 뒤에 "station"이 붙으면 역이라는 뜻
            if score < 1.0 and not named and (norm in _EN_CONFUSABLES or (n > 1 and score < EN_FUZZY_MULTI)):
                continue
            if score >= 1.0 or (score >= EN_FUZZY and len(norm) >= 5):
                spans.append((-score, -(e - s), s, e))
    for _, _, s, e in sorted(spans):
        if _free(found, s, e):
            # 바로 뒤의 "station"·"stn"·"역"도 이 역에 붙인다
            tail = re.match(r"\s*(station|stn|역)\b", low[e:]) or re.match(r"역", low[e:])
            end = e + (tail.end() if tail and _free(found, e, e + tail.end()) else 0)
            found.append(_mention(network, s, end, low[s:e]))


def _mention(network: Network, s: int, e: int, name: str) -> Mention:
    hit = stations.find(network, name)
    return Mention(s, e, "", hit.station_id, hit.candidates)


# ───────────────────────── 출발·도착 나누기 ─────────────────────────

_KO_START = ("에서", "부터", "출발", "인데", "이에요 근데", "에 있는데", "에있는데", "에 있어", "에있어")  # "지금 신당역인데" = 출발
_KO_END = ("까지", "으로", "로", "에 가", "에가", "에 어떻게", "에어떻게", "엔 어떻게", "행", "방면", "쪽으로", "도착")
_KO_GO = ("가는", "가려", "갈려", "가고", "가야", "가요", "가면", "가나", "갈 ", "갈수", "갈까", "가자", "가기", "갈래", "가?", "가 ")
_EN_START = re.compile(r"(from|leaving|departing|starting at|starting from|start at|i'?m at|i am at|im at|i'?m in|"
                       r"currently at|now at|at|in|fom|frm|form)\s+$")
_EN_END = re.compile(r"(to|towards?|for|reach|into|till|until|get to|go to|going to|head to|heading to|bound for|"
                     r"arrive at|what about|how about|go|going|head|heading|->|→|~|-)\s+(the\s+)?$|(->|→|~|-)\s*$")


def _assign_roles(low: str, found: list[Mention]) -> None:
    prev_end = 0
    for m in found:
        m.role = _role(low, m, prev_end)
        prev_end = m.end
    if len(found) == 1 and found[0].role == "station":
        found[0].role = _sole_role(low, found[0])
    if len(found) == 2:  # 둘이면 정해지지 않은 쪽을 채운다: 보통 먼저 말한 역이 출발역
        a, b = found
        if a.role == "station" and b.role == "station":
            a.role, b.role = "start", "end"
        elif a.role == "station":
            a.role = "start" if b.role == "end" else "end"
        elif b.role == "station":
            b.role = "end" if a.role == "start" else "start"
        elif a.role == b.role:  # 둘 다 같은 쪽이면 순서대로
            a.role, b.role = "start", "end"


def _role(low: str, m: Mention, prev_end: int) -> str:
    """한국어는 뒤에 붙은 조사("에서"·"까지"), 영어는 앞의 낱말("from"·"to")로 정한다."""
    attached = low[m.end:m.end + 8]
    spaced = attached.lstrip()
    if attached.startswith(_KO_START) or spaced.startswith("출발"):
        return "start"
    if attached.startswith(_KO_END) or spaced.startswith(("도착", "까지")) or spaced.startswith(_KO_GO):
        return "end"
    before = low[max(prev_end, m.start - 24):m.start]
    if _EN_END.search(before):
        return "end"
    if _EN_START.search(before):
        return "start"
    return "station"


def _sole_role(low: str, m: Mention) -> str:
    """역이 하나뿐이고 바로 옆에 단서가 없을 때: 문장 뒤쪽에 "가는·가려면"이 있으면 도착역, "출발"이 있으면 출발역."""
    rest = low[m.end:]
    if re.search(r"출발|from", rest):
        return "start"
    if re.search(r"(가는|가려|갈려|가고|가야|갈래|갈 수|가요|가나요|가면|갈까|도착|까지)", rest):
        return "end"
    return "station"


# ───────────────────────── 언어 ─────────────────────────

_VIETNAMESE = set("ăâđêôơưàảãáạằẳẵắặầẩẫấậèẻẽéẹềểễếệìỉĩíịòỏõóọồổỗốộờởỡớợùủũúụừửữứựỳỷỹýỵ")
# 번체에만 있는 흔한 글자 / 간체에만 있는 흔한 글자 (지하철 질문에 자주 나오는 것)
_HANT = set("車鐵場線轉乘從這個們買錢點裡嗎說請問該應東門總機開關號區後時間兩對樣讓過還進邊近遠廁電梯們圖")
_HANS = set("车铁场线转乘从这个们买钱点里吗说请问该应东门总机开关号区后时间两对样让过还进边近远厕电梯们图")


def detect_lang(text: str, mentions: list[Mention]) -> str | None:
    """사용자가 쓴 언어: ko, en, ja, zh-Hans, zh-Hant, vi, other(지원하지 않는 언어). 역 이름·숫자뿐이면 None."""
    rest = list(text)
    for m in mentions:
        rest[m.start:m.end] = [" "] * (m.end - m.start)
    rest = "".join(rest).lower()
    if re.search(r"[가-힣ㄱ-ㅣ]", rest):
        return "ko"
    if re.search(r"[぀-ヿ]", rest):
        return "ja"
    if re.search(r"[一-鿿]", rest):
        hant = sum(c in _HANT for c in rest) - sum(c in _HANS for c in rest)
        return "zh-Hant" if hant > 0 else "zh-Hans" if hant < 0 else None
    letters = [c for c in rest if c.isalpha()]
    if len(letters) < 2:
        return None
    if any(c in _VIETNAMESE for c in letters):
        return "vi"
    if any(not c.isascii() for c in letters):
        return "other"
    return "en"


# ───────────────────────── 모델에 넣을 문장 ─────────────────────────

def model_text(text: str, mentions: list[Mention]) -> str:
    """역 자리를 ◆로, 개인정보를 ◇로 바꾸고 소문자로 + 힌트 표시. 예: "Sindorim to Gangnam fastest?" → "◆ to ◆ ㉑fastest?" """
    out, last = [], 0
    for m in mentions:
        out.append(text[last:m.start])
        out.append(STATION_MARK)
        last = m.end
    out.append(text[last:])
    joined = PERSONAL_INFO.sub(PERSONAL_MARK, "".join(out))
    plain = re.sub(r"\s+", " ", unicodedata.normalize("NFKC", joined).lower()).strip()
    return hint(plain)  # NFKC 뒤에 붙인다 (원 숫자 표시가 숫자로 바뀌지 않게)


# ───────────────────────── 힌트 표시 ─────────────────────────
# 뜻이 같은 낱말을 같은 표시로 묶어 모델 입력에 붙인다 (세이빙 AI와 같은 방법).
# 모델이 처음 보는 말투라도 낱말 묶음으로 뜻을 잡게 하려는 것. 예: "how to buy tmoney" → "how to buy ①tmoney"
# 낱말을 더하면 모델을 다시 학습하지 않아도 어느 정도 바로 효과가 있다 (같은 표시로 묶이므로).
# 표시는 원 숫자 ①~⑳ ㉑~㉕. NFKC를 거친 뒤에 붙이므로 숫자로 바뀌지 않는다.

def _en(*words: str) -> str:
    """영어 낱말·구 (앞뒤가 영문자가 아닐 때만)."""
    return r"(?<![a-z])(?:" + "|".join(words) + r")(?![a-z])"


HINTS = [
    ("①", [r"(?<![대발])표(?!지|시|현|정)", "티켓", "승차권", "교통카드", "티머니", "일회용", "발권", "발매기", "매표", "충전", "잔액", "끊는", "카드",
           _en("tickets?", "t-?money", "t money", "transit card", "travel card", "metro card", "one-?time", "single journey",
               "one-?way", "fare card", "top ?up", "recharge", "reload", "machine", "vending", "buy", "purchase", "card", "pay")]),
    ("②", ["개찰구", "개표구", "게이트", "출입구 기계", "찍", "태그", "삑", "안 열려", "안열려", "통과",
           _en("gates?", "turnstiles?", "fare gates?", "tap", "tapped", "scan", "beep(?:ed|s)?", "let me (?:in|through|out)", "barrier")]),
    ("③", ["환승", "갈아타", "갈아탈", "바꿔 타", "다른 호선", _en("transfer\\w*", "change lines?", "changing (?:lines|to line|trains)", "change to line",
                                                              "switch(?:ing)? (?:lines?|trains)", "change trains")]),
    ("④", ["방면", "방향", "행선지", "표지판", "표지", "화살표", "안내판", r"행(?=['\"]| ?이라)", r"~행", _en("bound for", "direction", "signs?", "arrows?", "which way")]),
    ("⑤", ["안내방송", "방송", "전광판", "화면", "모니터", "led", "다음 ?역", "내릴 ?역", "영어로 나와", _en("announcements?", "announcing", "display", "screens?",
                                                                                          "monitor", "board", "next stop", "next station", "get off")]),
    ("⑥", ["막차", "첫차", "마지막 ?(?:열차|차|지하철)", "몇 ?시까지", "끊기", _en("last train", "last subway", "last metro", "first train", "final train",
                                                                   "last one", "train of the night",
                                                                   "until what time", "run late", "after midnight", "closing time")]),
    ("⑦", ["잃어버", "잃었", "두고 ?내", "놓고 ?내", "놓고 ?왔", "놓고왔", "분실", "유실물", "잊어버리고", "없어졌",
           _en("lost (?:my|a|the|something|it|her|his|our)", "left (?:my|it|something|a)", "missing", "forgot (?:my|it)", "dropped my",
               "lost and found", "lost property", "can'?t find my")]),
    ("⑧", ["길(?:을)? ?잃", "길잃", "헤매", "어딘지 ?(?:모르|몰라)", "어디인지 ?(?:모르|몰라)", "어디 ?있는지 ?(?:모르|몰라|설명)", "위치(?:도|를)? ?(?:모르|몰라)",
           "어디(?:서|)부터 ?잘못", "잘못 ?온", "어디야 여기", "여기 어디", "잘못 ?탔", "잘못 ?내렸", "잘못내", "잘못 ?왔",
           "엉뚱한 ?(?:데|곳)", "반대로 탔", "길을 모르",
           _en("i'?m lost", "i am lost", "got lost", "am lost", "where am i", "wrong (?:train|line|way|exit)", "don'?t know where i am",
               "idk where i am", "confused", "no idea where", "no clue where", "ended up", "lost(?=\\s*[.!?,]|$)", "(?:are|we'?re|were) lost",
               "lost (?:inside|somewhere|in the)", "(?:totally|completely|so) lost", "got off at the wrong", "don'?t recognize", "explain where i am")]),
    ("⑨", ["안내 ?센터", "안내소", "안내 ?데스크", "고객 ?센터", "역무실", "관광 ?안내", "물어볼", "문의", "누구한테", "누구에게", "역무원", "직원",
           _en("information", "info desk", "info center", "help ?desk", "help center", "customer service", "station office", "staff",
               "attendants?", "employees?", "ask for help", "who (?:can|should|do) i ask")]),
    ("⑩", ["문장", "한국어로", "한국말로", "보여 ?줄", "보여주기", "말하는 ?법", "어떻게 말해", "뭐라고", "이라고", "라는", "라고 ", "내밀", "띄워",
           _en("sentences?", "phrases?", "in korean", "how (?:do i|to|can i) say", "what (?:do|should) i say", "korean for", "show (?:them|staff|the staff|people)",
               "tell (?:the )?staff", "expression")]),
    ("⑪", ["아파", "아프", "어지러", "어지럽", "핑 ?돌", "경련", "발작", "의식", "다쳤", "다쳐", "피가", "피나", "피 ?흘", "쓰러", "토할", "숨이", "숨을", "기절", "구급차", "119", "가슴이",
           "열이", "넘어져", "속이 안", "몸이 안",
           _en("hurt", "injured", "injury", "bleeding", "blood", "dizzy", "faint\\w*", "collapsed?", "sick", "ill", "breathe", "ambulance",
               "chest pain", "throw up", "vomit\\w*", "pass out", "fell down", "heart attack", "not feeling (?:well|good)",
               "don'?t feel (?:well|good)", "feel(?:ing)? (?:bad|sick|unwell|terrible|awful)", "pain", "nause\\w*", "seizure", "unconscious",
               "convuls\\w*")]),
    ("⑫", ["훔쳐", "훔친", "도둑", "소매치기", "날치기", "뺏", "위협", "협박", "털렸", "털림", "내놓으", "따라와", "따라오", "만졌", "성추행", "가져갔",
           _en("stole", "stolen", "steal\\w*", "robbed", "pick-?pocket\\w*", "thief", "mugged", "snatched", "grabbed", "threaten\\w*",
               "following me", "harass\\w*", "took my")]),
    ("⑬", ["다음 ?열차", "다음 ?차", "언제 ?와", "언제 ?오", "언제 ?도착", "몇 ?시에 ?와", "앉아서", "자리 ?있", "혼잡", "몇 ?분 ?(?:남|뒤|후|걸려서 와)", "지연", "연착", "운행", "늦어", "지금 어디", "붐벼",
           "사람 많", "사고", "끊겼",
           _en("next train", "delay\\w*", "late", "running now", "right now", "how long until", "minutes until", "crowded", "real ?time", "live",
               "when (?:is|does|will) the (?:next )?train", "arriv\\w*", "(?:are|is) (?:the )?(?:trains?|subway) running", "still running", "packed",
               "busy (?:now|rn|right now)", "rn", "get a seat")]),
    ("⑭", ["화장실", "엘리베이터", "엘베", "에스컬레이터", "에스컬", "매점", "출구", "보관함", "사물함", "편의점", "atm", "수유실", "계단", "휠체어", "유모차", "층",
           _en("toilets?", "restrooms?", "bathrooms?", "washrooms?", "elevators?", "lifts?", "escalators?", "exits?", "lockers?", "atm",
               "stairs", "stroller", "wheelchair", "conv\\w*nience store", "shops?", "vending")]),
    ("⑮", ["날씨", "비 ?와", "비 ?올", "눈 ?와", "눈 ?올", "미세먼지", "축구", "야구", "이겼", "프롬프트", "환전", "챗지피티", "지피티", "맛집", "밥집", "식당", "카페", "술집", "호텔", "숙소", "번역", "농담", "노래", "주식", "환율", "코드", "숙제", "몇 ?살",
           "규칙", "무시", "역할", "여자친구", "남자친구", "사랑해", "심심", "추천",
           _en("weather", "restaurants?", "food", "eat", "cafe", "bars?", "hotels?", "translate", "joke", "sing", "stocks?", "bitcoin",
               "exchange rate", "code", "homework", "your name", "how old", "ignore", "instructions", "pretend", "rules", "system prompt",
               "bts", "k-?pop", "politics", "love you", "bored", "recommend", "rain\\w*", "snow\\w*", "sunny", "score", "who won", "chat ?gpt", "gpt",
               "are (?:you|u) (?:a )?(?:bot|ai|human|real|robot)", "money exchange", "exchange money")]),
    ("⑯", ["바보", "멍청", "병신", "븅신", "쓰레기", "꺼져", "닥쳐", "시발", "ㅅㅂ", "씨발", "개새", "ㅗ", "한심", "개못", "빡대가리",
           _en("stupid", "dumb", "idiot", "moron", "useless", "trash", "garbage", "shut up", "screw you", "f you", "fuck\\w*", "shit\\w*",
               "wtf", "go to hell", "sucks?")]),
    ("⑰", ["안녕(?!히)", "하이", "ㅎㅇ", "반가", "헬로", "안뇽", "뭐 할 수 있", "뭘 도와", "어떻게 써", "어떻게 쓰는", "너 뭐야", "누구야", "뭐 하는 (?:거|앱|봇)",
           _en("hi", "hello", "hey", "hiya", "yo", "good morning", "good evening", "sup", "what can you do", "how does this work", "who are you",
               "this bot", "what is this", "how (?:do i|to) use")]),
    ("⑱", ["고마", "감사", "땡큐", "ㄱㅅ", "ㄳ", "수고하", "덕분에", "안녕히", "도움 ?됐", _en("thanks?", "thank you", "thx", "ty", "appreciate\\w*", "cheers",
                                                                        "helpful",
                                                                        "bye", "goodbye", "see you")]),
    ("⑲", ["실제", "진짜", "서울 ?지하철", "공항", "기본요금", "시간표", "급행", "경복궁", "창덕궁", "덕수궁", "창경궁", "궁궐", "타워", "월드(?!컵)", "시장(?=\\s|$|에|까|으|가)",
           *sorted(_PLACES_KO, key=len, reverse=True),
           _en("real", "actual", "airport", "timetable", "seoul (?:subway|metro)", "fare in seoul", "palace", "tower", "museum", "mall",
               *sorted(_PLACES_EN, key=len, reverse=True))]),
    ("㉕", ["영어 ?(?:하실|할 ?줄|가능|되|돼|하세요|해요|할 수)", "한국어 ?(?:못|몰라|잘 못)", "한국말 ?(?:못|몰라|잘 못)", "외국인이라",
           "한국어 ?(?:를|가)? ?(?:이해|몰)",
           _en("speak english", "speaks english", "english speaker", "don'?t speak korean", "can'?t speak korean", "no korean", "only speak english",
               "do you speak english", "understand korean", "korean is (?:bad|not good)")]),
    ("⑳", ["환승 ?없(?:이|는)", "환승 ?안", "안 ?갈아타", "갈아타지 ?않", "환승 ?적", "환승 ?덜", "덜 ?갈아타", "갈아타는 ?(?:거|걸|게) ?(?:적|최소|덜|싫)",
           "갈아타기 ?싫", "환승 ?싫", "환승 ?최소",
           "환승 ?한 ?번", "한 ?번에", "환승 ?제일 적", "직통",
           _en("no transfers?", "without (?:transfer\\w*|changing)", "fewer (?:transfers?|changes)", "less transfers?", "least transfers?",
               "fewest", "min(?:imum)? transfers?", "no changes", "direct", "zero transfers?", "don'?t want to transfer", "less chang\\w*",
               "fewer chang\\w*", "hate transfer\\w*", "without switching")]),
    ("㉑", ["빠른", "빨리", "최단", "가장 ?빠", "제일 ?빠", "젤 ?빠", "급해", "늦었", "시간 ?(?:제일|가장) ?(?:적|짧)", "시간 ?짧", "얼른", "빠르게",
           _en("fastest", "quickest", "quickly", "fast", "asap", "hurry", "shortest time", "soonest", "faster", "quicker", "in a rush", "most fast",
               "speed", "don'?t care about transfers")]),
    ("㉒", ["그럼", "그러면", "다시", "는요", "은요", "대신", "바꿀게", "바꿔", "말고", _en("instead", "then", "what about", "how about", "and from",
                                                                          "again", "another", "other one", "change (?:it|the destination)")]),
    ("㉓", ["반대로", "반대 ?방향", "거꾸로", "돌아(?:갈|올|오는|가는)", "올 ?때", "집에 ?갈", "되돌아", _en("back", "return\\w*", "reverse",
                                                                                      "opposite", "other way", "way home")]),
    ("㉔", ["가는 ?(?:법|길|방법|경로|거)", "어떻게 ?가", "어케 ?가", "가려면", "갈려면", "경로", "루트", "길 ?찾", "가야 ?(?:돼|해|되)", "몇 ?정거장",
           "얼마나 걸려", "가고 ?싶", "출발", "도착", "→", "->",
           "지하철로", _en("route", "get to", "go to", "get from", "how do i get", "how to get", "how (?:do i|to) go", "directions?", "way to",
               "travel (?:from|to)", "how to travel",
               "how long", "how many stops", "take me", "going to", "which (?:train|line)")]),
]
# 겹칠 때는 더 구체적인 묶음이 먼저 ("환승 없이"는 ③환승이 아니라 ⑳환승 적게, "i'm lost"는 ⑦분실이 아니라 ⑧길 잃음)
_FIRST = "⑳㉑㉓⑧⑦"
_HINT_RES = sorted(((mark, re.compile(unicodedata.normalize("NFKC", "|".join(f"(?:{p})" for p in patterns))))
                    for mark, patterns in HINTS),
                   key=lambda mp: (_FIRST.index(mp[0]) if mp[0] in _FIRST else len(_FIRST)))


def hint(text: str) -> str:
    """낱말 앞에 힌트 표시를 붙인다. 겹치면 _FIRST의 표시가, 그다음은 위 목록 순서가 이긴다."""
    marks: dict[int, str] = {}
    taken = [False] * (len(text) + 1)
    for mark, rx in _HINT_RES:
        for m in rx.finditer(text):
            if m.start() == m.end() or any(taken[m.start():m.end()]):
                continue
            marks[m.start()] = marks.get(m.start(), "") + mark
            for i in range(m.start(), m.end()):
                taken[i] = True
    out = []
    for i, ch in enumerate(text):
        if i in marks:
            out.append(marks[i])
        out.append(ch)
    return "".join(out)
