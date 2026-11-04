import csv
import tempfile
import unittest
from pathlib import Path
from backend.app.routing.graph_builder import build_graph, read_times
from backend.app.routing.dijkstra import find_route, NoRouteError, UnknownStationError

DATA = Path(__file__).resolve().parents[2] / "data"

class RoutingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(dir=Path(__file__).parent)
        folder = Path(cls.tmp.name)
        def read(name):
            with (DATA / "extra" / name).open(encoding="utf-8") as f:
                return list(csv.DictReader(f))
        def write(name, rows, fields=None):
            with (folder / name).open("w", encoding="utf-8", newline="") as f:
                writer = csv.DictWriter(f, fieldnames=fields or list(rows[0]))
                writer.writeheader()
                writer.writerows(rows)
        # Actual consecutive slices: line 1, 112..119; line 9, 112..119.
        # The slice is open, so closure flags and sequence offsets are fixture metadata.
        rows = []
        for r in read("line_stations.csv"):
            if r["line"] == "1" and 12 <= int(r["seq"]) <= 19:
                rows.append(dict(r, seq=str(int(r["seq"]) - 11)))
            elif r["line"] == "9" and int(r["seq"]) <= 6:
                rows.append(r)
        rows.append({"line": "2", "seq": "1", "station": "101"})
        write("line_stations.csv", rows)
        write("lines.csv", [{"line": str(l), "is_circular": "0"} for l in (1, 9, 2)])
        ids = {r["station"] for r in rows}
        write("station_names.csv", [r for r in read("station_names.csv") if r["station"] in ids])
        write("transfers.csv", [r for r in read("transfers.csv")
              if r["station"] in ("112", "119") and r["line_a"] == "1" and r["line_b"] == "9"])
        raw = read_times(DATA / "raw" / "stations.xlsx")
        pairs = set()
        for line in ("1", "9"):
            ss = [int(r["station"]) for r in rows if r["line"] == line]
            pairs.update(tuple(sorted((a, b))) for a, b in zip(ss, ss[1:]))
        cls.times = {k: raw[k] for k in pairs}
        cls.folder = folder
        cls.graph = build_graph(folder, cls.times)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_same_line(self):
        r = find_route(self.graph, 113, 115)
        self.assertEqual((r.stations, r.total_seconds, r.transfer_count), ([113, 114, 115], 720, 0))

    def test_one_transfer(self):
        r = find_route(self.graph, 901, 118)
        self.assertEqual((r.stations, r.total_seconds, r.transfer_count),
                         ([901, 406, 605, 902, 119, 118], 2200, 1))
        self.assertEqual(r.transfers[0].station, 119)
        self.assertEqual([s.line for s in r.segments], [9, 9, 9, 9, 1])

    def test_shorter_alternative(self):
        r = find_route(self.graph, 112, 119)
        self.assertEqual((r.total_seconds, r.transfer_count), (2020, 0))
        self.assertEqual(r.stations, [112, 901, 406, 605, 902, 119])

    def test_objectives_differ(self):
        fast = find_route(self.graph, 112, 118)
        few = find_route(self.graph, 112, 118, "fewest_transfers")
        self.assertEqual((fast.total_seconds, fast.transfer_count), (2800, 1))
        self.assertEqual((few.total_seconds, few.transfer_count), (3750, 0))

    def test_equal_transfers_choose_time(self):
        r = find_route(self.graph, 112, 119, "fewest_transfers")
        self.assertEqual((r.total_seconds, r.transfer_count), (2020, 0))

    def test_same_station(self):
        self.assertEqual(find_route(self.graph, 112, 112).to_dict(),
                         dict(origin=112, destination=112, total_seconds=0,
                              transfer_count=0, stations=[112], segments=[], transfers=[]))

    def test_unknown(self):
        for a, b in [(999, 112), (112, 999), (999, 999)]:
            with self.assertRaises(UnknownStationError):
                find_route(self.graph, a, b)

    def test_disconnected(self):
        with self.assertRaises(NoRouteError):
            find_route(self.graph, 101, 112)

    def test_missing_time_rejected(self):
        with self.assertRaises(ValueError):
            build_graph(self.folder, {k:v for k,v in self.times.items() if k != (112,113)})


    def test_reverse_route(self):
        r = find_route(self.graph, 118, 112)
        self.assertEqual((r.total_seconds, r.transfer_count), (2800, 1))
        self.assertEqual((r.transfers[0].from_line, r.transfers[0].to_line), (1, 9))

    def altered_graph(self, filename, transform):
        import shutil
        with tempfile.TemporaryDirectory(dir=self.folder) as tmp:
            target = Path(tmp)
            for source in self.folder.glob("*.csv"):
                shutil.copyfile(source, target / source.name)
            p = target / filename
            p.write_text(transform(p.read_text(encoding="utf-8")), encoding="utf-8")
            return build_graph(target, self.times)

    def test_duplicate_transfer_reversed(self):
        with self.assertRaisesRegex(ValueError, "duplicate transfer"):
            self.altered_graph("transfers.csv", lambda s: s + "112,9,1,300\n")

    def test_missing_transfer(self):
        with self.assertRaisesRegex(ValueError, "Missing transfer"):
            self.altered_graph("transfers.csv", lambda s: "\n".join(s.splitlines()[:2]) + "\n")

    def test_unknown_line_reference(self):
        with self.assertRaisesRegex(ValueError, "Unknown line"):
            self.altered_graph("line_stations.csv", lambda s: s.replace("2,1,101", "99,1,101"))

    def test_invalid_csv_fields(self):
        for suffix in ("112,1,9\n", "112,1,9,300,unexpected\n"):
            with self.subTest(suffix=suffix), self.assertRaisesRegex(ValueError, "CSV fields"):
                self.altered_graph("transfers.csv", lambda s: s + suffix)

    def test_non_circular_has_no_closing_edge(self):
        self.assertFalse(any(e.target == (119,1) for e in self.graph.adjacency[112,1]))

    def test_actual_circular_lines(self):
        # Separate small fixtures of each actual circular line, preserving all its
        # original CSV rows and actual closing-edge time.
        for line, first, last in ((1,101,123), (6,601,622)):
            with self.subTest(line=line), tempfile.TemporaryDirectory(dir=self.folder) as tmp:
                target = Path(tmp)
                def read(name):
                    with (DATA / "extra" / name).open(encoding="utf-8") as f:
                        return list(csv.DictReader(f))
                selected = [r for r in read("line_stations.csv") if int(r["line"]) == line]
                ids = {int(r["station"]) for r in selected}
                for name, rows, fields in [
                    ("line_stations.csv", selected, ["line","seq","station"]),
                    ("lines.csv", [r for r in read("lines.csv") if int(r["line"]) == line], ["line","is_circular"]),
                    ("station_names.csv", [r for r in read("station_names.csv") if int(r["station"]) in ids], ["station","name_ko","name_en"]),
                    ("transfers.csv", [], ["station","line_a","line_b","transfer_sec"]),
                ]:
                    with (target/name).open("w",encoding="utf-8",newline="") as f:
                        writer = csv.DictWriter(f,fieldnames=fields)
                        writer.writeheader()
                        writer.writerows(rows)
                stations = [int(r["station"]) for r in selected]
                pairs = list(zip(stations,stations[1:])) + [(last,first)]
                raw = read_times(DATA/"raw"/"stations.xlsx")
                times = {tuple(sorted(pair)):raw[tuple(sorted(pair))] for pair in pairs}
                graph = build_graph(target,times)
                seconds = raw[tuple(sorted((first,last)))]
                for a,b in ((first,last),(last,first)):
                    self.assertTrue(any(e.target == (b,line) and e.seconds == seconds and not e.transfer
                                        for e in graph.adjacency[a,line]))

    def test_xlsx_empty_formula_and_inline_strings(self):
        import zipfile
        import xml.etree.ElementTree as ET
        source = DATA/"raw"/"stations.xlsx"
        ns = {"s":"http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
        with zipfile.ZipFile(source) as z:
            original = {name:z.read(name) for name in z.namelist()}
        for case in ("empty","formula","inline","missing"):
            with self.subTest(case=case), tempfile.TemporaryDirectory(dir=self.folder) as tmp:
                sheet = ET.fromstring(original["xl/worksheets/sheet1.xml"])
                data = sheet.find("s:sheetData",ns)
                if case == "empty":
                    data.clear()
                elif case == "formula":
                    cell = data[1][2]
                    cell.clear()
                    cell.set("r","C2")
                    ET.SubElement(cell, "{"+ns["s"]+"}f").text = "100+100"
                elif case == "missing":
                    data[1].remove(data[1][2])
                else:
                    strings = ["".join(e.itertext()) for e in ET.fromstring(original["xl/sharedStrings.xml"])]
                    for cell in data[0]:
                        v = cell.find("s:v",ns)
                        text = strings[int(v.text)]
                        cell.remove(v)
                        cell.set("t","inlineStr")
                        ET.SubElement(ET.SubElement(cell,"{"+ns["s"]+"}is"),"{"+ns["s"]+"}t").text = text
                dest = Path(tmp)/"case.xlsx"
                with zipfile.ZipFile(dest,"w") as z:
                    for name,blob in original.items():
                        z.writestr(name,ET.tostring(sheet) if name=="xl/worksheets/sheet1.xml" else blob)
                if case == "inline":
                    self.assertEqual(read_times(dest),read_times(source))
                else:
                    with self.assertRaises(ValueError):
                        read_times(dest)

if __name__ == "__main__":
    unittest.main()
