import 'package:flutter/material.dart';

class SubwayMapLine {
  const SubwayMapLine({
    required this.number,
    required this.color,
    required this.points,
  });

  final int number;
  final Color color;
  final List<Offset> points;
}

class SubwayMapStation {
  const SubwayMapStation({
    required this.id,
    required this.position,
    required this.lines,
    this.name,
  });

  final String id;
  final Offset position;
  final List<int> lines;
  final String? name;

  bool get isTransfer => lines.length > 1;

  String get label => name ?? id;
}

class SubwayMapData {
  SubwayMapData._();

  // 첨부 이미지의 비율을 유지합니다.
  // 아래 원본 좌표를 4로 나누어 그리기용 좌표로 사용합니다.
  static const Size canvasSize = Size(344, 449.25);

  // 나중에 제공받을 역 이름을 여기에 연결합니다.
  // 예시 형식:
  // '101': '역 이름',
  static const Map<String, String> _stationNames = {};

  static const Map<int, Color> _lineColors = {
    1: Color(0xFF075B9E),
    2: Color(0xFF00A650),
    3: Color(0xFFF17C19),
    4: Color(0xFF00A8CF),
    5: Color(0xFF9D6DAA),
    6: Color(0xFFC98130),
    7: Color(0xFF7E8905),
    8: Color(0xFFE61178),
    9: Color(0xFFB9AF91),
  };

  // 첨부 이미지에서 읽은 역별 위치입니다.
  // 환승역도 번호 하나와 좌표 하나만 사용합니다.
  static const Map<String, Offset> _imagePositions = {
    // 1호선 번호
    '101': Offset(711, 1524),
    '102': Offset(606, 1629),
    '103': Offset(513, 1722),
    '104': Offset(337, 1722),
    '105': Offset(262, 1722),
    '106': Offset(151, 1610),
    '107': Offset(84, 1544),
    '108': Offset(84, 1390),
    '109': Offset(84, 1281),
    '110': Offset(84, 1187),
    '111': Offset(84, 1045),
    '112': Offset(84, 934),
    '113': Offset(84, 788),
    '114': Offset(179, 692),
    '115': Offset(337, 692),
    '116': Offset(469, 692),
    '117': Offset(535, 758),
    '118': Offset(644, 867),
    '119': Offset(711, 934),
    '120': Offset(711, 1073),
    '121': Offset(711, 1175),
    '122': Offset(711, 1281),
    '123': Offset(711, 1431),

    // 2호선 번호
    '201': Offset(829, 1524),
    '202': Offset(945, 1524),
    '203': Offset(1012, 1591),
    '204': Offset(1088, 1667),
    '205': Offset(1177, 1667),
    '206': Offset(1299, 1544),
    '207': Offset(1299, 1431),
    '208': Offset(1299, 1352),
    '209': Offset(1299, 1281),
    '210': Offset(1299, 1154),
    '211': Offset(1299, 934),
    '212': Offset(1299, 831),
    '213': Offset(1299, 714),
    '214': Offset(1299, 598),
    '215': Offset(1299, 488),
    '216': Offset(1299, 357),
    '217': Offset(1299, 262),

    // 3호선 번호
    '301': Offset(1171, 1431),
    '302': Offset(1086, 1431),
    '303': Offset(945, 1431),
    '304': Offset(821, 1431),
    '305': Offset(599, 1544),
    '306': Offset(476, 1544),
    '307': Offset(337, 1544),
    '308': Offset(204, 1544),

    // 4호선 번호
    '401': Offset(337, 1619),
    '402': Offset(337, 1380),
    '403': Offset(337, 1281),
    '404': Offset(337, 1133),
    '405': Offset(337, 1027),
    '406': Offset(337, 934),
    '407': Offset(337, 798),
    '408': Offset(337, 534),
    '409': Offset(400, 470),
    '410': Offset(400, 315),
    '411': Offset(485, 231),
    '412': Offset(609, 231),
    '413': Offset(706, 231),
    '414': Offset(864, 231),
    '415': Offset(960, 231),
    '416': Offset(1086, 357),
    '417': Offset(1187, 357),

    // 5호선 번호
    '501': Offset(1169, 1281),
    '502': Offset(1063, 1281),
    '503': Offset(945, 1281),
    '504': Offset(823, 1281),
    '505': Offset(570, 1281),
    '506': Offset(480, 1281),
    '507': Offset(246, 1281),

    // 6호선 번호
    '601': Offset(945, 1175),
    '602': Offset(821, 1175),
    '603': Offset(611, 1075),
    '604': Offset(531, 995),
    '605': Offset(469, 934),
    '606': Offset(469, 819),
    '607': Offset(469, 603),
    '608': Offset(469, 470),
    '609': Offset(469, 370),
    '610': Offset(700, 139),
    '611': Offset(778, 61),
    '612': Offset(920, 61),
    '613': Offset(1035, 61),
    '614': Offset(1086, 112),
    '615': Offset(1187, 213),
    '616': Offset(1187, 289),
    '617': Offset(1187, 506),
    '618': Offset(1187, 598),
    '619': Offset(1187, 740),
    '620': Offset(1187, 843),
    '621': Offset(1187, 934),
    '622': Offset(1047, 1073),

    // 7호선 번호
    '701': Offset(945, 1084),
    '702': Offset(945, 934),
    '703': Offset(945, 846),
    '704': Offset(1086, 706),
    '705': Offset(1086, 598),
    '706': Offset(1086, 502),
    '707': Offset(1086, 219),

    // 8호선 번호
    '801': Offset(84, 647),
    '802': Offset(185, 546),
    '803': Offset(261, 470),
    '804': Offset(693, 470),
    '805': Offset(835, 470),
    '806': Offset(958, 470),

    // 9호선 번호
    '901': Offset(202, 934),
    '902': Offset(619, 934),
    '903': Offset(847, 934),
    '904': Offset(1042, 934),
  };

