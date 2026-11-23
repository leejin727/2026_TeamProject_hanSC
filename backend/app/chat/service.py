"""챗봇 답 만들기: 메시지 하나 + 직전 대화 값(context) → 답 (docs/api-spec.md 4-2장).

nano.understand()가 고른 의도에 따라
- 길찾기: 역을 정하고(빠진 역은 되묻고, 오타는 알려 주고) 기존 경로 계산(compute_route)을 부른다
- 그 밖: data/chat/replies.json의 고정 문구

외부 AI는 부르지 않는다. 메시지 내용은 저장하지 않고 로그에도 남기지 않는다.
서버는 대화를 기억하지 않는다. 이어 묻기에 필요한 값은 앱이 context로 들고 다닌다.
"""

import json
import logging
from dataclasses import dataclass
from typing import Literal

from pydantic import BaseModel

from app.api.common import station_ref
from app.api.routes import RouteRequest, compute_route
from app.chat import nano, stations
from app.config import DATA_DIR
from app.errors import AppError
from app.routing.graph_builder import Network

logger = logging.getLogger("subfit")

REPLY_LANGS = ("ko", "en")  # 답 문구가 있는 언어. 모델도 이 두 언어의 문장만 믿을 수 있다 (docs/chatbot.md 8장)
TEXTS = json.loads((DATA_DIR / "chat" / "replies.json").read_text(encoding="utf-8"))


class Context(BaseModel):
    """앱이 직전 응답에서 받아 다음 요청에 그대로 돌려보내는 값."""

    start: str | None = None                              # 출발역 ID (직전 길찾기의 역, 또는 지금까지 들은 역)
    end: str | None = None                                # 도착역 ID
    criteria: Literal["time", "transfers"] | None = None
    # 직전 답에서 어느 역을 물어봤는지. 둘 다 물어봤을 때도 end다 (역 하나만 답하면 도착역으로 본다)
    asked: Literal["start", "end"] | None = None


def reply(network: Network, message: str, lang: str, context: Context) -> dict:
    """lang은 앱의 언어 설정이다. 사용자가 쓴 언어를 알 수 없을 때(역 이름만 보냈을 때)만 쓴다."""
    try:
        answer = nano.understand(network, message)
    except nano.NanoUnavailable as e:
        logger.warning("챗봇 모델을 쓸 수 없음: %s", e)  # 까닭만 남긴다. 메시지 내용은 남기지 않는다
        raise AppError(503, "CHAT_UNAVAILABLE", "지금은 챗봇을 쓸 수 없습니다") from e

    fallback = lang if lang in REPLY_LANGS else "en"
    if answer.lang is not None and answer.lang not in REPLY_LANGS:
        # 일본어·중국어 등은 모델이 자신 있게 틀려서 확신 기준으로 걸러지지 않는다. 의도를 믿지 않고 안내만 한다
        return _fixed("out_of_scope", "unsupported_language", fallback, context)
    lang = answer.lang or fallback

    if answer.intent == "route":
        return _route(network, answer, lang, context)
    topic = {
        "faq": answer.faq_id,
        "phrase": answer.phrase_id or "list",
        "help": "lost",
        "emergency": answer.phrase_id,
        "out_of_scope": answer.kind,
        "greet": "hello",
        "thanks": "welcome",
    }[answer.intent]
    return _fixed(answer.intent, topic, lang, context)


def _response(intent: str, topic: str, lang: str, text: str, context: Context,
              route: dict | None = None, phrases=(), options=()) -> dict:
    return {"intent": intent, "topic": topic, "lang": lang, "text": text, "route": route,
            "phrases": list(phrases), "options": list(options), "context": context.model_dump()}


# ───────────────────────── 고정 문구 ─────────────────────────

def _fixed(intent: str, topic: str, lang: str, context: Context) -> dict:
    """고정 문구로 답한다. 길찾기 대화 값(context)은 건드리지 않고 그대로 돌려준다."""
    if intent == "phrase":
        entry = TEXTS["phrase"]["list" if topic == "list" else "one"]
        cards = list(TEXTS["phrases"]) if topic == "list" else [topic]
    else:
        entry = TEXTS[intent][topic]
        cards = [entry["phrase"]] if "phrase" in entry else []  # 문구에 딸린 문장 카드 ("아래 문장을 보여 주세요")
    return _response(intent, topic, lang, entry[lang], context, phrases=[_card(c, lang) for c in cards])


