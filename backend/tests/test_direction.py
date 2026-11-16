"""방면은 이동 구간의 다음 역이며 최단 경로의 기준을 바꾸지 않는다."""
import unittest
from pathlib import Path
from app.routing.dijkstra import find_route
from app.routing.graph_builder import Network, load_network
from app.routing.models import Edge
from app.routing.meeting import find_meeting_stations


class DirectionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.network = load_network(Path(__file__).resolve().parents[2] / "data")

    def test_first_boarding_and_transfer(self):
        route = find_route(self.network, "101", "207", "time")
        self.assertEqual([s.direction for s in route.segments], ["123", "304"])
        self.assertEqual((route.total_sec, len(route.transfers)), (2510, 1))

    def test_reverse(self):
        route = find_route(self.network, "207", "101", "time")
        self.assertEqual([s.direction for s in route.segments], ["301", "101"])

    def test_minimum_transfers(self):
        route = find_route(self.network, "101", "207", "transfers")
        self.assertEqual([s.direction for s in route.segments], ["201"])
        self.assertEqual((route.total_sec, len(route.transfers)), (3200, 0))

    def test_circular_boundary_both_directions(self):
        # 실제 1·6호선의 끝↔처음 연결만 추출해 경계 이동을 분리 검사한다.
        for line, first, last in ((1, "101", "123"), (6, "601", "622")):
            a, b = (first, line), (last, line)
            edge = next(e for e in self.network.adjacency[a] if e.target == b)
            network = Network({a: [edge], b: [Edge(a, edge.seconds)]},
                              {s: self.network.names[s] for s in (first, last)})
            for start, end in ((first, last), (last, first)):
                self.assertEqual(find_route(network, start, end, "time").segments[0].direction, end)

    def test_same_station_has_no_boarding(self):
        self.assertEqual(find_route(self.network, "101", "101", "time").segments, [])

    def test_meeting_all_modes_and_zero_trip(self):
        for result in find_meeting_stations(self.network, ["101", "101", "207"]).values():
            for participant in result.participants:
                for segment in participant.segments:
                    self.assertEqual(segment.direction, segment.stations[1])
                if participant.start == result.station:
                    self.assertEqual(participant.segments, [])


if __name__ == "__main__":
    unittest.main()
