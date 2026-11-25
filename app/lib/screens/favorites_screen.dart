import 'package:flutter/material.dart';

import '../data/favorite_routes.dart';
import '../l10n/strings.dart';
import 'route_result_screen.dart';
import '../data/recent_routes.dart';
import 'subway_map_screen.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

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
                  child: ValueListenableBuilder<List<FavoriteRoute>>(
                    valueListenable: FavoriteRoutes.items,
                    builder: (context, routes, child) {
                      return ListView(
                        padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
                        children: [
                          Row(
                            children: [
                              Text(
                                Tr.of(context)('fav.saved'),
                                style: const TextStyle(
                                  color: _textColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                Tr.of(context)('fav.count', {
                                  'n': routes.length,
                                }),
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          if (routes.isEmpty)
                            _buildEmptyState(context)
                          else
                            for (final route in routes)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: _buildRouteCard(context, route),
                              ),
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.info_outline,
                                size: 15,
                                color: _muted,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  Tr.of(context)('fav.note'),
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 11,
                                    height: 1.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
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
            tooltip: Tr.of(context)('common.back'),
            icon: const Icon(Icons.chevron_left, color: _navy),
          ),
          Expanded(
            child: Text(
              Tr.of(context)('fav.title'),
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

  Widget _buildEmptyState(BuildContext context) {
    final t = Tr.of(context);
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
            t('fav.empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textColor,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t('fav.emptyHint'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted, fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(BuildContext context, FavoriteRoute route) {
    return Material(
      color: _lightBackground,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
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
                      '${route.departure} → ${route.arrival}',
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      Tr.of(context)('fav.open'),
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: () {
              FavoriteRoutes.toggle(route.departure, route.arrival);
            },
            tooltip: Tr.of(context)('common.favoriteRemove'),
            icon: const Icon(Icons.star_rounded, color: _navy, size: 28),
          ),
          const SizedBox(width: 8),
        ],
      ),
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
            label: Tr.of(context)('nav.home'),
            icon: Icons.home_outlined,
            selected: false,
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
          _buildNavigationItem(
            label: Tr.of(context)('nav.favorites'),
            icon: Icons.star_rounded,
            selected: true,
            onPressed: () {},
          ),
          _buildNavigationItem(
            label: Tr.of(context)('nav.map'),
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