  // 각 호선이 지나는 역을 순서대로 작성합니다.
  // 환승역은 다른 호선에서도 같은 번호를 참조합니다.
  static const Map<int, List<String>> _lineStationIds = {
    // 1호선: 마지막 123번에서 101번으로 돌아오는 순환선
    1: [
      '101',
      '102',
      '103',
      '104',
      '105',
      '106',
      '107',
      '108',
      '109',
      '110',
      '111',
      '112',
      '113',
      '114',
      '115',
      '116',
      '117',
      '118',
      '119',
      '120',
      '121',
      '122',
      '123',
      '101',
    ],

    2: [
      '101',
      '201',
      '202',
      '203',
      '204',
      '205',
      '206',
      '207',
      '208',
      '209',
      '210',
      '211',
      '212',
      '213',
      '214',
      '215',
      '216',
      '217',
    ],

    3: [
      '107',
      '308',
      '307',
      '306',
      '305',
      '123',
      '304',
      '303',
      '302',
      '301',
      '207',
    ],

    4: [
      '104',
      '401',
      '307',
      '402',
      '403',
      '404',
      '405',
      '406',
      '407',
      '115',
      '408',
      '409',
      '410',
      '411',
      '412',
      '413',
      '414',
      '415',
      '416',
      '417',
      '216',
    ],

    5: [
      '109',
      '507',
      '403',
      '506',
      '505',
      '122',
      '504',
      '503',
      '502',
      '501',
      '209',
    ],

    // 6호선: 601번으로 돌아오는 순환선
    6: [
      '601',
      '602',
      '121',
      '603',
      '604',
      '605',
      '606',
      '116',
      '607',
      '608',
      '609',
      '412',
      '610',
      '611',
      '612',
      '613',
      '614',
      '615',
      '616',
      '417',
      '617',
      '618',
      '619',
      '620',
      '621',
      '622',
      '601',
    ],

    7: [
      '202',
      '303',
      '503',
      '601',
      '701',
      '702',
      '703',
      '704',
      '705',
      '706',
      '416',
      '707',
      '614',
    ],

    8: [
      '113',
      '801',
      '802',
      '803',
      '409',
      '608',
      '804',
      '805',
      '806',
      '705',
      '618',
      '214',
    ],

    9: [
      '112',
      '901',
      '406',
      '605',
      '902',
      '119',
      '903',
      '702',
      '904',
      '621',
      '211',
    ],
  };

  static Offset _positionFor(String id) {
    final position = _imagePositions[id];

    if (position == null) {
      throw StateError('위치 정보가 없는 역 번호입니다: $id');
    }

    return Offset(position.dx / 4, position.dy / 4);
  }

  static final List<SubwayMapLine> lines = List<SubwayMapLine>.unmodifiable(
    _lineStationIds.entries.map(
      (entry) => SubwayMapLine(
        number: entry.key,
        color: colorForLine(entry.key),
        points: List<Offset>.unmodifiable(entry.value.map(_positionFor)),
      ),
    ),
  );

  static final List<SubwayMapStation> stations = _buildStations();

  static List<SubwayMapStation> _buildStations() {
    final connections = <String, Set<int>>{};

    for (final entry in _lineStationIds.entries) {
      for (final id in entry.value) {
        connections.putIfAbsent(id, () => <int>{}).add(entry.key);
      }
    }

    return List<SubwayMapStation>.unmodifiable(
      _imagePositions.keys.map((id) {
        final stationLines = connections[id]?.toList();

        if (stationLines == null || stationLines.isEmpty) {
          throw StateError('연결된 호선이 없는 역입니다: $id');
        }

        stationLines.sort();

        return SubwayMapStation(
          id: id,
          position: _positionFor(id),
          lines: List<int>.unmodifiable(stationLines),
          name: _stationNames[id],
        );
      }),
    );
  }

  static Color colorForLine(int number) {
    final color = _lineColors[number];

    if (color == null) {
      throw ArgumentError('등록되지 않은 호선입니다: $number');
    }

    return color;
  }
}
