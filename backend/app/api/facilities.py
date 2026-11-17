"""GET /stations/{station_id}/facilities — 역 주변 시설 (AI가 만든 예시, docs/api-spec.md 4-1장)."""

from fastapi import APIRouter, Request

from app.ai.facilities import facilities

router = APIRouter()


@router.get("/stations/{station_id}/facilities")
def station_facilities(station_id: str, lang: str, request: Request) -> dict:
    """lang: ko, en, ja, zh-Hans, zh-Hant, vi. 없으면 422 INVALID_REQUEST."""
    return facilities(request.app.state.network, station_id, lang)
