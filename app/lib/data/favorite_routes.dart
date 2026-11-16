import 'package:flutter/foundation.dart';

class FavoriteRoute {
  const FavoriteRoute({required this.departure, required this.arrival});

  final String departure;
  final String arrival;
}

class FavoriteRoutes {
  FavoriteRoutes._();

  static final ValueNotifier<List<FavoriteRoute>> items =
      ValueNotifier<List<FavoriteRoute>>(const <FavoriteRoute>[]);

  static bool contains(String departure, String arrival) {
    return items.value.any(
      (route) =>
          route.departure == departure.trim() &&
          route.arrival == arrival.trim(),
    );
  }

  static void toggle(String departure, String arrival) {
    final from = departure.trim();
    final to = arrival.trim();

    if (from.isEmpty || to.isEmpty) {
      return;
    }

    if (contains(from, to)) {
      items.value = List<FavoriteRoute>.unmodifiable(
        items.value.where(
          (route) => !(route.departure == from && route.arrival == to),
        ),
      );
      return;
    }

    items.value = List<FavoriteRoute>.unmodifiable([
      ...items.value,
      FavoriteRoute(departure: from, arrival: to),
    ]);
  }
}
