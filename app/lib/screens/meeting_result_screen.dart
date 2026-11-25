import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/subway_map_data.dart';
import '../localization/app_strings.dart';
import '../widgets/language_selector.dart';
import 'favorites_screen.dart';
import 'route_result_screen.dart';
import 'subway_map_screen.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);
const _border = Color(0xFFD2DAE6);

Color _lineColor(int line) {
  try {
    return SubwayMapData.colorForLine(line);
  } on ArgumentError {
    return _muted;
  }
}

// 번역한 문장에 실제 이름, 시간, 인원 등을 넣습니다.
String _t(String key, [Map<String, Object> values = const {}]) {
  var text = AppStrings.text(key);

  for (final entry in values.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value.toString());
  }

  return text;
}

String _personLabel(int index) {
  return index == 0 ? _t('나') : _t('친구 {number}', {'number': index});
}

// 앱에서 역을 찾지 못한 경우 이름을 보관합니다.
// 표시할 때 번역하므로 언어가 바뀌어도 올바르게 표시됩니다.
class _UnknownMeetingStation implements Exception {
  const _UnknownMeetingStation(this.index, this.name);

  final int index;
  final String name;
}

class MeetingResultScreen extends StatefulWidget {
  const MeetingResultScreen({
    super.key,
    required this.departures,
    required this.criteria,
    required this.criteriaLabel,
  });

  final List<String> departures;
  final String criteria;
  final String criteriaLabel;

  @override
  State<MeetingResultScreen> createState() => _MeetingResultScreenState();
}

class _MeetingResultScreenState extends State<MeetingResultScreen> {
  late Future<List<String>> _startIds;
  late Future<(MeetingResult, List<int>)> _result;

  Future<String>? _explanation;

  String get _nameLang =>
      LanguageSettings.selected.value.code == 'ko' ? 'ko' : 'en';

  String get _explainLang => LanguageSettings.selected.value.code;

  String get _criteriaText {
    final key = switch (widget.criteria) {
      'time' => '최단시간',
      'fairness' => '공평성',
      'transfers' => '최소환승',
      _ => widget.criteriaLabel,
    };

    return _t(key);
  }

  @override
  void initState() {
    super.initState();
    LanguageSettings.selected.addListener(_onLanguageChanged);
    _load();
  }

