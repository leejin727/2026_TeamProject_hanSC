import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/favorite_routes.dart';
import '../data/recent_routes.dart';
import '../localization/app_strings.dart';
import '../widgets/language_selector.dart';
import 'route_result_screen.dart';
import 'subway_map_screen.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);

String _t(String key, [Map<String, Object> values = const {}]) {
  var text = AppStrings.text(key);

  for (final entry in values.entries) {
    text = text.replaceAll('{${entry.key}}', entry.value.toString());
  }

  return text;
}

String _normalizeStationName(String value) {
  var text = value.replaceAll(RegExp(r'\s+'), '').toLowerCase();

  if (text.endsWith('역')) {
    text = text.substring(0, text.length - 1);
  }

  return text;
}

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  Map<String, String> _namesKo = const {};
  Map<String, String> _namesEn = const {};
  Map<String, String> _idByName = const {};

  bool _loadingNames = true;
  bool _nameLoadFailed = false;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _loadStationNames();
  }

  Future<void> _loadStationNames() async {
    final version = ++_loadVersion;

    setState(() {
      _loadingNames = true;
      _nameLoadFailed = false;
    });

    try {
      // 노선도와 동일한 역 목록 API를 사용합니다.
      // API에서 이미 받은 목록은 같은 실행 중 재사용합니다.
      final results = await Future.wait([
        apiClient.stations('ko'),
        apiClient.stations('en'),
      ]);

      if (!mounted || version != _loadVersion) return;

      final ko = <String, String>{
        for (final station in results[0]) station.id: station.name,
      };

      final en = <String, String>{
        for (final station in results[1]) station.id: station.name,
      };

      final idByName = <String, String>{};

      for (final stations in results) {
        for (final station in stations) {
          final key = _normalizeStationName(station.name);

          if (key.isNotEmpty) {
            idByName[key] = station.id;
          }
        }
      }

      setState(() {
        _namesKo = Map<String, String>.unmodifiable(ko);
        _namesEn = Map<String, String>.unmodifiable(en);
        _idByName = Map<String, String>.unmodifiable(idByName);
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

  // 저장된 한국어/영어 이름 또는 ID를 화면 언어의 이름으로 변환합니다.
  // FavoriteRoutes에 저장된 원본 값은 수정하지 않습니다.
  String _displayStationName(String savedValue) {
    final input = savedValue.trim();

    final String? id;
    if (_namesKo.containsKey(input) || _namesEn.containsKey(input)) {
      id = input;
    } else {
      id = _idByName[_normalizeStationName(input)];
    }

    if (id == null) return savedValue;

    final useKorean = LanguageSettings.selected.value == AppLanguage.korean;

    final translated = useKorean ? _namesKo[id] : _namesEn[id];

    if (translated == null || translated.trim().isEmpty) {
      return savedValue;
    }

    return translated;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageSettings.selected,
      builder: (context, language, child) {
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
                      child: ValueListenableBuilder<List<FavoriteRoute>>(
                        valueListenable: FavoriteRoutes.items,
                        builder: (context, routes, child) {
                          return ListView(
                            padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
                            children: [
                              _buildListHeading(routes.length),
                              const SizedBox(height: 18),
                              if (routes.isEmpty)
                                _buildEmptyState()
                              else ...[
                                _buildNameStatus(),
                                for (final route in routes)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: _buildRouteCard(route),
                                  ),
                              ],
                              const SizedBox(height: 6),
                              _buildStorageNotice(),
                            ],
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
      },
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
              _t('즐겨찾기'),
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

  Widget _buildListHeading(int count) {
    return Semantics(
      label: _t('저장한 경로 {count}개', {'count': count}),
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: Text(
              _t('저장한 경로'),
              style: const TextStyle(
                color: _textColor,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _t('{count}개', {'count': count}),
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildNameStatus() {
    if (_loadingNames) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _t('역 이름을 불러오는 중입니다…'),
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (!_nameLoadFailed) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t('역 이름을 불러오지 못했어요. 저장된 이름으로 표시합니다.'),
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.5),
          ),
          TextButton.icon(
            onPressed: _loadStationNames,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(_t('다시 시도')),
            style: TextButton.styleFrom(foregroundColor: _navy),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 34),
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: _lightBackground,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.star_border_rounded, color: _navy, size: 36),
          const SizedBox(height: 12),
          Text(
            _t('아직 저장한 경로가 없어요'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _t('최근 검색이나 경로 결과의 별을 눌러 자주 찾는 경로를 추가해 보세요.'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageNotice() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 15, color: _muted),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            _t(
              '현재 즐겨찾기는 앱 실행 중에만 유지돼요.\n'
              '새로고침하거나 재시작하면 초기화됩니다.',
            ),
            style: const TextStyle(color: _muted, fontSize: 11, height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteCard(FavoriteRoute route) {
    final departureName = _displayStationName(route.departure);
    final arrivalName = _displayStationName(route.arrival);

    return Material(
      color: _lightBackground,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                // 검색과 저장에는 기존 값을 사용합니다.
                RecentRoutes.add(route.departure, route.arrival);

                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => RouteResultScreen(
                      departure: route.departure,
                      arrival: route.arrival,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 19, 8, 19),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$departureName → $arrivalName',
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _t('경로 결과 보기'),
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              // 화면에 번역된 이름 대신 저장된 원본으로 해제합니다.
              FavoriteRoutes.toggle(route.departure, route.arrival);
            },
            tooltip: _t('즐겨찾기 해제'),
            icon: const Icon(Icons.star_rounded, color: _navy, size: 28),
          ),
          const SizedBox(width: 8),
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
            selected: false,
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          _buildNavigationItem(
            label: '즐겨찾기',
            icon: Icons.star_rounded,
            selected: true,
            onPressed: () {},
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
