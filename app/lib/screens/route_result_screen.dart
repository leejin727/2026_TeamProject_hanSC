import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/favorite_routes.dart';
import '../data/subway_map_data.dart';
import '../widgets/language_selector.dart';
import 'favorites_screen.dart';
import 'subway_map_screen.dart';
import '../localization/app_strings.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);
const _border = Color(0xFFD2DAE6);
const _transferColor = Color(0xFF9CA8BA);

/// 노선 색. 노선도 화면과 같은 색을 쓴다.
Color _lineColor(int line) {
  try {
    return SubwayMapData.colorForLine(line);
  } on ArgumentError {
    return _muted;
  }
}

class RouteResultScreen extends StatefulWidget {
  const RouteResultScreen({
    super.key,
    required this.departure,
    required this.arrival,
    this.criteria = 'time',
  });

  /// 사용자가 입력한 역 이름 (예: '신도림', 'Sindorim')
  final String departure;
  final String arrival;

  /// 처음 열어 둘 탭: 'time'(최단시간) 또는 'transfers'(최소환승).
  /// 챗봇이 찾은 경로를 같은 기준으로 보여 줄 때 쓴다.
  final String criteria;

  @override
  State<RouteResultScreen> createState() => _RouteResultScreenState();
}

class _RouteResultScreenState extends State<RouteResultScreen> {
  // 탭 순서대로 서버의 criteria 값 (api-spec.md 2장)
  static const _criteriaValues = ['time', 'transfers'];

  int _selectedCriteria = 0;

  /// 입력한 역 이름 → (출발역 ID, 도착역 ID)
  late Future<(String, String)> _stationIds;

  // 기준(탭)별 결과. 탭을 다시 눌러도 서버를 또 부르지 않는다.
  final Map<String, Future<RouteResult>> _routes = {};
  final Map<String, Future<String>> _explanations = {};

  String get _criteria => _criteriaValues[_selectedCriteria];

  // 역 이름 데이터는 한국어·영어만 있다. 앱 언어가 한국어가 아니면 영어 이름을 쓴다.
  String get _nameLang =>
      LanguageSettings.selected.value.code == 'ko' ? 'ko' : 'en';

  // AI 설명은 앱에서 고른 언어 그대로 (ko, en, ja, zh-Hans, zh-Hant, vi)
  String get _explainLang => LanguageSettings.selected.value.code;

  @override
  void initState() {
    super.initState();
    final index = _criteriaValues.indexOf(widget.criteria);
    if (index > 0) _selectedCriteria = index; // 모르는 값이면 첫 탭 그대로
    _stationIds = _findStationIds();
  }

  Future<(String, String)> _findStationIds() async {
    final start = await apiClient.findStationId(widget.departure);
    if (start == null) {
      throw ApiException(
        'STATION_NOT_FOUND',
        "'${widget.departure}' 역을 찾을 수 없습니다.",
      );
    }
    final end = await apiClient.findStationId(widget.arrival);
    if (end == null) {
      throw ApiException(
        'STATION_NOT_FOUND',
        "'${widget.arrival}' 역을 찾을 수 없습니다.",
      );
    }
    return (start, end);
  }

  Future<RouteResult> _routeFor(String criteria) {
    return _routes[criteria] ??= _stationIds.then(
      (ids) => apiClient.route(
        startId: ids.$1,
        endId: ids.$2,
        criteria: criteria,
        lang: _nameLang,
      ),
    );
  }

  // 경로 계산과 AI 설명은 따로 부른다. 설명이 실패해도 경로는 그대로 보인다.
  Future<String> _explanationFor(String criteria) {
    return _explanations[criteria] ??= _stationIds.then(
      (ids) => apiClient.explainRoute(
        startId: ids.$1,
        endId: ids.$2,
        criteria: criteria,
        lang: _nameLang,
        explainLang: _explainLang,
      ),
    );
  }

  void _retryRoute() {
    setState(() {
      _stationIds = _findStationIds();
      _routes.clear();
      _explanations.clear();
    });
  }

  void _retryExplanation() {
    setState(() {
      _explanations.remove(_criteria);
    });
  }

  String _routeErrorText(Object? error) {
    if (error is ApiException) {
      switch (error.code) {
        case 'NETWORK':
          return '서버에 연결할 수 없습니다.\n서버가 켜져 있는지 확인해 주세요.';
        case 'SAME_STATION':
          return '출발역과 도착역이 같습니다.';
        case 'NO_ROUTE':
          return '두 역을 잇는 경로가 없습니다.';
        case 'STATION_NOT_FOUND':
          return error.message;
      }
      return error.message;
    }
    return '알 수 없는 오류가 발생했습니다.';
  }

