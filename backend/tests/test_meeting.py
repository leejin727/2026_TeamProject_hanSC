import itertools
import unittest
from unittest.mock import patch
from pathlib import Path
from app.routing.graph_builder import Network, load_network
from app.routing.models import Edge
from app.routing.dijkstra import search, find_route, UnknownStationError
from app.routing import meeting
from app.routing.meeting import find_meeting_station, find_meeting_stations, NoMeetingStationError, InvalidParticipantCountError

def graph(edges, isolated=()):
    adjacency = {n: [] for n in isolated}
    for a,b,seconds,transfer in edges:
        adjacency.setdefault(a,[]).append(Edge(b,seconds,transfer))
        adjacency.setdefault(b,[]).append(Edge(a,seconds,transfer))
    return Network(adjacency, {n[0]:(n[0],n[0]) for n in adjacency})

def line():
    return graph([(("1",1),("2",1),10,False), (("2",1),("3",1),10,False)])

def exhaustive_records(network, start, mode):
    # 작은 그래프에서 모든 단순 노드 경로를 열거하는 독립 검증.
    best = {}
    def visit(node, seen, seconds, transfers):
        record = (transfers,seconds) if mode=="transfers" else (seconds,transfers)
        station = node[0]
        if station not in best or record < best[station]:
            best[station] = record
        for edge in network.adjacency[node]:
            if edge.target not in seen:
                visit(edge.target,seen|{edge.target},seconds+edge.seconds,transfers+int(edge.transfer))
    for node in network.adjacency:
        if node[0]==start:
            visit(node,{node},0,0)
    return {s:(r[::-1] if mode=="transfers" else r) for s,r in best.items()}

