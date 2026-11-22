"""SubFit 나노 의도 판단기 — 직접 만든 작은 모델(C++, CPU)이 "무엇을 묻는지"를 고른다. 외부 AI는 부르지 않는다.

    1. 규칙(rules.py): 개인정보 가리기 → 문장 속 역 찾기(오타 포함)·출발/도착 나누기 → 언어 고르기 → 역 자리를 ◆로
    2. 모델(subfit_nano.cpp + subfit_nano.bin): ◆가 들어간 문장 → 의도 26가지 · 기준 · 흐름 (문장 하나에 수 ms)
    3. 여기서 service.py가 쓰는 모양(Answer)으로 바꾼다

모델은 답 문장을 만들지 않는다. 답은 서버가 계산한 값과 data/chat/의 고정 문구로만 만든다.
모델 다시 만들기(학습)는 docs/chatbot.md를 본다.
"""

import os
import platform
import re
import subprocess
import threading
from dataclasses import dataclass, field
from pathlib import Path

from app.chat import settings
from app.chat.nano import rules
from app.routing.graph_builder import Network

HERE = Path(__file__).resolve().parent
MODEL_FILE = HERE / "subfit_nano.bin"


class NanoUnavailable(Exception):
    """실행기를 띄울 수 없거나, 시간 안에 답하지 않거나, 답 모양이 틀림."""


@dataclass
class StationName:
    written: str              # 사용자가 쓴 글자
    guess: str | None = None  # (지금은 쓰지 않음. 다른 글자로 옮겨 적은 이름 자리)


@dataclass
class Answer:
    """service.py가 쓰는 이해 결과."""

    intent: str                       # route faq phrase help emergency out_of_scope greet thanks
    lang: str | None = None           # 사용자가 쓴 언어 (모르면 None, 지원하지 않는 언어면 other)
    kind: str | None = None           # out_of_scope 종류
    start: StationName | None = None
    end: StationName | None = None
    station: StationName | None = None
    criteria: str | None = None       # time · transfers · None(말 안 함)
    follow_up: bool = False
    reverse: bool = False
    faq_id: str | None = None
    phrase_id: str | None = None
    line: int | None = None
    confidence: float = 1.0
    labels: dict = field(default_factory=dict)  # 모델이 고른 라벨 그대로 (확인용)


# 모델 라벨 → 서버 의도
_EMERGENCY_PHRASE = {"emergency_sick": "feel_sick", "emergency_theft": "lost_item"}


def to_answer(labels: dict, mentions: list[rules.Mention], text: str, lang: str | None) -> Answer:
    label, conf = labels["intent"]
    a = Answer(intent="out_of_scope", lang=lang, confidence=conf, labels=labels)
    if conf < settings.NANO_MIN_CONFIDENCE:
        a.kind = "not_understood"  # 확신이 낮으면 아무것도 하지 않고 되묻는다
        return a
    if label == "route":
        a.intent = "route"
        a.criteria = labels["criteria"][0] if labels["criteria"][0] != "none" else None
        a.follow_up = labels["flow"][0] in ("follow", "reverse")
        a.reverse = labels["flow"][0] == "reverse"
    elif label.startswith("faq_"):
        a.intent, a.faq_id = "faq", label[4:]
    elif label == "phrase_list":
        a.intent = "phrase"
    elif label.startswith("phrase_"):
        a.intent, a.phrase_id = "phrase", label[7:]
    elif label == "help_lost":
        a.intent = "help"
    elif label in _EMERGENCY_PHRASE:
        a.intent, a.phrase_id = "emergency", _EMERGENCY_PHRASE[label]
    elif label.startswith("oos_"):
        a.kind = label[4:]
    elif label in ("greet", "thanks"):
        a.intent = label
    for m in mentions:  # 역할마다 처음 나온 역
        slot = {"start": "start", "end": "end"}.get(m.role, "station")
        if getattr(a, slot) is None:
            setattr(a, slot, StationName(m.written))
    line = re.search(r"(\d)\s*호선|line\s*(\d)|(\d)\s*번\s*(?:라인|선)", text.lower())
    if line:
        a.line = int(next(g for g in line.groups() if g))
    return a


# 역이 둘(출발·도착) 잡혔는데 이 의도라고 하면 길찾기로 바로잡는다 ("kinda confused but I need A to B")
_TWO_STATIONS_MEAN_ROUTE = {"help_lost", "phrase_which_side", "oos_real_seoul", "oos_unrelated", "faq_help_desk", "faq_direction_sign"}


