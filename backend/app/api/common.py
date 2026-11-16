"""여러 API가 같이 쓰는 입력 검사와 역 이름 붙이기 (docs/api-spec.md 0·5장)."""

from app.errors import AppError
from app.routing.graph_builder import Network

# 역 이름 데이터(station_names.csv)에 있는 언어.
# 순서가 network.names[역] = (한국어 이름, 영어 이름)의 순서와 같아야 한다.
SUPPORTED_LANGS = ("ko", "en")


def check_lang(lang: str) -> None:
    if lang not in SUPPORTED_LANGS:
        raise AppError(
            400, "UNSUPPORTED_LANGUAGE", f"지원하지 않는 언어입니다: {lang}",
            {"lang": lang, "supported": list(SUPPORTED_LANGS)},
        )


def check_station(network: Network, station_id: str) -> None:
    if station_id not in network.names:
        raise AppError(400, "STATION_NOT_FOUND", f"존재하지 않는 역입니다: {station_id}", {"station_id": station_id})


def station_ref(network: Network, station_id: str, lang: str) -> dict:
    """역 객체 {"id", "name"}. name은 lang에 맞는 이름이다. lang은 check_lang을 통과한 값이어야 한다."""
    return {"id": station_id, "name": network.names[station_id][SUPPORTED_LANGS.index(lang)]}
