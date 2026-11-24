import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/subway_map_data.dart';
import '../localization/app_strings.dart';
import '../widgets/language_selector.dart';
import 'favorites_screen.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);
const _border = Color(0xFFD2DAE6);

String _t(String key, [Map<String, Object> values = const {}]) {
  var text = AppStrings.text(key);

  for (final entry in values.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value.toString());
  }

  return text;
}

// 공백과 대소문자를 무시합니다.
// 신도림 / 신도림역, 서울 / 서울역 모두 검색할 수 있습니다.
String _normalizeName(String value) {
  var result = value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  if (result.endsWith('역')) {
    result = result.substring(0, result.length - 1);
  }

  return result;
}

class SubwayMapScreen extends StatefulWidget {
  const SubwayMapScreen({super.key});

  @override
  State<SubwayMapScreen> createState() => _SubwayMapScreenState();
}

class _SubwayMapScreenState extends State<SubwayMapScreen> {
  final _searchController = TextEditingController();
  final _transformationController = TransformationController();

  Map<String, String> _namesKo = const {};
  Map<String, String> _namesEn = const {};

  bool _loadingNames = true;
  bool _nameLoadFailed = false;
  int _loadVersion = 0;

  int? _selectedLine;
  String? _selectedStationId;
  Size _viewportSize = Size.zero;

  bool get _useKorean => LanguageSettings.selected.value == AppLanguage.korean;

  Map<String, String> get _displayNames => _useKorean ? _namesKo : _namesEn;

  @override
  void initState() {
    super.initState();
    LanguageSettings.selected.addListener(_onLanguageChanged);
    _loadStationNames();
  }

