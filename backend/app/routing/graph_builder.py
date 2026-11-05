"""Read the project's unchanged CSV files and original XLSX, using stdlib only."""
import csv
import itertools
import xml.etree.ElementTree as ET
import zipfile
from dataclasses import dataclass
from pathlib import Path
from .models import Edge, Node, StationId

@dataclass
class Network:
    adjacency: dict[Node, list[Edge]]
    names: dict[StationId, tuple[str, str]]

def station_id(value):
    """역 번호를 문자열 ID로 바꾼다. "101", 101 → "101". 숫자가 아니면 ValueError."""
    return str(int(value))

def read_csv(path, expected):
    with Path(path).open(encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != expected:
            raise ValueError(f"{path}: unexpected columns {reader.fieldnames}")
        rows = list(reader)
        for number, row in enumerate(rows, start=2):
            if None in row or any(value is None or not value.strip() for value in row.values()):
                raise ValueError(f"{path}:{number}: missing or extra CSV fields")
        return rows

def read_edges(path):
    """원본 엑셀에서 구간을 읽는다. 결과: {(역 ID, 역 ID): (시간 초, 비용 원)}. 거리는 쓰지 않는다."""
    # The supplied workbook has one worksheet. Resolve its actual relationship.
    ns = {"s": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    with zipfile.ZipFile(path) as z:
        workbook = ET.fromstring(z.read("xl/workbook.xml"))
        sheets = workbook.findall("s:sheets/s:sheet", ns)
        if len(sheets) != 1:
            raise ValueError("Expected one source worksheet")
        rid = sheets[0].get("{http://schemas.openxmlformats.org/officeDocument/2006/relationships}id")
        rels = ET.fromstring(z.read("xl/_rels/workbook.xml.rels"))
        target = next(r.get("Target") for r in rels if r.get("Id") == rid)
        target = target.lstrip("/") if target.startswith("/") else "xl/" + target
        strings = []
        if "xl/sharedStrings.xml" in z.namelist():
            strings = ["".join(e.itertext()) for e in ET.fromstring(z.read("xl/sharedStrings.xml"))]
        rows = []
        for row in ET.fromstring(z.read(target)).findall("s:sheetData/s:row", ns):
            values = {}
            for cell in row:
                if cell.find("s:f", ns) is not None:
                    raise ValueError("Formula cells are not supported in source data")
                v = cell.find("s:v", ns)
                if cell.get("t") == "inlineStr":
                    value = "".join(t.text or "" for t in cell.findall("s:is//s:t", ns))
                elif v is None:
                    continue
                else:
                    value = strings[int(v.text)] if cell.get("t") == "s" else v.text
                column = "".join(c for c in cell.get("r") if c.isalpha())
                values[column] = value
            if values:
                rows.append([values.get(c) for c in "ABCDE"])
    if not rows:
        raise ValueError("Source worksheet is empty")
    if rows[0] != ["출발역", "도착역", "시간(초)", "거리(미터)", "비용(원)"]:
        raise ValueError(f"Unexpected workbook headers: {rows[0]}")
    edges = {}
    for a, b, seconds, distance, fare in rows[1:]:
        try:
            a, b, seconds, distance, fare = map(int, (a, b, seconds, distance, fare))
        except (TypeError, ValueError) as exc:
            raise ValueError("Source edge must contain five integer values") from exc
        key = tuple(sorted((station_id(a), station_id(b))))
        if a == b or min(seconds, distance, fare) <= 0 or key in edges:
            raise ValueError(f"Invalid or duplicate source edge: {key}")
        edges[key] = (seconds, fare)
    return edges

def build_graph(extra_dir, edges):
    extra_dir = Path(extra_dir)
    lines = {}
    for r in read_csv(extra_dir / "lines.csv", ["line", "is_circular"]):
        line, circular = int(r["line"]), int(r["is_circular"])
        if line in lines or circular not in (0, 1):
            raise ValueError("Invalid or duplicate line")
        lines[line] = circular
    names = {}
    for r in read_csv(extra_dir / "station_names.csv", ["station", "name_ko", "name_en"]):
        station = station_id(r["station"])
        if station in names or not r["name_ko"] or not r["name_en"]:
            raise ValueError("Invalid or duplicate station name record")
        names[station] = (r["name_ko"], r["name_en"])
    orders = {line: {} for line in lines}
    adjacency = {}
    membership = {}
    for r in read_csv(extra_dir / "line_stations.csv", ["line", "seq", "station"]):
        line, seq, station = int(r["line"]), int(r["seq"]), station_id(r["station"])
        if line not in lines or station not in names:
            raise ValueError("Unknown line or station reference")
        if seq in orders[line] or (station, line) in adjacency:
            raise ValueError("Duplicate sequence or station within a line")
        orders[line][seq] = station
        adjacency[station, line] = []
        membership.setdefault(station, set()).add(line)
    if set(names) != set(membership):
        raise ValueError("Station names and membership disagree")

    def connect(a, b, seconds, cost_won=0, transfer=False):
        if isinstance(seconds, bool) or not isinstance(seconds, int) or seconds <= 0:
            raise ValueError("Travel times must be positive integer seconds")
        adjacency[a].append(Edge(b, seconds, transfer, cost_won))
        adjacency[b].append(Edge(a, seconds, transfer, cost_won))

    used = set()
    for line, ordered in orders.items():
        if not ordered or sorted(ordered) != list(range(1, len(ordered) + 1)):
            raise ValueError("Sequences must start at 1 and be contiguous")
        stations = [ordered[i] for i in sorted(ordered)]
        pairs = list(zip(stations, stations[1:]))
        if lines[line]:
            if len(stations) < 3:
                raise ValueError("Circular line needs at least three stations")
            pairs.append((stations[-1], stations[0]))
        for a, b in pairs:
            key = tuple(sorted((a, b)))
            if key not in edges:
                raise ValueError(f"Missing travel time: {key}")
            if key in used:
                raise ValueError(f"Ambiguous repeated physical segment: {key}")
            used.add(key)
            seconds, cost_won = edges[key]
            connect((a, line), (b, line), seconds, cost_won)
    if used != set(edges):
        raise ValueError("Unused travel-time edges")
    expected = {(s, a, b) for s, ls in membership.items()
                for a, b in itertools.combinations(sorted(ls), 2)}
    seen = set()
    for r in read_csv(extra_dir / "transfers.csv", ["station", "line_a", "line_b", "transfer_sec"]):
        s = station_id(r["station"])
        a, b, seconds = (int(r[k]) for k in ("line_a", "line_b", "transfer_sec"))
        a, b = sorted((a, b))
        key = s, a, b
        if key not in expected or key in seen:
            raise ValueError(f"Invalid or duplicate transfer: {key}")
        seen.add(key)
        connect((s, a), (s, b), seconds, transfer=True)  # 환승은 비용 0원
    if seen != expected:
        raise ValueError("Missing transfer pairs")
    return Network(adjacency, names)

def load_network(data_dir):
    data_dir = Path(data_dir)
    return build_graph(data_dir / "extra", read_edges(data_dir / "raw" / "stations.xlsx"))
