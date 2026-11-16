import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/subway_map_data.dart';
import 'favorites_screen.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);
const _border = Color(0xFFD2DAE6);

class SubwayMapScreen extends StatefulWidget {
  const SubwayMapScreen({super.key});

  @override
  State<SubwayMapScreen> createState() => _SubwayMapScreenState();
}

class _SubwayMapScreenState extends State<SubwayMapScreen> {
  final _searchController = TextEditingController();
  final _transformationController = TransformationController();

  int? _selectedLine;
  String? _selectedStationId;
  Size _viewportSize = Size.zero;

  @override
  void dispose() {
    _searchController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _resetView() {
    _transformationController.value = Matrix4.identity();
  }

  void _zoom(double factor) {
    if (_viewportSize.isEmpty) {
      return;
    }

    final current = _transformationController.value;
    final oldScale = current.getMaxScaleOnAxis();
    final newScale = (oldScale * factor).clamp(1.0, 5.0).toDouble();
    final ratio = newScale / oldScale;

    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);

    final oldX = current.storage[12];
    final oldY = current.storage[13];

    final matrix = Matrix4.identity();
    matrix.setEntry(0, 0, newScale);
    matrix.setEntry(1, 1, newScale);
    matrix.setEntry(0, 3, center.dx - (center.dx - oldX) * ratio);
    matrix.setEntry(1, 3, center.dy - (center.dy - oldY) * ratio);

    _transformationController.value = matrix;
  }

  void _searchStation() {
    FocusScope.of(context).unfocus();

    final query = _searchController.text.trim().toLowerCase();

    if (query.isEmpty) {
      _showMessage('역 번호를 입력해 주세요. 예: 101');
      return;
    }

    final matches = SubwayMapData.stations.where((station) {
      return station.id.toLowerCase() == query ||
          station.name?.toLowerCase() == query;
    }).toList();

    if (matches.isEmpty) {
      _showMessage('일치하는 역이 없어요. 현재는 임시 역 번호로 검색해 주세요.');
      return;
    }

    final station = matches.first;

    setState(() {
      _selectedLine = null;
      _selectedStationId = station.id;
    });

    _resetView();
    _showStationDetails(station);
  }

  void _selectLine(int? line) {
    setState(() {
      _selectedLine = line;
      _selectedStationId = null;
    });

    _resetView();
  }

  void _onMapTap(Offset localPosition, Size size) {
    final scale = _mapScale(size);
    final offset = _mapOffset(size, scale);

    final mapPoint = Offset(
      (localPosition.dx - offset.dx) / scale,
      (localPosition.dy - offset.dy) / scale,
    );

    SubwayMapStation? nearest;
    var nearestDistance = double.infinity;

    for (final station in SubwayMapData.stations) {
      if (_selectedLine != null && !station.lines.contains(_selectedLine)) {
        continue;
      }

      final distance = (station.position - mapPoint).distance;

      if (distance < nearestDistance) {
        nearest = station;
        nearestDistance = distance;
      }
    }

    final zoom = _transformationController.value.getMaxScaleOnAxis();

    // 화면상 약 18픽셀 이내의 가장 가까운 역을 선택합니다.
    if (nearest == null || nearestDistance * scale * zoom > 18) {
      return;
    }

    setState(() {
      _selectedStationId = nearest!.id;
    });

    _showStationDetails(nearest);
  }

