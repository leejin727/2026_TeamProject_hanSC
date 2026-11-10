import 'package:flutter/material.dart';

import 'favorites_screen.dart';
import 'subway_map_screen.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);
const _border = Color(0xFFD2DAE6);

class MeetingResultScreen extends StatelessWidget {
  const MeetingResultScreen({
    super.key,
    required this.departures,
    required this.criteriaLabel,
  });

  final List<String> departures;
  final String criteriaLabel;

  void _showMessage(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _goHome(BuildContext context) {
    Navigator.of(context).popUntil((route) => route.isFirst);
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
                _buildHeader(context),
                Expanded(
                  child: LayoutBuilder(
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildRecommendationCard(),
                                  const SizedBox(height: 14),
                                  const Text(
                                    '디자인 확인용 예시입니다. 추천역·시간·'
                                    '시설 정보는 실제 조회 결과가 아닙니다.',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 11,
                                      height: 1.5,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _buildReason(),
                                  const SizedBox(height: 26),
                                  _buildFacilities(),
                                ],
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 32),
                                child: _buildActionButtons(context),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _buildBottomNavigation(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
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

  Widget _buildRecommendationCard() {
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
          const Text(
            '을지로3가역',
            textAlign: TextAlign.center,
            style: TextStyle(
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
              _buildLineBadge(label: '2호선', color: const Color(0xFF00AD50)),
              _buildLineBadge(label: '3호선', color: const Color(0xFFEF8421)),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            '평균 이동시간 24분 · 최대 환승 1회',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 12, height: 1.5),
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

  Widget _buildReason() {
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
          '선택한 기준: $criteriaLabel · 참여 인원: ${departures.length}명',
          style: const TextStyle(
            color: _textColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '출발역: ${departures.join(' · ')}',
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.6),
        ),
        const SizedBox(height: 10),
        const Text(
          '추천 이유 예시: 이동시간을 균형 있게 고려하고, '
          '모두 환승 1회 이내로 도착할 수 있는 역이에요.',
          style: TextStyle(color: _muted, fontSize: 12, height: 1.7),
        ),
      ],
    );
  }

  Widget _buildFacilities() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          '주변 인프라',
          style: TextStyle(
            color: _textColor,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        _buildFacilityRow(
          icon: Icons.local_cafe_outlined,
          label: '카페',
          detail: '1번 출구 · 도보 3분',
        ),
        _buildFacilityRow(
          icon: Icons.restaurant_outlined,
          label: '음식점',
          detail: '2번 출구 · 도보 3분',
        ),
        _buildFacilityRow(
          icon: Icons.storefront_outlined,
          label: '편의점',
          detail: '역 안 · 도보 1분',
        ),
        _buildFacilityRow(
          icon: Icons.local_pharmacy_outlined,
          label: '약국',
          detail: '3번 출구 · 도보 4분',
        ),
        _buildFacilityRow(
          icon: Icons.accessible_forward,
          label: '공중화장실',
          detail: '역 안 · 대합실',
          showDivider: false,
        ),
      ],
    );
  }

  Widget _buildFacilityRow({
    required IconData icon,
    required String label,
    required String detail,
    bool showDivider = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: _lightBackground))
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: _navy, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: _textColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              detail,
              textAlign: TextAlign.right,
              style: const TextStyle(color: _muted, fontSize: 11, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              _showMessage(context, '공유하기 기능은 추후 연결할 예정입니다.');
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
            onPressed: () {
              _showMessage(context, '추천역까지의 실제 길찾기는 데이터 연동 후 제공됩니다.');
            },
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

  Widget _buildBottomNavigation(BuildContext context) {
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
            onPressed: () => _goHome(context),
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
