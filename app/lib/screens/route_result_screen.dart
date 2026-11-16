import 'package:flutter/material.dart';

import '../data/favorite_routes.dart';
import 'favorites_screen.dart';
import 'subway_map_screen.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);
const _border = Color(0xFFD2DAE6);
const _line4 = Color(0xFF00A9D6);
const _line2 = Color(0xFF00AD50);
const _transferColor = Color(0xFF9CA8BA);

class RouteResultScreen extends StatefulWidget {
  const RouteResultScreen({
    super.key,
    required this.departure,
    required this.arrival,
  });

  final String departure;
  final String arrival;

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen> {
  int _selectedCriteria = 0;

  // 화면 구현용 예시 데이터입니다.
  // 사용자가 입력한 역에 따라 계산한 결과가 아닙니다.
  static const _exampleStations = ['서울역', '회현역', '명동역', '충무로역', '동대문역사문화공원역'];

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _showStations() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.6,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '정차역 목록',
                    style: TextStyle(
                      color: _textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '목록 UI 확인용 일부 예시입니다.\n'
                    '검색한 경로의 전체 정차역은 데이터 연동 후 제공됩니다.',
                    style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _exampleStations.length,
                      separatorBuilder: (context, index) {
                        return const Divider(
                          height: 1,
                          color: _lightBackground,
                        );
                      },
                      itemBuilder: (context, index) {
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.circle_outlined,
                            color: _line4,
                            size: 20,
                          ),
                          title: Text(
                            _exampleStations[index],
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 15,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      Navigator.of(sheetContext).pop();
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _navy,
                      minimumSize: const Size(double.infinity, 48),
                      side: const BorderSide(color: _border),
                    ),
                    child: const Text('닫기'),
                  ),
                ],
              ),
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
                _buildHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildRouteTitle(),
                        const SizedBox(height: 22),
                        _buildCriteriaTabs(),
                        const SizedBox(height: 16),
                        _buildSummaryCard(),
                        const SizedBox(height: 12),
                        const Text(
                          '예시 화면 · 아래 시간과 상세 경로는 실제 검색 결과가 '
                          '아니며, 기준을 바꿔도 동일한 예시를 표시합니다.',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Text(
                          '상세 경로',
                          style: TextStyle(
                            color: _textColor,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildTimeline(),
                        const SizedBox(height: 20),
                        OutlinedButton(
                          onPressed: _showStations,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _textColor,
                            side: const BorderSide(color: Color(0xFF9AAAC1)),
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            '정차역 모두 보기',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildBottomNavigation(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: '뒤로가기',
            icon: const Icon(Icons.chevron_left, color: _navy),
          ),
          const Expanded(
            child: Text(
              '경로 결과',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ValueListenableBuilder<List<FavoriteRoute>>(
            valueListenable: FavoriteRoutes.items,
            builder: (context, routes, child) {
              final isFavorite = FavoriteRoutes.contains(
                widget.departure,
                widget.arrival,
              );

              return IconButton(
                onPressed: () {
                  FavoriteRoutes.toggle(widget.departure, widget.arrival);

                  _showMessage(
                    isFavorite
                        ? '즐겨찾기에서 해제했습니다.'
                        : '즐겨찾기에 추가했습니다. 앱 재시작 시 초기화됩니다.',
                  );
                },
                tooltip: isFavorite ? '즐겨찾기 해제' : '즐겨찾기 선택',
                icon: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: _navy,
                  size: 27,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRouteTitle() {
    return Column(
      children: [
        Text(
          '${widget.departure} → ${widget.arrival}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _textColor,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '예상 소요 31분 · 환승 1회 (예시)',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildCriteriaTabs() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _lightBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildCriteriaTab(label: '최단시간', index: 0),
          _buildCriteriaTab(label: '최소환승', index: 1),
        ],
      ),
    );
  }

  Widget _buildCriteriaTab({required String label, required int index}) {
    final selected = _selectedCriteria == index;

    return Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: () {
            setState(() {
              _selectedCriteria = index;
            });
          },
          style: TextButton.styleFrom(
            foregroundColor: selected ? Colors.white : _muted,
            backgroundColor: selected ? _navy : Colors.transparent,
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _lightBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildMetric(label: '총 소요시간', value: '31', unit: '분'),
                ),
                const VerticalDivider(width: 28, thickness: 1, color: _border),
                Expanded(
                  child: _buildMetric(label: '환승', value: '1', unit: '회'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _buildTimeBar(color: _line4, flex: 18),
              const SizedBox(width: 4),
              _buildTimeBar(color: _transferColor, flex: 5),
              const SizedBox(width: 4),
              _buildTimeBar(color: _line2, flex: 8),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              _buildLegend(color: _line4, label: '4호선 18분'),
              _buildLegend(color: _transferColor, label: '환승 5분'),
              _buildLegend(color: _line2, label: '2호선 8분'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric({
    required String label,
    required String value,
    required String unit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: value,
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                ),
              ),
              TextSpan(
                text: unit,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          style: const TextStyle(color: _textColor),
        ),
      ],
    );
  }

  Widget _buildTimeBar({required Color color, required int flex}) {
    return Expanded(
      flex: flex,
      child: Container(
        height: 9,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  Widget _buildLegend({required Color color, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(color: _muted, fontSize: 10)),
      ],
    );
  }

  Widget _buildTimeline() {
    // Figma를 참고한 고정 예시입니다.
    // 입력한 역명과 관계없이 실제 노선으로 안내하지 않습니다.
    return Column(
      children: [
        _buildTimelineStep(
          title: '서울역 승차',
          subtitle: '4호선 · 오이도 방면 · 7개 역 이동',
          duration: '18분',
          markerColor: _line4,
          lineColor: _line4,
          markerText: '4',
        ),
        _buildTimelineStep(
          title: '사당역 환승',
          subtitle: '4호선 → 2호선',
          duration: '5분',
          markerColor: _transferColor,
          lineColor: _border,
          transfer: true,
        ),
        _buildTimelineStep(
          title: '사당역 승차',
          subtitle: '2호선 · 잠실 방면 · 4개 역 이동',
          duration: '8분',
          markerColor: _line2,
          lineColor: _line2,
          markerText: '2',
        ),
        _buildTimelineStep(title: '강남역 하차', markerColor: _line2, isLast: true),
      ],
    );
  }

  Widget _buildTimelineStep({
    required String title,
    required Color markerColor,
    String? subtitle,
    String? duration,
    String? markerText,
    Color? lineColor,
    bool transfer = false,
    bool isLast = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 28,
            child: Column(
              children: [
                Container(
                  width: 25,
                  height: 25,
                  decoration: BoxDecoration(
                    color: transfer || isLast ? Colors.white : markerColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: markerColor,
                      width: isLast ? 2.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: transfer
                      ? const Icon(Icons.swap_horiz, color: _muted, size: 17)
                      : markerText != null
                      ? Text(
                          markerText,
                          style: const TextStyle(
                            color: _navy,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        )
                      : null,
                ),
                if (!isLast)
                  Expanded(child: Container(width: 2, color: lineColor)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 2, bottom: isLast ? 0 : 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (duration != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            duration,
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF2F4F7))),
      ),
      padding: const EdgeInsets.only(top: 6, bottom: 22),
      child: Row(
        children: [
          _buildNavigationItem(
            label: '홈',
            icon: Icons.home_outlined,
            selected: true,
            onPressed: _goHome,
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
            selected: false,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (context) => const SubwayMapScreen(),
                ),
              );
            },
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