  @override
  void dispose() {
    LanguageSettings.selected.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _onLanguageChanged() {
    if (!mounted) return;

    // 이름과 AI 설명도 변경된 언어로 다시 요청합니다.
    setState(_load);
  }

  void _load() {
    final nameLang = _nameLang;
    _startIds = _findStartIds();
    _result = _findMeetingStation(_startIds, nameLang);
    _explanation = null;
  }

  Future<List<String>> _findStartIds() async {
    final ids = <String>[];

    for (var i = 0; i < widget.departures.length; i++) {
      final name = widget.departures[i];
      final id = await apiClient.findStationId(name);

      if (id == null) {
        throw _UnknownMeetingStation(i, name);
      }

      ids.add(id);
    }

    return ids;
  }

  Future<(MeetingResult, List<int>)> _findMeetingStation(
    Future<List<String>> startIds,
    String nameLang,
  ) async {
    final ids = await startIds;

    final result = await apiClient.meeting(
      startIds: ids,
      criteria: widget.criteria,
      lang: nameLang,
    );

    final station = await apiClient.stationById(result.station.id, nameLang);

    return (result, station?.lines ?? const <int>[]);
  }

  Future<String> _explanationFuture() {
    final nameLang = _nameLang;
    final explainLang = _explainLang;

    return _explanation ??= _startIds.then(
      (ids) => apiClient.explainMeeting(
        startIds: ids,
        criteria: widget.criteria,
        lang: nameLang,
        explainLang: explainLang,
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
    if (error is _UnknownMeetingStation) {
      return _t('{person}의 "{station}" 역을 찾을 수 없습니다.', {
        'person': _personLabel(error.index),
        'station': error.name,
      });
    }

    if (error is ApiException) {
      switch (error.code) {
        case 'NETWORK':
          return _t('서버에 연결할 수 없습니다.\n서버가 켜져 있는지 확인해 주세요.');
        case 'INVALID_PARTICIPANT_COUNT':
          return _t('참여 인원은 2~4명이어야 합니다.');
        case 'NO_MEETING_STATION':
          return _t('모두가 갈 수 있는 모임역이 없습니다.');
        case 'STATION_NOT_FOUND':
          return _t('입력한 역을 찾을 수 없습니다.');
        default:
          return _t('추천 결과를 불러올 수 없습니다. 잠시 후 다시 시도해 주세요.');
      }
    }

    return _t('알 수 없는 오류가 발생했습니다.');
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openRoute(MeetingResult result) {
    if (result.participants.isEmpty) return;

    if (result.participants.first.start.id == result.station.id) {
      _showMessage(_t('나의 출발역이 추천 만남역입니다.'));
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
                                  else if (data != null)
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        _buildRecommendationCard(
                                          data.$1,
                                          data.$2,
                                        ),
                                        const SizedBox(height: 24),
                                        _buildReason(data.$1),
                                        const SizedBox(height: 26),
                                        _buildFacilities(),
                                      ],
                                    )
                                  else
                                    _buildError(null),
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
            child: Text(_t('다시 시도')),
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
            tooltip: _t('뒤로가기'),
            icon: const Icon(Icons.chevron_left, color: _navy),
          ),
          Expanded(
            child: Text(
              _t('추천 결과'),
              textAlign: TextAlign.center,
              style: const TextStyle(
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
    final averageMinutes = people == 0
        ? 0
        : (result.totalTravelSec / people / 60).round();

    final maxTransfers = result.participants.fold<int>(
      0,
      (current, person) =>
          person.transferCount > current ? person.transferCount : current,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 25),
      decoration: BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Text(
            _t('추천 만남역'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12),
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
                _buildLineBadge(
                  label: _t('{line}호선', {'line': line}),
                  color: _lineColor(line),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _t('평균 이동시간 {minutes}분 · 최대 환승 {count}회', {
              'minutes': averageMinutes,
              'count': maxTransfers,
            }),
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
        Text(
          _t('추천 이유'),
          style: const TextStyle(
            color: _textColor,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _t('선택한 기준: {criteria} · 참여 인원: {count}명', {
            'criteria': _criteriaText,
            'count': result.participants.length,
          }),
          style: const TextStyle(
            color: _textColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < result.participants.length; i++)
          _buildParticipantRow(i, result.participants[i]),
        const SizedBox(height: 12),
        _buildExplanation(),
      ],
    );
  }

  Widget _buildParticipantRow(int index, MeetingParticipant participant) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '${_personLabel(index)} · ${participant.start.name}',
              style: const TextStyle(
                color: _textColor,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _t('{minutes}분 · 환승 {count}회', {
                'minutes': minutesOf(participant.travelSec),
                'count': participant.transferCount,
              }),
              textAlign: TextAlign.right,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
            ),
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
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: _navy, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _t('AI 추천 이유'),
                  style: const TextStyle(
                    color: _textColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<String>(
            future: _explanationFuture(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _t('추천 이유를 만드는 중입니다…'),
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                  ],
                );
              }

              if (snapshot.hasError) {
                final error = snapshot.error;
                final message = error is ApiException && error.code == 'NETWORK'
                    ? '서버에 연결할 수 없습니다.'
                    : '지금은 AI 설명을 만들 수 없습니다. 잠시 후 다시 시도해 주세요.';

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _t(message),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _retryExplanation,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(_t('다시 시도')),
                      style: TextButton.styleFrom(
                        foregroundColor: _navy,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                );
              }

              return Text(
                snapshot.data ?? '',
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

  Widget _buildFacilities() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _t('주변 인프라'),
          style: const TextStyle(
            color: _textColor,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          _t('주변 시설 정보는 아직 제공되지 않습니다.'),
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.6),
        ),
      ],
    );
  }

  Widget _buildActionButtons(MeetingResult? result) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              _showMessage(_t('공유하기 기능은 추후 연결할 예정입니다.'));
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: _textColor,
              side: const BorderSide(color: _border),
              minimumSize: const Size(0, 54),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.share_outlined, size: 18),
            label: Text(
              _t('공유하기'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: result == null || result.participants.isEmpty
                ? null
                : () => _openRoute(result),
            style: FilledButton.styleFrom(
              backgroundColor: _navy,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 54),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              _t('길찾기'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
