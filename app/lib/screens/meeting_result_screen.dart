import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/subway_map_data.dart';
import '../widgets/language_selector.dart';
import 'favorites_screen.dart';
import 'route_result_screen.dart';
import 'subway_map_screen.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);
const _border = Color(0xFFD2DAE6);

/// 노선 색. 노선도 화면과 같은 색을 쓴다.
Color _lineColor(int line) {
  try {
    return SubwayMapData.colorForLine(line);
  } on ArgumentError {
    return _muted;
  }
}

/// 입력 화면과 같은 이름: 0번은 '나', 나머지는 '친구 1', '친구 2' …
String _personLabel(int index) => index == 0 ? '나' : '친구 $index';

class MeetingResultScreen extends StatefulWidget {
  const MeetingResultScreen({
    super.key,
    required this.departures,
    required this.criteria,
    required this.criteriaLabel,
  });

  /// 사람별로 입력한 출발역 이름 (2~4개)
  final List<String> departures;

  /// 서버에 보내는 기준: 'time', 'fairness', 'transfers'
  final String criteria;

  /// 화면에 보이는 기준 이름: '최단시간', '공평성', '최소환승'
  final String criteriaLabel;

  @override
  State<MeetingResultScreen> createState() => _MeetingResultScreenState();
}

class _MeetingResultScreenState extends State<MeetingResultScreen> {
  /// 입력한 역 이름들 → 역 ID들 (입력 순서 그대로)
  late Future<List<String>> _startIds;

  /// 모임역 결과 + 추천역이 지나는 노선 목록 (배지용)
  late Future<(MeetingResult, List<int>)> _result;

  /// AI 추천 이유. 결과와 따로 불러온다 (실패해도 결과는 보인다).
  Future<String>? _explanation;

  // 역 이름 데이터는 한국어·영어만 있다. 앱 언어가 한국어가 아니면 영어 이름을 쓴다.
  String get _nameLang =>
      LanguageSettings.selected.value.code == 'ko' ? 'ko' : 'en';