  @override
  void dispose() {
    LanguageSettings.selected.removeListener(_onLanguageChanged);
    _searchController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _onLanguageChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadStationNames() async {
    final version = ++_loadVersion;

    setState(() {
      _loadingNames = true;
      _nameLoadFailed = false;
    });

    try {
      // 기존 API가 언어별 역 목록을 보관하므로
      // 성공적으로 받은 목록은 같은 앱 실행 중 재사용합니다.
      final results = await Future.wait([
        apiClient.stations('ko'),
        apiClient.stations('en'),
      ]);

      if (!mounted || version != _loadVersion) return;

      final ko = Map<String, String>.unmodifiable({
        for (final station in results[0]) station.id: station.name,
      });
      final en = Map<String, String>.unmodifiable({
        for (final station in results[1]) station.id: station.name,
      });

      setState(() {
        _namesKo = ko;
        _namesEn = en;
        _loadingNames = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;

      setState(() {
        _loadingNames = false;
        _nameLoadFailed = true;
      });
    }
  }

  String _stationName(SubwayMapStation station) {
    final name = _displayNames[station.id];

    if (name != null && name.trim().isNotEmpty) {
      return name;
    }

    return _t('역 {number}', {'number': station.id});
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
    if (_viewportSize.isEmpty) return;

    final current = _transformationController.value;
    final oldScale = current.getMaxScaleOnAxis();
    final newScale = (oldScale * factor).clamp(1.0, 5.0).toDouble();
    final ratio = newScale / oldScale;
    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);

    final matrix = Matrix4.identity();
    matrix.setEntry(0, 0, newScale);
    matrix.setEntry(1, 1, newScale);
    matrix.setEntry(
      0,
      3,
      center.dx - (center.dx - current.storage[12]) * ratio,
    );
    matrix.setEntry(
      1,
      3,
      center.dy - (center.dy - current.storage[13]) * ratio,
    );

    _transformationController.value = matrix;
  }

  void _searchStation() {
    FocusScope.of(context).unfocus();

    final input = _searchController.text.trim();
    if (input.isEmpty) {
      _showMessage(_t('역 이름이나 번호를 입력해 주세요.'));
      return;
    }

    final normalized = _normalizeName(input);
    SubwayMapStation? match;

    // ID가 정확히 일치하면 이름을 불러오기 전에도 검색 가능합니다.
    for (final station in SubwayMapData.stations) {
      if (station.id == input) {
        match = station;
        break;
      }
    }

    // 화면 언어와 관계없이 한국어와 영어 이름을 모두 검색합니다.
    if (match == null && normalized.isNotEmpty) {
      for (final station in SubwayMapData.stations) {
        final ko = _namesKo[station.id];
        final en = _namesEn[station.id];

        if ((ko != null && _normalizeName(ko) == normalized) ||
            (en != null && _normalizeName(en) == normalized)) {
          match = station;
          break;
        }
      }
    }

    if (match == null) {
      if (_loadingNames || _nameLoadFailed) {
        _showMessage(_t('역 이름을 불러온 뒤 다시 검색하거나 역 번호로 검색해 주세요.'));
      } else {
        _showMessage(_t('일치하는 역이 없어요. 역 이름이나 번호를 확인해 주세요.'));
      }
      return;
    }

    final station = match;

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

    if (nearest == null || nearestDistance * scale * zoom > 18) {
      return;
    }

    final station = nearest;

    setState(() {
      _selectedStationId = station.id;
    });

    _showStationDetails(station);
  }

  void _showStationDetails(SubwayMapStation station) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      builder: (sheetContext) {
        // 名前データ読み込み後も詳細を更新します。
        return AnimatedBuilder(
          animation: Listenable.merge([
            LanguageSettings.selected,
            _detailsNotifier,
          ]),
          builder: (context, child) {
            return SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _stationName(station),
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_t('역 번호 {number}', {'number': station.id})}'
                      ' · ${_t(station.isTransfer ? '환승역' : '일반역')}',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final number in station.lines)
                          Chip(
                            avatar: CircleAvatar(
                              backgroundColor: SubwayMapData.colorForLine(
                                number,
                              ),
                              radius: 5,
                            ),
                            label: Text(_t('{line}호선', {'line': number})),
                            backgroundColor: _lightBackground,
                            side: BorderSide.none,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _t(
                        '프로젝트용 가상 노선도입니다.\n'
                        '실제 지하철 노선과 다를 수 있습니다.',
                      ),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                      child: Text(_t('닫기')),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 상세 창이 열린 상태에서 이름을 받아도 화면을 갱신합니다.
  final _detailsNotifier = ValueNotifier<int>(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _detailsNotifier.value++;
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 20,
                  ),
                  child: Text(
                    _t('노선도'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
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
                _buildNameStatus(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _t('가상 노선도 · 한국어·영어 이름 또는 번호로 검색'),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 10,
                        height: 1.4,
                      ),
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

  Widget _buildNameStatus() {
    if (_loadingNames) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Row(
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _t('역 이름을 불러오는 중입니다…'),
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ),
          ],
        ),
      );
    }

    if (!_nameLoadFailed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _t('역 이름을 불러오지 못했어요. 현재는 역 번호로 표시합니다.'),
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.4),
            ),
          ),
          TextButton(onPressed: _loadStationNames, child: Text(_t('다시 시도'))),
        ],
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
        hintText: _t('역 이름 또는 번호 검색'),
        hintStyle: const TextStyle(color: _muted, fontSize: 12),
        prefixIcon: IconButton(
          onPressed: _searchStation,
          tooltip: _t('역 검색'),
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
                tooltip: _t('검색어 지우기'),
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
          number == null ? _t('전체') : _t('{line}호선', {'line': number}),
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
                        stationNames: _displayNames,
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
                      tooltip: _t('확대'),
                      icon: const Icon(Icons.add, color: _navy),
                    ),
                    IconButton(
                      onPressed: () => _zoom(1 / 1.3),
                      tooltip: _t('축소'),
                      icon: const Icon(Icons.remove, color: _navy),
                    ),
                    IconButton(
                      onPressed: _resetView,
                      tooltip: _t('원래 크기'),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 14),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildLegendItem(Icons.radio_button_checked, 14, '환승역'),
            _buildLegendItem(Icons.circle_outlined, 10, '일반역'),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(IconData icon, double size, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: size, color: _navy),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            _t(label),
            style: const TextStyle(color: _muted, fontSize: 10, height: 1.4),
          ),
        ),
      ],
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
              Text(
                _t(label),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    required this.stationNames,
  });

  final int? selectedLine;
  final String? selectedStationId;
  final Map<String, String> stationNames;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = _mapScale(size);
    final offset = _mapOffset(size, scale);

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

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

    // 선택한 역은 마지막에 그려 강조 표시가 덮이지 않도록 합니다.
    final stations = [
      for (final station in SubwayMapData.stations)
        if (station.id != selectedStationId) station,
      for (final station in SubwayMapData.stations)
        if (station.id == selectedStationId) station,
    ];

    for (final station in stations) {
      final active =
          selectedLine == null || station.lines.contains(selectedLine);
      if (!active) continue;

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

      final name = stationNames[station.id];
      final label = name == null || name.trim().isEmpty ? station.id : name;

      final textPainter = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: selected ? _navy : _textColor,
            fontSize: selected ? 5.5 : 4,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
          ),
        ),
        maxLines: 1,
        ellipsis: '…',
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: selected ? 72 : 42);

      // 오른쪽 끝 역의 이름은 왼쪽에 표시합니다.
      final rightX = station.position.dx + radius + 2;
      final drawX =
          rightX + textPainter.width > SubwayMapData.canvasSize.width - 2
          ? station.position.dx - radius - 2 - textPainter.width
          : rightX;
      final drawY = math.max(0.0, station.position.dy - textPainter.height - 1);

      final textOffset = Offset(drawX, drawY);

      // 이름 뒤에 흰 배경을 넣어 노선과 글자가 겹칠 때 읽기 쉽게 합니다.
      canvas.drawRect(
        Rect.fromLTWH(
          drawX - 0.7,
          drawY - 0.3,
          textPainter.width + 1.4,
          textPainter.height + 0.6,
        ),
        Paint()..color = Colors.white,
      );

      textPainter.paint(canvas, textOffset);
      textPainter.dispose();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SubwayMapPainter oldDelegate) {
    return oldDelegate.selectedLine != selectedLine ||
        oldDelegate.selectedStationId != selectedStationId ||
        oldDelegate.stationNames != stationNames;
  }
}