class MeetingTests(unittest.TestCase):
    def test_total_time_and_origin_zero(self):
        r = find_meeting_station(line(),["1","3"],"time")
        self.assertEqual((r.station,r.total_travel_sec,r.total_transfer_count),("1",20,0))
        self.assertEqual((r.participants[0].travel_sec,r.participants[0].stations),(0,["1"]))

    def test_fairness_minimax(self):
        r = find_meeting_station(line(),["1","3"],"fairness")
        self.assertEqual((r.station,r.max_travel_sec,r.total_travel_sec),("2",10,20))

    def test_duplicate_participants_and_cache(self):
        with patch.object(meeting,"search",wraps=search) as spy:
            results = find_meeting_stations(line(),["1","1","3"])
            self.assertEqual(spy.call_count,4)  # 2개의 출발역 × 2개의 탐색 모드
        r=results["time"]
        self.assertEqual(r.station,"1")
        self.assertEqual([p.start for p in r.participants],["1","1","3"])
        self.assertEqual(r.total_travel_sec,20)
        self.assertIsNot(r.participants[0].stations,r.participants[1].stations)

    def test_single_criterion_search_count(self):
        for c in meeting.CRITERIA:
            with patch.object(meeting,"search",wraps=search) as spy:
                find_meeting_station(line(),["1","1","3"],c)
                self.assertEqual(spy.call_count,2)

    def test_numeric_tie_break(self):
        n=graph([(("10",1),("2",1),5,False)])
        for c in meeting.CRITERIA:
            self.assertEqual(find_meeting_station(n,["10","2"],c).station,"2")

    def test_score_priorities(self):
        # 보고서의 X/Y 예시 및 모든 2차 비교를 독립된 명시 값으로 확인.
        self.assertLess(meeting._score("time",[(600,0),(1200,0),(3000,0)],"10"),
                        meeting._score("time",[(1500,0),(1800,0),(2100,0)],"20"))
        self.assertGreater(meeting._score("fairness",[(600,0),(1200,0),(3000,0)],"10"),
                           meeting._score("fairness",[(1500,0),(1800,0),(2100,0)],"20"))
        self.assertLess(meeting._score("fairness",[(10,0),(1,0)],"20"),
                        meeting._score("fairness",[(10,0),(9,0)],"10"))
        self.assertLess(meeting._score("transfers",[(1000,0),(1000,0)],"20"),
                        meeting._score("transfers",[(1,1),(1,0)],"10"))
        self.assertLess(meeting._score("transfers",[(10,1),(5,0)],"20"),
                        meeting._score("transfers",[(10,0),(6,1)],"10"))

    def test_validation(self):
        for starts in ([],["1"],["1"]*5):
            with self.assertRaises(InvalidParticipantCountError):
                find_meeting_station(line(),starts,"time")
        for starts in ([1,"3"],[True,"3"],["999","3"],[None,"3"]):
            with self.assertRaises(UnknownStationError):
                find_meeting_station(line(),starts,"time")
        for starts in ("13",None,{"1","3"}):
            with self.assertRaises(ValueError):
                find_meeting_station(line(),starts,"time")
        with self.assertRaises(ValueError):
            find_meeting_station(line(),["1","3"],"wrong")

    def test_disconnected(self):
        n=graph([], [("1",1),("2",2)])
        with self.assertRaises(NoMeetingStationError):
            find_meeting_station(n,["1","2"],"fairness")

    def test_same_starts(self):
        for c in meeting.CRITERIA:
            r=find_meeting_station(line(),["2"]*4,c)
            self.assertEqual((r.station,r.total_travel_sec,r.total_transfer_count),("2",0,0))

    def test_multiple_start_and_end_lines(self):
        n=graph([(("1",1),("9",1),100,False),
                 (("1",2),("9",2),2,False),
                 (("3",3),("9",3),3,False)])
        r=find_meeting_station(n,["1","3"],"time")
        self.assertEqual((r.station,r.total_travel_sec,r.total_transfer_count),("9",5,0))
        self.assertEqual([p.segments[0].line for p in r.participants],[2,3])

    def test_exhaustive_small_graph_all_candidates(self):
        n=graph([(("1",1),("2",1),20,False),(("2",1),("3",1),20,False),
                 (("1",2),("4",2),2,False),(("4",2),("4",3),7,True),
                 (("4",3),("3",3),2,False),(("2",1),("2",4),11,True),
                 (("2",4),("5",4),1,False)])
        for starts in itertools.product(["1","2","3","5"],repeat=3):
            for c in meeting.CRITERIA:
                mode="transfers" if c=="transfers" else "time"
                records=[exhaustive_records(n,s,mode) for s in starts]
                scores={}
                for station in n.names:
                    if all(station in r for r in records):
                        ts=[r[station][0] for r in records]
                        xs=[r[station][1] for r in records]
                        scores[station]=((sum(ts),int(station)) if c=="time" else
                                         (sum(xs),sum(ts),int(station)) if c=="transfers" else
                                         (max(ts),sum(ts),int(station)))
                r=find_meeting_station(n,list(starts),c)
                self.assertEqual(r.station,min(scores,key=scores.get))
                for p,expected in zip(r.participants,records):
                    self.assertEqual((p.travel_sec,p.transfer_count),expected[r.station])
                    self.assertEqual(p.travel_sec,sum(s.ride_sec for s in p.segments)+sum(t.sec for t in p.transfers))

    def test_actual_network_modes_and_no_fare(self):
        n=load_network(Path(__file__).resolve().parents[2]/"data")
        self.assertEqual({e.seconds for es in n.adjacency.values() for e in es if e.transfer},{300})
        self.assertNotEqual(find_route(n,"101","207","time").total_sec,
                            find_route(n,"101","207","transfers").total_sec)
        for starts in (["101","101","207"],["101","416","805"],["112","118"]):
            for c in meeting.CRITERIA:
                r=find_meeting_station(n,starts,c)
                mode="transfers" if c=="transfers" else "time"
                candidates={}
                for station in n.names:
                    routes=[find_route(n,s,station,mode) for s in starts]
                    ts=[x.total_sec for x in routes]
                    xs=[len(x.transfers) for x in routes]
                    candidates[station]=((sum(ts),int(station)) if c=="time" else
                                         (sum(xs),sum(ts),int(station)) if c=="transfers" else
                                         (max(ts),sum(ts),int(station)))
                self.assertEqual(r.station,min(candidates,key=candidates.get))
                self.assertNotIn("cost_won",str(r.to_dict()))
                for p in r.participants:
                    expected=find_route(n,p.start,r.station,mode)
                    self.assertEqual((p.travel_sec,p.transfer_count),(expected.total_sec,len(expected.transfers)))

    def test_transfer_recommendation_uses_min_transfer_records(self):
        n=load_network(Path(__file__).resolve().parents[2]/"data")
        result=find_meeting_stations(n,["101","101","207"])
        self.assertEqual((result["time"].station,result["time"].total_travel_sec,result["time"].total_transfer_count),
                         ("101",2510,1))
        self.assertEqual((result["transfers"].station,result["transfers"].total_travel_sec,result["transfers"].total_transfer_count),
                         ("123",2690,0))
        self.assertEqual((result["fairness"].station,result["fairness"].max_travel_sec),("303",1430))

    def test_meeting_never_reads_fares(self):
        class FarelessEdge:
            def __init__(self,target):
                self.target=target
                self.seconds=10
                self.transfer=False
            @property
            def cost_won(self):
                raise AssertionError("Meeting must not read a fare")
        n=Network({("1",1):[FarelessEdge(("2",1))],("2",1):[FarelessEdge(("1",1))]},
                  {"1":("가","A"),"2":("나","B")})
        self.assertEqual(find_meeting_station(n,["1","2"],"time").total_travel_sec,10)