def _card(phrase_id: str, lang: str) -> dict:
    """역무원에게 보여 줄 한국어 문장 하나. meaning은 그 뜻 (한국어로 답할 때는 필요 없어서 None)."""
    phrase = TEXTS["phrases"][phrase_id]
    return {"id": phrase_id, "korean": phrase["korean"], "meaning": phrase["en"] if lang == "en" else None}


# ───────────────────────── 길찾기 ─────────────────────────

@dataclass
class _Said:
    """사용자가 말한 역 하나."""

    written: str
    ids: list[str]  # 그 역. 후보가 여럿이면 여러 개
    exact: bool     # 데이터의 이름과 정확히 같았는가 (아니면 오타·줄임말)


def _said(network: Network, name: nano.StationName | None) -> _Said | None:
    if name is None:
        return None
    found = stations.find(network, name.written)
    ids = [found.station_id] if found.station_id else found.candidates
    return _Said(name.written, ids, found.station_id is not None) if ids else None


def _route(network: Network, answer: nano.Answer, lang: str, ctx: Context) -> dict:
    said = {"start": _said(network, answer.start), "end": _said(network, answer.end)}
    loose = _said(network, answer.station)  # 출발인지 도착인지 말하지 않은 역 ("강남")
    if loose:
        # 방금 물어본 자리 → 도착역 → 출발역 순으로, 비어 있는 곳에 넣는다
        slot = ctx.asked if ctx.asked and not said[ctx.asked] else "end" if not said["end"] else "start"
        said[slot] = said[slot] or loose

    # 앞 대화의 값은 이어 묻는 말("그럼 환승 없이는?")이거나 방금 역을 물어본 뒤일 때만 가져온다
    continuing = answer.follow_up or ctx.asked is not None
    before = {"start": ctx.start, "end": ctx.end} if continuing else {"start": None, "end": None}
    if answer.reverse and ctx.start and ctx.end:  # "반대로는?"
        before = {"start": ctx.end, "end": ctx.start}
    criteria = answer.criteria or (ctx.criteria if continuing else None) or "time"

    def name(station_id: str) -> str:
        return station_ref(network, station_id, lang)["name"]

    def text(topic: str, **values) -> str:
        return TEXTS["route"][topic][lang].format(**values)

    # 오타·줄임말인데 후보가 하나면 그 역으로 답하면서 어떻게 이해했는지 알려 준다 (팀 결정 2026-11-23)
    notes = [text("understood_as", written=s.written, station=name(s.ids[0]))
             for s in said.values() if s and not s.exact and len(s.ids) == 1]

    def respond(topic: str, context: Context, route: dict | None = None, options=(), **values) -> dict:
        return _response("route", topic, lang, "\n".join([*notes, text(topic, **values)]), context, route, options=options)

    for slot, other in (("start", "end"), ("end", "start")):
        s = said[slot]
        if s and len(s.ids) > 1:  # 후보가 여럿이면 어느 역인지 묻는다. 다른 쪽 역은 기억해 둔다
            kept = said[other].ids[0] if said[other] and len(said[other].ids) == 1 else before[other]
            return respond("choose_station", Context(**{other: kept}, criteria=criteria, asked=slot),
                           options=[station_ref(network, i, lang) for i in s.ids], written=s.written)

    start = said["start"].ids[0] if said["start"] else before["start"]
    end = said["end"].ids[0] if said["end"] else before["end"]
    if start is None and end is None:
        return respond("ask_both", Context(criteria=criteria, asked="end"))
    if start is None:
        return respond("ask_start", Context(end=end, criteria=criteria, asked="start"), end=name(end))
    if end is None:
        return respond("ask_end", Context(start=start, criteria=criteria, asked="end"), start=name(start))
    if start == end:
        return respond("same_station", Context(start=start, criteria=criteria, asked="end"), station=name(start))

    context = Context(start=start, end=end, criteria=criteria)
    try:
        route = compute_route(network, RouteRequest(start_station_id=start, end_station_id=end,
                                                    criteria=criteria, lang=lang))
    except AppError as e:
        if e.code != "NO_ROUTE":
            raise
        return respond("no_route", context)
    return respond("result", context, route, start=route["start"]["name"], end=route["end"]["name"],
                   minutes=round(route["total_sec"] / 60), transfers=route["transfer_count"],
                   criteria=text("criteria_" + criteria))