  void _showStationDetails(SubwayMapStation station) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  station.name ?? '역 ${station.id}',
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '임시 번호 ${station.id} · '
                  '${station.isTransfer ? '환승역' : '일반역'}',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final number in station.lines)
                      Chip(
                        avatar: CircleAvatar(
                          backgroundColor: SubwayMapData.colorForLine(number),
                          radius: 5,
                        ),
                        label: Text('$number호선'),
                        backgroundColor: _lightBackground,
                        side: BorderSide.none,
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  '현재는 임시 노선 데이터입니다.\n'
                  '역 이름과 실제 연결 정보는 추후 반영합니다.',
                  style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: const Text('닫기'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    '노선도',
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: _buildSearchField(),
                ),
                const SizedBox(height: 10),
                _buildLineFilters(),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '임시 노선도 · 역 번호로 검색할 수 있어요',
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  ),
                ),
                Expanded(child: _buildMap()),
                _buildLegend(),
                _buildBottomNavigation(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (_) => setState(() {}),
      onSubmitted: (_) => _searchStation(),
      textInputAction: TextInputAction.search,
      cursorColor: _navy,
      style: const TextStyle(color: _textColor, fontSize: 14),
      decoration: InputDecoration(
        hintText: '역 이름 또는 번호 검색',
        hintStyle: const TextStyle(color: _muted, fontSize: 12),
        prefixIcon: IconButton(
          onPressed: _searchStation,
          tooltip: '역 검색',
          icon: const Icon(Icons.search, color: _navy, size: 22),
        ),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _selectedStationId = null;
                  });
                },
                tooltip: '검색어 지우기',
                icon: const Icon(Icons.close, color: _muted, size: 18),
              ),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _navy),
        ),
      ),
    );
  }

  Widget _buildLineFilters() {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          _buildFilter(null),
          for (var number = 1; number <= 9; number++) _buildFilter(number),
        ],
      ),
    );
  }

  Widget _buildFilter(int? number) {
    final selected = _selectedLine == number;

    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => _selectLine(number),
        selectedColor: _navy,
        backgroundColor: Colors.white,
        side: BorderSide(color: selected ? _navy : _border),
        shape: const StadiumBorder(),
        avatar: number == null
            ? null
            : CircleAvatar(
                radius: 4,
                backgroundColor: SubwayMapData.colorForLine(number),
              ),
        label: Text(
          number == null ? '전체' : '$number호선',
          style: TextStyle(
            color: selected ? Colors.white : _textColor,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildMap() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _viewportSize = size;

        return Stack(
          children: [
            Positioned.fill(
              child: ClipRect(
                child: InteractiveViewer(
                  transformationController: _transformationController,
                  minScale: 1,
                  maxScale: 5,
                  boundaryMargin: const EdgeInsets.all(100),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (details) {
                      _onMapTap(details.localPosition, size);
                    },
                    child: CustomPaint(
                      size: size,
                      painter: _SubwayMapPainter(
                        selectedLine: _selectedLine,
                        selectedStationId: _selectedStationId,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 16,
              bottom: 12,
              child: Material(
                color: Colors.white,
                elevation: 1,
                borderRadius: BorderRadius.circular(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _zoom(1.3),
                      tooltip: '확대',
                      icon: const Icon(Icons.add, color: _navy),
                    ),
                    IconButton(
                      onPressed: () => _zoom(1 / 1.3),
                      tooltip: '축소',
                      icon: const Icon(Icons.remove, color: _navy),
                    ),
                    IconButton(
                      onPressed: _resetView,
                      tooltip: '원래 크기',
                      icon: const Icon(
                        Icons.center_focus_strong,
                        color: _navy,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLegend() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, 14),
      child: Row(
        children: [
          Icon(Icons.radio_button_checked, size: 14, color: _navy),
          SizedBox(width: 5),
          Text('환승역', style: TextStyle(color: _muted, fontSize: 10)),
          SizedBox(width: 16),
          Icon(Icons.circle_outlined, size: 10, color: _navy),
          SizedBox(width: 5),
          Text('일반역', style: TextStyle(color: _muted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF2F4F7))),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 22),
      child: Row(
        children: [
          _buildNavigationItem(
            label: '홈',
            icon: Icons.home_outlined,
            selected: false,
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          _buildNavigationItem(
            label: '즐겨찾기',
            icon: Icons.star_border_rounded,
            selected: false,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const FavoritesScreen(),
                ),
              );
            },
          ),
          _buildNavigationItem(
            label: '노선도',
            icon: Icons.map_outlined,
            selected: true,
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationItem({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            foregroundColor: _navy,
            padding: const EdgeInsets.symmetric(vertical: 4),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: selected ? _lightBackground : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 23),
              ),
              const SizedBox(height: 3),
              Text(label, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

// 지도 전체가 화면 안에 들어오도록 비율을 계산합니다.
double _mapScale(Size size) {
  return math.max(
    0.01,
    math.min(
          size.width / SubwayMapData.canvasSize.width,
          size.height / SubwayMapData.canvasSize.height,
        ) *
        0.94,
  );
}

Offset _mapOffset(Size size, double scale) {
  return Offset(
    (size.width - SubwayMapData.canvasSize.width * scale) / 2,
    (size.height - SubwayMapData.canvasSize.height * scale) / 2,
  );
}

class _SubwayMapPainter extends CustomPainter {
  const _SubwayMapPainter({
    required this.selectedLine,
    required this.selectedStationId,
  });

  final int? selectedLine;
  final String? selectedStationId;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = _mapScale(size);
    final offset = _mapOffset(size, scale);

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    // 선택하지 않은 노선은 먼저 연하게 그립니다.
    final orderedLines = [...SubwayMapData.lines];

    if (selectedLine != null) {
      orderedLines.sort((a, b) {
        final aSelected = a.number == selectedLine ? 1 : 0;
        final bSelected = b.number == selectedLine ? 1 : 0;
        return aSelected.compareTo(bSelected);
      });
    }

    for (final line in orderedLines) {
      final active = selectedLine == null || line.number == selectedLine;
      final path = Path()..moveTo(line.points.first.dx, line.points.first.dy);

      for (final point in line.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = active ? line.color : const Color(0xFFE8EDF2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 2 : 1.2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }

    for (final station in SubwayMapData.stations) {
      final active =
          selectedLine == null || station.lines.contains(selectedLine);

      if (!active) {
        continue;
      }

      final selected = station.id == selectedStationId;
      final color = SubwayMapData.colorForLine(
        selectedLine ?? station.lines.first,
      );
      final radius = station.isTransfer ? 3.4 : 2.1;

      if (selected) {
        canvas.drawCircle(
          station.position,
          9,
          Paint()..color = const Color(0xFFFFE3A1),
        );
        canvas.drawCircle(
          station.position,
          9,
          Paint()
            ..color = _navy
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2,
        );
      }

      canvas.drawCircle(
        station.position,
        radius,
        Paint()..color = Colors.white,
      );

      canvas.drawCircle(
        station.position,
        radius,
        Paint()
          ..color = station.isTransfer ? _navy : color
          ..style = PaintingStyle.stroke
          ..strokeWidth = station.isTransfer ? 1.1 : 0.9,
      );

      if (station.isTransfer) {
        canvas.drawCircle(station.position, 1.1, Paint()..color = _navy);
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: station.label,
          style: TextStyle(
            color: selected ? _navy : _textColor,
            fontSize: selected ? 5.5 : 4,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      textPainter.paint(
        canvas,
        Offset(
          station.position.dx + radius + 2,
          station.position.dy - textPainter.height - 1,
        ),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SubwayMapPainter oldDelegate) {
    return oldDelegate.selectedLine != selectedLine ||
        oldDelegate.selectedStationId != selectedStationId;
  }
}