  // AI 설명은 앱에서 고른 언어 그대로 (ko, en, ja, zh-Hans, zh-Hant, vi)
  String get _explainLang => LanguageSettings.selected.value.code;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _startIds = _findStartIds();
    _result = _findMeetingStation();
    _explanation = null;
  }

  Future<List<String>> _findStartIds() async {
    final ids = <String>[];
    for (var i = 0; i < widget.departures.length; i++) {
      final name = widget.departures[i];
      final id = await apiClient.findStationId(name);
      if (id == null) {
        throw ApiException(
          'STATION_NOT_FOUND',
          "${_personLabel(i)}의 '$name' 역을 찾을 수 없습니다.",
        );
      }
      ids.add(id);
    }
    return ids;
  }

  Future<(MeetingResult, List<int>)> _findMeetingStation() async {
    final ids = await _startIds;
    final result = await apiClient.meeting(
      startIds: ids,
      criteria: widget.criteria,
      lang: _nameLang,
    );
    final station = await apiClient.stationById(result.station.id, _nameLang);
    return (result, station?.lines ?? const <int>[]);
  }

  Future<String> _explanationFuture() {
    return _explanation ??= _startIds.then(
      (ids) => apiClient.explainMeeting(
        startIds: ids,
        criteria: widget.criteria,
        lang: _nameLang,
        explainLang: _explainLang,
      ),
    );
  }

  void _retry() {
    setState(_load);
  }

  void _retryExplanation() {
    setState(() {
      _explanation = null;
    });
  }

  String _errorText(Object? error) {
    if (error is ApiException) {
      switch (error.code) {
        case 'NETWORK':
          return '서버에 연결할 수 없습니다.\n서버가 켜져 있는지 확인해 주세요.';
        case 'INVALID_PARTICIPANT_COUNT':
          return '참여 인원은 2~4명이어야 합니다.';
        case 'NO_MEETING_STATION':
          return '모두가 갈 수 있는 모임역이 없습니다.';
      }
      return error.message;
    }
    return '알 수 없는 오류가 발생했습니다.';
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  /// '나'의 출발역 → 추천역 길찾기 (경로 결과 화면을 그대로 쓴다)
  void _openRoute(MeetingResult result) {
    if (result.participants.first.start.id == result.station.id) {
      _showMessage('나의 출발역이 추천 만남역입니다.');
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RouteResultScreen(
          departure: widget.departures.first,
          arrival: result.station.name,
        ),
      ),
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
                  child: FutureBuilder<(MeetingResult, List<int>)>(
                    future: _result,
                    builder: (context, snapshot) {
                      final done =
                          snapshot.connectionState == ConnectionState.done;
                      final data = done && !snapshot.hasError
                          ? snapshot.data
                          : null;

                      return LayoutBuilder(
                        builder: (context, constraints) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minHeight: constraints.maxHeight > 40
                                    ? constraints.maxHeight - 40
                                    : 0,
                              ),
                              child: Column(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (!done)
                                    _buildLoading()
                                  else if (snapshot.hasError)
                                    _buildError(snapshot.error)
                                  else
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildRecommendationCard(
                                          data!.$1,
                                          data.$2,
                                        ),
                                        const SizedBox(height: 24),
                                        _buildReason(data.$1),
                                        const SizedBox(height: 26),
                                        _buildFacilities(),
                                      ],
                                    ),
                                  Padding(
                                    padding: const EdgeInsets.only(top: 32),
                                    child: _buildActionButtons(data?.$1),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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
            _errorText(error),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textColor,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 14),
          OutlinedButton(
            onPressed: _retry,
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: const BorderSide(color: _border),
            ),
            child: const Text('다시 시도'),
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
            tooltip: '뒤로가기',
            icon: const Icon(Icons.chevron_left, color: _navy),
          ),
          const Expanded(
            child: Text(
              '추천 결과',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildRecommendationCard(MeetingResult result, List<int> lines) {
    final people = result.participants.length;
    final averageMinutes = (result.totalTravelSec / people / 60).round();
    final maxTransfers = result.participants
        .map((p) => p.transferCount)
        .reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Text(
            '추천 만남역',
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            result.station.name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 29,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              for (final line in lines)
                _buildLineBadge(label: '$line호선', color: _lineColor(line)),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '평균 이동시간 $averageMinutes분 · 최대 환승 $maxTransfers회',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineBadge({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildReason(MeetingResult result) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '추천 이유',
          style: TextStyle(
            color: _textColor,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '선택한 기준: ${widget.criteriaLabel} · '
          '참여 인원: ${result.participants.length}명',
          style: const TextStyle(
            color: _textColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        // 사람별 이동 시간과 환승 횟수 (서버가 계산한 값)
        for (var i = 0; i < result.participants.length; i++)
          _buildParticipantRow(i, result.participants[i]),
        const SizedBox(height: 12),
        _buildExplanation(),
      ],
    );
  }

  Widget _buildParticipantRow(int index, MeetingParticipant participant) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${_personLabel(index)} · ${participant.start.name}',
              style: const TextStyle(color: _textColor, fontSize: 12),
            ),
          ),
          Text(
            '${minutesOf(participant.travelSec)}분 · '
            '환승 ${participant.transferCount}회',
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildExplanation() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _lightBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: _navy, size: 16),
              SizedBox(width: 6),
              Text(
                'AI 추천 이유',
                style: TextStyle(
                  color: _textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<String>(
            future: _explanationFuture(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Row(
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text(
                      '추천 이유를 만드는 중입니다…',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ],
                );
              }
              if (snapshot.hasError) {
                final error = snapshot.error;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      error is ApiException && error.code == 'NETWORK'
                          ? '서버에 연결할 수 없습니다.'
                          : '지금은 AI 설명을 만들 수 없습니다. 잠시 후 다시 시도해 주세요.',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _retryExplanation,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('다시 시도'),
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
                  fontSize: 12,
                  height: 1.7,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // 가상 노선이라 실제 주변 시설 데이터가 없다. 서버도 항상 빈 목록을 준다
  // (api-spec.md 논의 필요 4). 데이터와 항목 형식이 정해지면 여기에 목록을 그린다.
  Widget _buildFacilities() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '주변 인프라',
          style: TextStyle(
            color: _textColor,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 12),
        Text(
          '주변 시설 정보는 아직 제공되지 않습니다.',
          style: TextStyle(color: _muted, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }

  /// [result]가 없으면(불러오는 중·오류) 길찾기 버튼을 누를 수 없다.
  Widget _buildActionButtons(MeetingResult? result) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              _showMessage('공유하기 기능은 추후 연결할 예정입니다.');
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _textColor,
              side: const BorderSide(color: _border),
              minimumSize: const Size(0, 54),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.share_outlined, size: 18),
            label: const Text(
              '공유하기',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: result == null ? null : () => _openRoute(result),
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 54),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              '길찾기',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
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
