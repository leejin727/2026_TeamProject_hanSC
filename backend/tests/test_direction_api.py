"""DB·AI나 HTTP 서버 없이 실제 API 응답 변환을 검사한다."""
import unittest
from pathlib import Path
from types import SimpleNamespace
from app.routing.graph_builder import load_network
from app.api.routes import RouteRequest, compute_route
from app.api.meeting import MeetingRequest, calculate_meeting_station


class DirectionApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.network = load_network(Path(__file__).resolve().parents[2] / "data")

    def test_route_localized_direction(self):
        for lang, names in (("ko", ["압구정", "신사"]), ("en", ["Apgujeong", "Sinsa"])):
            result = compute_route(self.network, RouteRequest(
                start_station_id="101", end_station_id="207", criteria="time", lang=lang))
            self.assertEqual([s["direction"]["name"] for s in result["segments"]], names)
            for segment in result["segments"]:
                self.assertEqual(segment["direction"], segment["stations"][1])

    def test_meeting_localized_direction(self):
        request = SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(network=self.network)))
        for lang in ("ko", "en"):
            for criterion in ("time", "transfers", "fairness"):
                result = calculate_meeting_station(MeetingRequest(
                    start_station_ids=["101", "101", "207"], criteria=criterion, lang=lang), request)
                for participant in result["participants"]:
                    for segment in participant["segments"]:
                        self.assertEqual(segment["direction"], segment["stations"][1])


if __name__ == "__main__":
    unittest.main()