def understand(network: Network, text: str) -> Answer:
    """사용자 메시지 하나 → Answer. 실행기가 안 되면 NanoUnavailable."""
    mentions = rules.find_mentions(network, text)
    lang = rules.detect_lang(text, mentions)
    model_text = rules.model_text(text, mentions)
    labels = fix_labels(_runner().ask(model_text), model_text, mentions)
    return to_answer(labels, mentions, text, lang)


def fix_labels(labels: dict, model_text: str, mentions: list[rules.Mention]) -> dict:
    """모델 판단 위에 확실한 규칙을 얹는다.
    - 기준: "환승 없이"(⑳)·"빨리"(㉑) 힌트가 있으면 힌트대로. 둘 다 있으면 환승 적게를 말한 쪽이 우선
    - 흐름: "반대로"(㉓) 힌트가 있고 역이 둘 다 나오지 않았으면 반대로
    - 의도: 출발역·도착역이 둘 다 잡혔으면 길찾기
    """
    labels = dict(labels)
    roles = {m.role for m in mentions}
    if labels["intent"][0] in _TWO_STATIONS_MEAN_ROUTE and {"start", "end"} <= roles:
        labels["intent"] = ("route", 1.0)
    if "⑳" in model_text:
        labels["criteria"] = ("transfers", 1.0)
    elif "㉑" in model_text:
        labels["criteria"] = ("time", 1.0)
    if "㉓" in model_text and not {"start", "end"} <= roles:
        labels["flow"] = ("reverse", 1.0)
    return labels


# ───────────────────────── C++ 실행기 ─────────────────────────

def binary_path() -> Path:
    """이 컴퓨터에 맞는 실행기. bin/ 에 미리 빌드해 둔 것을 쓴다 (없으면 subfit_nano.cpp로 빌드: docs/chatbot.md)."""
    system = platform.system().lower()            # linux · windows · darwin
    machine = platform.machine().lower()
    arch = {"amd64": "x86_64", "x64": "x86_64", "arm64": "aarch64"}.get(machine, machine)
    os_name = {"darwin": "macos"}.get(system, system)
    name = f"subfit_nano-{os_name}-{arch}"
    if system == "windows":
        name += ".exe"
    custom = os.getenv("SUBFIT_NANO_BIN", "").strip()  # 직접 빌드한 실행기를 쓰려면 .env에 경로
    return Path(custom) if custom else HERE / "bin" / name


class _Runner:
    """실행기를 한 번 띄워 두고 계속 쓴다. 죽었거나 느리면 다시 띄운다."""

    def __init__(self):
        self.proc: subprocess.Popen | None = None
        self.lock = threading.Lock()

    def _start(self) -> None:
        exe = binary_path()
        if not exe.exists() or not MODEL_FILE.exists():
            raise NanoUnavailable(f"실행기나 모델 파일이 없습니다: {exe.name}")
        flags = 0x08000000 if platform.system() == "Windows" else 0  # 창 띄우지 않기
        try:
            self.proc = subprocess.Popen([str(exe), str(MODEL_FILE)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, creationflags=flags)
        except OSError as e:
            raise NanoUnavailable(f"실행기를 띄울 수 없습니다: {type(e).__name__}") from e

    def ask(self, model_text: str) -> dict:
        with self.lock:
            if self.proc is None or self.proc.poll() is not None:
                self._start()
            result = {}

            def talk():
                try:
                    self.proc.stdin.write((model_text.replace("\n", " ") + "\n").encode("utf-8"))
                    self.proc.stdin.flush()
                    result["line"] = self.proc.stdout.readline().decode("utf-8")
                except (OSError, ValueError):
                    pass

            worker = threading.Thread(target=talk, daemon=True)
            worker.start()
            worker.join(settings.NANO_TIMEOUT_SEC)
            line = result.get("line", "")
            if worker.is_alive() or not line:
                self.close()
                raise NanoUnavailable("실행기가 시간 안에 답하지 않았습니다")
        parts = line.rstrip("\n").split("\t")
        try:
            return {"intent": (parts[0], float(parts[1])), "criteria": (parts[2], float(parts[3])),
                    "flow": (parts[4], float(parts[5]))}
        except (IndexError, ValueError) as e:
            raise NanoUnavailable("실행기 답의 모양이 틀립니다") from e

    def close(self) -> None:
        if self.proc is not None:
            try:
                self.proc.kill()
            except OSError:
                pass
        self.proc = None


_shared: _Runner | None = None


def _runner() -> _Runner:
    global _shared
    if _shared is None:
        _shared = _Runner()
    return _shared