  String _explanationErrorText(Object? error) {
    if (error is ApiException && error.code == 'NETWORK') {
      return '서버에 연결할 수 없습니다.';
    }
    return '지금은 AI 설명을 만들 수 없습니다. 잠시 후 다시 시도해 주세요.';
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// 지나가는 모든 역 (환승역은 한 번만)과 그때 탄 노선
  List<(StationRef, int)> _allStations(RouteResult route) {
    final stations = <(StationRef, int)>[];
    for (final segment in route.segments) {
      final skipFirst = stations.isNotEmpty; // 환승역은 앞 구간에서 이미 넣었다
      for (final station in segment.stations.skip(skipFirst ? 1 : 0)) {
        stations.add((station, segment.line));
      }
    }
    return stations;
  }

  void _showStations(RouteResult route) {
    final stations = _allStations(route);

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
                  Text(
                    AppStrings.text('정차역 목록'),
                    style: const TextStyle(
                      color: _textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '출발역부터 도착역까지 ${stations.length}개 역',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: stations.length,
                      separatorBuilder: (context, index) {
                        return const Divider(
                          height: 1,
                          color: _lightBackground,
                        );
                      },
                      itemBuilder: (context, index) {
                        final (station, line) = stations[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            Icons.circle_outlined,
                            color: _lineColor(line),
                            size: 20,
                          ),
                          title: Text(
                            station.name,
                            style: const TextStyle(
                              color: _textColor,
                              fontSize: 15,
                            ),
                          ),
                          trailing: Text(
                            '$line호선',
                            style: const TextStyle(color: _muted, fontSize: 12),
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
                    child: Text(AppStrings.text('닫기')),
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
                  child: FutureBuilder<RouteResult>(
                    future: _routeFor(_criteria),
                    builder: (context, snapshot) {
                      // 탭을 바꾸면 새 결과가 올 때까지 로딩을 보여 준다
                      final done =
                          snapshot.connectionState == ConnectionState.done;
                      final route = done && !snapshot.hasError
                          ? snapshot.data
                          : null;

                      return SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildRouteTitle(route),
                            const SizedBox(height: 22),
                            _buildCriteriaTabs(),
                            const SizedBox(height: 16),
                            if (!done)
                              _buildLoading()
                            else if (snapshot.hasError)
                              _buildError(snapshot.error)
                            else
                              ..._buildRouteDetails(route!),
                          ],
                        ),
                      );
                    },
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

  List<Widget> _buildRouteDetails(RouteResult route) {
    return [
      _buildSummaryCard(route),
      const SizedBox(height: 16),
      _buildExplanationCard(),
      const SizedBox(height: 22),
      Text(
        AppStrings.text('상세 경로'),
        style: const TextStyle(
          color: _textColor,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 16),
      _buildTimeline(route),
      const SizedBox(height: 20),
      OutlinedButton(
        onPressed: () => _showStations(route),
        style: OutlinedButton.styleFrom(
          foregroundColor: _textColor,
          side: const BorderSide(color: Color(0xFF9AAAC1)),
          minimumSize: const Size(double.infinity, 54),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          AppStrings.text('정차역 모두 보기'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    ];
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
      child: Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildError(Object? error) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _lightBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: _muted, size: 32),
          const SizedBox(height: 10),
          Text(
            _routeErrorText(error),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textColor,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _retryRoute,
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: const BorderSide(color: _border),
            ),
            child: Text(AppStrings.text('다시 시도')),
          ),
        ],
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
            tooltip: AppStrings.text('뒤로가기'),
            icon: const Icon(Icons.chevron_left, color: _navy),
          ),
          Expanded(
            child: Text(
              AppStrings.text('경로 결과'),
              textAlign: TextAlign.center,
              style: const TextStyle(
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
                    AppStrings.text(
                      isFavorite
                          ? '즐겨찾기에서 해제했습니다.'
                          : '즐겨찾기에 추가했습니다. 앱 재시작 시 초기화됩니다.',
                    ),
                  );
                },
                tooltip: AppStrings.text(isFavorite ? '즐겨찾기 해제' : '즐겨찾기 선택'),
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

  /// [route]가 없으면(불러오는 중·오류) 입력한 이름을 보여 준다.
  Widget _buildRouteTitle(RouteResult? route) {
    final title = route == null
        ? '${widget.departure} → ${widget.arrival}'
        : '${route.start.name} → ${route.end.name}';

    return Column(
      children: [
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _textColor,
            fontSize: 25,
            fontWeight: FontWeight.w800,
            height: 1.4,
          ),
        ),
        if (route != null) ...[
          const SizedBox(height: 8),
          Text(
            '예상 소요 ${minutesOf(route.totalSec)}분 · 환승 ${route.transferCount}회',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
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
            AppStrings.text(label),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }

  /// 탄 순서대로 (색, 걸린 초, 설명): 노선 구간 → 환승 → 노선 구간 …
  List<(Color, int, String)> _timeParts(RouteResult route) {
    final parts = <(Color, int, String)>[];
    for (var i = 0; i < route.segments.length; i++) {
      final segment = route.segments[i];
      parts.add((
        _lineColor(segment.line),
        segment.rideSec,
        '${segment.line}호선 ${minutesOf(segment.rideSec)}분',
      ));
      if (i < route.transfers.length) {
        final transfer = route.transfers[i];
        parts.add((
          _transferColor,
          transfer.sec,
          '환승 ${minutesOf(transfer.sec)}분',
        ));
      }
    }
    return parts;
  }

  Widget _buildSummaryCard(RouteResult route) {
    final parts = _timeParts(route);

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
                  child: _buildMetric(
                    label: '총 소요시간',
                    value: '${minutesOf(route.totalSec)}',
                    unit: '분',
                  ),
                ),
                const VerticalDivider(width: 28, thickness: 1, color: _border),
                Expanded(
                  child: _buildMetric(
                    label: '환승',
                    value: '${route.transferCount}',
                    unit: '회',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          // 막대 길이 = 걸린 시간 비율
          Row(
            children: [
              for (var i = 0; i < parts.length; i++) ...[
                if (i > 0) const SizedBox(width: 4),
                _buildTimeBar(color: parts[i].$1, flex: parts[i].$2),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              for (final part in parts)
                _buildLegend(color: part.$1, label: part.$3),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExplanationCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: _navy, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  AppStrings.text('AI 경로 설명'),
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<String>(
            future: _explanationFor(_criteria),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        AppStrings.text('설명을 만드는 중입니다…'),
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
                    ),
                  ],
                );
              }
              if (snapshot.hasError) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _explanationErrorText(snapshot.error),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _retryExplanation,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(AppStrings.text('다시 시도')),
                      style: TextButton.styleFrom(
                        foregroundColor: _navy,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                );
              }
              return Text(
                snapshot.data!,
                style: const TextStyle(
                  color: _textColor,
                  fontSize: 14,
                  height: 1.6,
                ),
              );
            },
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

  /// 승차 → (환승 → 승차) … → 하차. 방면은 탑승 직후 다음 역이다.
  Widget _buildTimeline(RouteResult route) {
    if (route.segments.isEmpty) {
      return const SizedBox.shrink();
    }

    final steps = <Widget>[];
    for (var i = 0; i < route.segments.length; i++) {
      final segment = route.segments[i];
      final color = _lineColor(segment.line);
      final direction = segment.direction == null
          ? ''
          : ' · ${segment.direction!.name} 방면';

      steps.add(
        _buildTimelineStep(
          title: '${segment.board.name} 승차',
          subtitle: '${segment.line}호선$direction · ${segment.stops}개 역 이동',
          duration: '${minutesOf(segment.rideSec)}분',
          markerColor: color,
          lineColor: color,
          markerText: '${segment.line}',
        ),
      );

      if (i < route.transfers.length) {
        final transfer = route.transfers[i];
        steps.add(
          _buildTimelineStep(
            title: '${transfer.station.name} 환승',
            subtitle: '${transfer.fromLine}호선 → ${transfer.toLine}호선',
            duration: '${minutesOf(transfer.sec)}분',
            markerColor: _transferColor,
            lineColor: _border,
            transfer: true,
          ),
        );
      }
    }
    steps.add(
      _buildTimelineStep(
        title: '${route.end.name} 하차',
        markerColor: _lineColor(route.segments.last.line),
        isLast: true,
      ),
    );

    return Column(children: steps);
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
              Text(
                AppStrings.text(label),
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
