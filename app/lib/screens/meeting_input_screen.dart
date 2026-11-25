import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import 'favorites_screen.dart';
import 'meeting_result_screen.dart';
import 'subway_map_screen.dart';
import '../widgets/language_selector.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);
const _border = Color(0xFFD2DAE6);

enum _RecommendationCriteria { fastest, fairest, fewestTransfers }

class MeetingInputScreen extends StatefulWidget {
  const MeetingInputScreen({super.key});

  @override
  State<MeetingInputScreen> createState() => _MeetingInputScreenState();
}

class _MeetingInputScreenState extends State<MeetingInputScreen> {
  // 처음에는 나와 친구 두 명의 입력창을 표시합니다.
  // 처음에는 나와 친구 1, 총 두 명의 입력창을 표시합니다.
  final List<TextEditingController> _controllers = [
    TextEditingController(),
    TextEditingController(),
  ];

  // 삭제된 입력창의 컨트롤러도 화면 종료 시 함께 정리합니다.
  final List<TextEditingController> _removedControllers = [];

  _RecommendationCriteria _criteria = _RecommendationCriteria.fastest;

  /// 화면 글자 (앱 언어가 ko면 한국어, 아니면 영어)
  Tr get _t => Tr.of(context);

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final controller in _removedControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _goHome() {
    Navigator.of(context).pop();
  }

  void _addFriend() {
    if (_controllers.length >= 4) {
      return;
    }

    setState(() {
      _controllers.add(TextEditingController());
    });
  }

  void _removeFriend(int index) {
    // 모임 추천을 위해 최소 두 명의 입력창은 유지합니다.
    if (index == 0 || _controllers.length <= 2) {
      return;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      final removed = _controllers.removeAt(index);
      _removedControllers.add(removed);
    });
  }

  void _findMeetingStation() {
    FocusScope.of(context).unfocus();

    for (var index = 0; index < _controllers.length; index++) {
      if (_controllers[index].text.trim().isEmpty) {
        final t = Tr.current;
        _showMessage(
          t('meetingInput.needDeparture', {'person': t.person(index)}),
        );
        return;
      }
    }

    final departures = _controllers
        .map((controller) => controller.text.trim())
        .toList();

    final String criteria; // 서버에 보내는 값 (api-spec.md 3장)

    switch (_criteria) {
      case _RecommendationCriteria.fastest:
        criteria = 'time';
        break;
      case _RecommendationCriteria.fairest:
        criteria = 'fairness';
        break;
      case _RecommendationCriteria.fewestTransfers:
        criteria = 'transfers';
        break;
    }
    final criteriaLabel = Tr.current.criteria(criteria);

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => MeetingResultScreen(
          departures: departures,
          criteria: criteria,
          criteriaLabel: criteriaLabel,
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
                        Text(
                          _t('common.whereTo'),
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _t('meetingInput.subtitle'),
                          style: const TextStyle(
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
                        _buildParticipantInputs(),
                        const SizedBox(height: 8),
                        _buildAddButton(),
                        const SizedBox(height: 26),
                        Text(
                          _t('meetingInput.criteria'),
                          style: const TextStyle(
                            color: _textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildCriteriaSelector(),
                        const SizedBox(height: 24),
                        FilledButton(
                          onPressed: _findMeetingStation,
                          style: FilledButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 62),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _t('meetingInput.find'),
                            style: const TextStyle(
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
                  child: CustomPaint(painter: _MeetingRoutePainter()),
                ),
                Positioned(
                  left: trainCenterX - 15.5,
                  top: 6.5,
                  child: Container(
                    width: 31,
                    height: 21,
                    decoration: BoxDecoration(
                      color: _navy,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildTrainWindow(),
                        const SizedBox(width: 5),
                        _buildTrainWindow(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrainWindow() {
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(2),
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
          _buildTab(
            label: _t('tab.route'),
            selected: false,
            onPressed: _goHome,
          ),
          _buildTab(label: _t('tab.meeting'), selected: true, onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildTab({
    required String label,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return Expanded(
      child: Semantics(
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
      ),
    );
  }

  Widget _buildParticipantInputs() {
    return Column(
      children: [
        for (var index = 0; index < _controllers.length; index++)
          Padding(
            key: ObjectKey(_controllers[index]),
            padding: EdgeInsets.only(
              bottom: index == _controllers.length - 1 ? 0 : 10,
            ),
            child: _buildParticipantField(index),
          ),
      ],
    );
  }

  Widget _buildParticipantField(int index) {
    final label = _t.person(index);
    final canRemove = index > 0 && _controllers.length > 2;

    return Container(
      padding: const EdgeInsets.only(left: 16, right: 4),
      decoration: BoxDecoration(
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            // 영어 이름표("Friend 1")는 한국어("친구 1")보다 길어서 칸을 넓힌다
            width: _t.isKorean ? 44 : 64,
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _navy,
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.only(left: 12, right: 14),
            color: _border,
          ),
          Expanded(
            child: TextField(
              controller: _controllers[index],
              textInputAction: index == _controllers.length - 1
                  ? TextInputAction.done
                  : TextInputAction.next,
              cursorColor: _navy,
              style: const TextStyle(
                color: _textColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                hintText: _t('common.departureHint'),
                hintStyle: const TextStyle(
                  color: _muted,
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 18),
                // 화면 읽기 도구에서도 사람을 구분할 수 있습니다.
                semanticCounterText: _t('meetingInput.departureOf', {
                  'person': label,
                }),
              ),
            ),
          ),
          if (canRemove)
            IconButton(
              onPressed: () => _removeFriend(index),
              tooltip: _t('meetingInput.remove', {'person': label}),
              icon: const Icon(Icons.close, color: _muted, size: 18),
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    final canAdd = _controllers.length < 4;

    return TextButton(
      onPressed: canAdd ? _addFriend : null,
      style: TextButton.styleFrom(
        backgroundColor: _lightBackground,
        foregroundColor: _navy,
        disabledForegroundColor: _muted,
        minimumSize: const Size(double.infinity, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(canAdd ? Icons.add : Icons.check, size: 19),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              canAdd ? _t('meetingInput.addFriend') : _t('meetingInput.max'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCriteriaSelector() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: _lightBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildCriteriaButton(
            label: _t.criteria('time'),
            value: _RecommendationCriteria.fastest,
          ),
          _buildCriteriaButton(
            label: _t.criteria('fairness'),
            value: _RecommendationCriteria.fairest,
          ),
          _buildCriteriaButton(
            label: _t.criteria('transfers'),
            value: _RecommendationCriteria.fewestTransfers,
          ),
        ],
      ),
    );
  }

  Widget _buildCriteriaButton({
    required String label,
    required _RecommendationCriteria value,
  }) {
    final selected = _criteria == value;

    return Expanded(
      child: Semantics(
        selected: selected,
        child: TextButton(
          onPressed: () {
            setState(() {
              _criteria = value;
            });
          },
          style: TextButton.styleFrom(
            foregroundColor: selected ? _navy : _muted,
            backgroundColor: selected ? Colors.white : Colors.transparent,
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            side: BorderSide(
              color: selected ? _navy : Colors.transparent,
              width: 1.5,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9),
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
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
            label: _t('nav.home'),
            icon: Icons.home_outlined,
            selected: true,
            onPressed: _goHome,
          ),
          _buildNavigationItem(
            label: _t('nav.favorites'),
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
            label: _t('nav.map'),
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

class _MeetingRoutePainter extends CustomPainter {
  const _MeetingRoutePainter();

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
  bool shouldRepaint(covariant _MeetingRoutePainter oldDelegate) => false;
}
