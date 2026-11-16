"""GET /stations — 역 목록 (docs/api-spec.md 1장)."""

from fastapi import APIRouter, Request

from app.api.common import check_lang, station_ref

router = APIRouter()


@router.get("/stations")
def list_stations(lang: str, request: Request) -> dict:
    check_lang(lang)
    network = request.app.state.network

    # 노선도의 노드는 (역, 노선) 튜플이다. 역마다 지나는 노선을 모은다.
    lines: dict[str, list[int]] = {}
    for station, line in network.adjacency:
        lines.setdefault(station, []).append(line)

    return {
        "stations": [
            {**station_ref(network, station, lang), "lines": sorted(lines[station])}
            for station in sorted(network.names)  # 역 ID 오름차순 (모두 세 자리라 문자열 정렬로 충분)
        ]
    }
