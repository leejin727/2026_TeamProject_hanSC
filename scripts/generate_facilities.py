"""역마다 주변 시설 예시를 Gemini로 미리 만들어 data/extra/ai_facilities.json에 저장한다.

실행 (저장소 최상위에서):
    source .venv/bin/activate
    python scripts/generate_facilities.py --lang ko en    # 한국어·영어만
    python scripts/generate_facilities.py                 # 6개 언어 전부

- .env의 GEMINI_FACILITY_API_KEY를 쓴다. 서버의 주변 시설 API와 같은 프롬프트·같은 검사를 쓴다.
- 파일에 이미 있는 역·언어는 건너뛴다. 하나 만들 때마다 바로 저장하므로,
  중간에 멈추거나(Ctrl+C) 사용량 한도에 걸려도 다시 실행하면 이어서 만든다.
- 실패(과부하, 시간 초과, 한글 섞임 등)하면 기다렸다 다시 시도하고, 그래도 안 되면 건너뛴다.
- 만든 파일은 커밋한다. python scripts/load_db.py가 이 파일을 DB(ai_facilities)에 넣는다.
- 왜 파일인가: 캐시 DB는 컴퓨터마다 따로라서, 파일로 공유해야 모두 같은 시설을 보고 Gemini도 한 번만 부른다.
"""

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "backend"))  # 서버의 프롬프트·Gemini 호출·검사를 그대로 쓰기 위해

from app.ai.client import AIUnavailableError  # noqa: E402
from app.ai.facilities import FACILITY_LANGS, generate  # noqa: E402
from app.config import DATA_DIR, MissingSettingError  # noqa: E402
from app.routing.graph_builder import load_network  # noqa: E402

OUTPUT = ROOT / "data/extra/ai_facilities.json"
RETRY_WAITS = (10, 30, 60)  # 실패하면 이만큼(초) 기다렸다 다시 시도. 그래도 안 되면 그 역·언어는 건너뛴다
MAX_FAILS_IN_A_ROW = 3  # 호출 자체가 연속으로 이만큼 실패하면 멈춘다 (하루 사용량 한도나 Gemini 장애일 가능성이 큼)
PAUSE_SEC = 4.0  # 호출 사이에 쉬는 시간. 분당 사용 한도를 넘지 않게


def read_file(path: Path) -> dict:
    """{역 ID: {언어: [시설, …]}}. 파일이 없으면 빈 사전."""
    if not path.exists():
        return {}
    return json.loads(path.read_text(encoding="utf-8"))


def write_file(path: Path, data: dict) -> None:
    """역 번호·언어 순서로 정렬해 저장한다. 순서가 늘 같아서 PR에서 바뀐 부분만 보인다."""
    ordered = {
        sid: {lang: data[sid][lang] for lang in FACILITY_LANGS if lang in data[sid]}
        for sid in sorted(data)
    }
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(ordered, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(path)  # 다 쓴 뒤에 바꿔치기 → 쓰는 도중에 멈춰도 원래 파일이 깨지지 않는다


def make_one(name_ko: str, name_en: str, lang: str) -> list[dict]:
    """한 역·한 언어를 만든다. 다시 시도해도 안 되면 마지막 오류를 그대로 낸다.

    AIUnavailableError: 호출 실패(과부하, 한도, 시간 초과). ValueError: 답이 틀림(한글 섞임 등).
    키가 없으면 MissingSettingError.
    """
    for wait in RETRY_WAITS:
        try:
            return generate(name_ko, name_en, lang)
        except (AIUnavailableError, ValueError) as e:
            print(f"    실패: {str(e)[:150]}")
            print(f"    {wait}초 뒤 다시 시도")
            time.sleep(wait)
    return generate(name_ko, name_en, lang)  # 마지막 시도


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="주변 시설 AI 예시를 미리 만들어 파일에 저장")
    parser.add_argument("--lang", nargs="+", choices=FACILITY_LANGS, default=list(FACILITY_LANGS),
                        help="만들 언어 (기본: 6개 전부)")
    parser.add_argument("--pause", type=float, default=PAUSE_SEC, help=f"호출 사이 쉬는 초 (기본 {PAUSE_SEC})")
    args = parser.parse_args(argv)

    network = load_network(DATA_DIR)
    data = read_file(OUTPUT)
    todo = [(sid, lang) for sid in sorted(network.names) for lang in args.lang
            if lang not in data.get(sid, {})]
    print(f"만들 것 {len(todo)}개 (역 {len(network.names)}개 × 언어 {', '.join(args.lang)} 중 파일에 없는 것)")

    made, skipped, fails_in_a_row = 0, [], 0
    try:
        for i, (sid, lang) in enumerate(todo, 1):
            name_ko, name_en = network.names[sid]
            print(f"[{i}/{len(todo)}] {sid} {name_ko} ({lang})")
            try:
                items = make_one(name_ko, name_en, lang)
            except (AIUnavailableError, ValueError) as e:
                print(f"    실패: {str(e)[:150]} → 건너뜀")
                skipped.append(f"{sid}/{lang}")
                # 답이 틀린 것(ValueError)은 그 역만의 문제라 계속한다. 호출 자체가 계속 실패할 때만 멈춘다
                if isinstance(e, AIUnavailableError):
                    fails_in_a_row += 1
                    if fails_in_a_row >= MAX_FAILS_IN_A_ROW:
                        print(f"❗ 연속 {fails_in_a_row}번 호출이 실패해서 멈춥니다. "
                              "하루 사용량 한도이거나 Gemini 장애일 수 있습니다.")
                        break
            else:
                data.setdefault(sid, {})[lang] = items
                write_file(OUTPUT, data)
                made += 1
                fails_in_a_row = 0
            if i < len(todo):
                time.sleep(args.pause)
    except MissingSettingError as e:
        print(f"❌ {e}")
        return 1
    except KeyboardInterrupt:
        print("\n멈췄습니다.")

    print(f"\n새로 만든 것 {made}개 → {OUTPUT}")
    if skipped:
        print(f"건너뛴 것 {len(skipped)}개: {', '.join(skipped)}")
    left = sum(1 for sid, lang in todo if lang not in data.get(sid, {}))
    if left:
        print(f"남은 것 {left}개. 나중에 같은 명령을 다시 실행하면 이어서 만듭니다.")
        return 1
    print("✅ 모두 만들었습니다. DB에 넣으려면: python scripts/load_db.py")
    return 0


if __name__ == "__main__":
    sys.exit(main())
