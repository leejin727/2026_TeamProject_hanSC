import 'package:flutter/material.dart';

import '../data/favorite_routes.dart';
import '../data/recent_routes.dart';
import 'favorites_screen.dart';
import 'meeting_input_screen.dart';
import 'route_result_screen.dart';
import 'subway_map_screen.dart';
import '../widgets/language_selector.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);
const _border = Color(0xFFD2DAE6);

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _departureController = TextEditingController();
  final _arrivalController = TextEditingController();

  @override
  void dispose() {
    _departureController.dispose();
    _arrivalController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _swapStations() {
    final departure = _departureController.text;
    _departureController.text = _arrivalController.text;
    _arrivalController.text = departure;
  }

  void _searchRoute() {
    FocusScope.of(context).unfocus();

    final departure = _departureController.text.trim();
    final arrival = _arrivalController.text.trim();

    if (departure.isEmpty || arrival.isEmpty) {
      _showMessage('출발역과 도착역을 모두 입력해 주세요.');
      return;
    }

    if (departure == arrival) {
      _showMessage('출발역과 도착역을 다르게 입력해 주세요.');
      return;
    }

    // 최신 검색을 맨 앞에 추가합니다.
    // 중복 제거와 최대 10개 제한은 데이터 파일에서 처리합니다.
    RecentRoutes.add(departure, arrival);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) =>
            RouteResultScreen(departure: departure, arrival: arrival),
      ),
    );
  }

  void _selectRoute(RecentRoute route) {
    _departureController.text = route.departure;
    _arrivalController.text = route.arrival;
    _searchRoute();
  }

  void _openMeetingScreen() {
    FocusScope.of(context).unfocus();

    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const MeetingInputScreen()),
    );
  }

  void _openFavoritesScreen() {
    FocusScope.of(context).unfocus();

    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const FavoritesScreen()),
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
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 28),
                        const Text(
                          '어디로 가시나요?',
                          style: TextStyle(
                            color: _textColor,
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '출발역을 입력하면 가장 빠른 길을 찾아드려요',
                          style: TextStyle(
                            color: _muted,
                            fontSize: 12,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildRouteDecoration(),
                        const SizedBox(height: 24),
                        _buildTabs(),
                        const SizedBox(height: 24),
                        _buildStationInputs(),
                        const SizedBox(height: 24),
                        _buildSearchButton(),
                        const SizedBox(height: 16),
                        _buildRecentRoutes(),
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
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _navy,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(
            Icons.train_outlined,
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 9),
        const Text(
          'SubFit',
          style: TextStyle(
            color: _textColor,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        const LanguageSelector(),
      ],
    );
  }

  Widget _buildRouteDecoration() {
    return ExcludeSemantics(
      child: SizedBox(
        height: 34,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const startX = 6.0;
            final endX = constraints.maxWidth - 6;
            final trainCenterX = startX + (endX - startX) * 0.365;

            return Stack(
              children: [
                const Positioned.fill(
                  child: CustomPaint(painter: _RouteLinePainter()),
                ),
                Positioned(
                  left: trainCenterX - 15.5,
                  top: 6.5,
                  child: const _TrainMarker(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _lightBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTab(label: '경로 검색', selected: true, onPressed: () {}),
          ),
          Expanded(
            child: _buildTab(
              label: '모임역 추천',
              selected: false,
              onPressed: _openMeetingScreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab({
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          backgroundColor: selected ? _navy : Colors.transparent,
          foregroundColor: selected ? Colors.white : _muted,
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildStationInputs() {
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        Column(
          children: [
            _buildStationField(
              label: '출발',
              hint: '출발역 입력',
              controller: _departureController,
              inputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            _buildStationField(
              label: '도착',
              hint: '도착역 입력',
              controller: _arrivalController,
              inputAction: TextInputAction.search,
              onSubmitted: (_) => _searchRoute(),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            onPressed: _swapStations,
            tooltip: '출발역과 도착역 교환',
            style: IconButton.styleFrom(
              backgroundColor: _lightBackground,
              foregroundColor: _navy,
              side: const BorderSide(color: _border),
              minimumSize: const Size(44, 44),
              shape: const CircleBorder(),
            ),
            icon: const Icon(Icons.swap_vert, size: 23),
          ),
        ),
      ],
    );
  }

  Widget _buildStationField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required TextInputAction inputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      padding: const EdgeInsets.only(left: 16, right: 56),
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _navy,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            color: _border,
          ),
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: inputAction,
              onSubmitted: onSubmitted,
              cursorColor: _navy,
              style: const TextStyle(
                color: _textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: _muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchButton() {
    return FilledButton(
      onPressed: _searchRoute,
      style: FilledButton.styleFrom(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 62),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: const Text(
        '경로 검색',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildRecentRoutes() {
    return ValueListenableBuilder<List<RecentRoute>>(
      valueListenable: RecentRoutes.items,
      builder: (context, routes, child) {
        final homeRoutes = routes.take(5).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text(
                  '최근 검색',
                  style: TextStyle(
                    color: _textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _showAllRecentRoutes,
                  style: TextButton.styleFrom(
                    foregroundColor: _muted,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('전체보기', style: TextStyle(fontSize: 11)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (homeRoutes.isEmpty)
              _buildRecentEmptyState()
            else
              for (final route in homeRoutes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _buildRecentRouteCard(
                    route: route,
                    onTap: () => _selectRoute(route),
                  ),
                ),
          ],
        );
      },
    );
  }

  Widget _buildRecentRouteCard({
    required RecentRoute route,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _lightBackground,
      borderRadius: BorderRadius.circular(13),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 19,
                ),
                child: Text(
                  '${route.departure} → ${route.arrival}',
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<List<FavoriteRoute>>(
            valueListenable: FavoriteRoutes.items,
            builder: (context, favorites, child) {
              final isFavorite = FavoriteRoutes.contains(
                route.departure,
                route.arrival,
              );

              return IconButton(
                onPressed: () {
                  FavoriteRoutes.toggle(route.departure, route.arrival);
                },
                tooltip: isFavorite ? '즐겨찾기 해제' : '즐겨찾기 선택',
                icon: Icon(
                  isFavorite ? Icons.star_rounded : Icons.star_border_rounded,
                  color: _navy,
                  size: 26,
                ),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildRecentEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      decoration: BoxDecoration(
        color: _lightBackground,
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Column(
        children: [
          Icon(Icons.history, color: _muted, size: 28),
          SizedBox(height: 10),
          Text(
            '최근 검색 기록이 없어요',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 6),
          Text(
            '출발역과 도착역을 입력해 경로를 검색해 보세요.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Future<void> _showAllRecentRoutes() async {
    FocusScope.of(context).unfocus();

    final selectedRoute = await showModalBottomSheet<RecentRoute>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.75,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '최근 검색 전체보기',
                          style: TextStyle(
                            color: _textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop();
                        },
                        tooltip: '닫기',
                        icon: const Icon(Icons.close, color: _navy),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '최신순으로 최대 10개까지 표시돼요.',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ValueListenableBuilder<List<RecentRoute>>(
                      valueListenable: RecentRoutes.items,
                      builder: (context, routes, child) {
                        if (routes.isEmpty) {
                          return SingleChildScrollView(
                            child: _buildRecentEmptyState(),
                          );
                        }

                        return ListView.builder(
                          itemCount: routes.length,
                          itemBuilder: (context, index) {
                            final route = routes[index];

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildRecentRouteCard(
                                route: route,
                                onTap: () {
                                  Navigator.of(sheetContext).pop(route);
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<List<RecentRoute>>(
                    valueListenable: RecentRoutes.items,
                    builder: (context, routes, child) {
                      return OutlinedButton.icon(
                        onPressed: routes.isEmpty ? null : RecentRoutes.clear,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _navy,
                          side: const BorderSide(color: _border),
                          minimumSize: const Size(double.infinity, 52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.delete_outline, size: 20),
                        label: const Text(
                          '최근 검색 전체 삭제',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '검색 기록만 삭제되며 즐겨찾기는 유지돼요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    // 홈 화면이 남아 있고, 경로를 선택했을 때만 재검색합니다.
    if (!mounted || selectedRoute == null) {
      return;
    }

    _selectRoute(selectedRoute);
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
            onPressed: () {},
          ),
          _buildNavigationItem(
            label: '즐겨찾기',
            icon: Icons.star_border_rounded,
            selected: false,
            onPressed: _openFavoritesScreen,
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

class _TrainMarker extends StatelessWidget {
  const _TrainMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 31,
      height: 21,
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [_buildWindow(), const SizedBox(width: 5), _buildWindow()],
      ),
    );
  }

  Widget _buildWindow() {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _RouteLinePainter extends CustomPainter {
  const _RouteLinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    const fadedColor = Color(0xFFA0ABBE);
    const startX = 6.0;

    final endX = size.width - 6;
    final centerY = size.height / 2;
    final middleX = startX + (endX - startX) * 0.48;

    final linePaint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    linePaint.color = fadedColor;
    canvas.drawLine(Offset(middleX, centerY), Offset(endX, centerY), linePaint);

    linePaint.color = _navy;
    canvas.drawLine(
      Offset(startX, centerY),
      Offset(middleX, centerY),
      linePaint,
    );

    const positions = [0.0, 0.23, 0.48, 0.74, 1.0];

    for (var index = 0; index < positions.length; index++) {
      final center = Offset(
        startX + (endX - startX) * positions[index],
        centerY,
      );

      final isMiddle = index == 2;
      final radius = isMiddle ? 4.75 : 3.5;
      final color = index <= 2 ? _navy : fadedColor;

      canvas.drawCircle(center, radius, Paint()..color = Colors.white);

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );

      if (isMiddle) {
        canvas.drawCircle(center, 2, Paint()..color = _navy);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RouteLinePainter oldDelegate) => false;
}
