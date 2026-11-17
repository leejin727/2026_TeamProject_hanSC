import 'package:flutter/foundation.dart';

class RecentRoute {
  const RecentRoute({required this.departure, required this.arrival});

  final String departure;
  final String arrival;
}

class RecentRoutes {
  RecentRoutes._();

  // 화면과 동작 확인을 위한 임의의 검색 기록입니다.
  // 위쪽일수록 최근 검색한 것으로 가정합니다.
  static final ValueNotifier<List<RecentRoute>> items =
      ValueNotifier<List<RecentRoute>>(const [
        RecentRoute(departure: '홍대입구역', arrival: '잠실역'),
        RecentRoute(departure: '서울역', arrival: '을지로3가역'),
        RecentRoute(departure: '강남역', arrival: '성수역'),
        RecentRoute(departure: '사당역', arrival: '서울역'),
        RecentRoute(departure: '건대입구역', arrival: '왕십리역'),
        RecentRoute(departure: '신도림역', arrival: '여의도역'),
        RecentRoute(departure: '수서역', arrival: '고속터미널역'),
        RecentRoute(departure: '노원역', arrival: '동대문역'),
        RecentRoute(departure: '종로3가역', arrival: '안국역'),
        RecentRoute(departure: '합정역', arrival: '이대역'),
      ]);

  static void add(String departure, String arrival) {
    final from = departure.trim();
    final to = arrival.trim();

    if (from.isEmpty || to.isEmpty || from == to) {
      return;
    }

    // 같은 경로가 있다면 기존 위치에서 제거합니다.
    final otherRoutes = items.value.where(
      (route) => !(route.departure == from && route.arrival == to),
    );

    // 새 검색을 맨 앞에 놓고 최신 10개만 유지합니다.
    items.value = List<RecentRoute>.unmodifiable(
      [RecentRoute(departure: from, arrival: to), ...otherRoutes].take(10),
    );
  }

  // 출발역과 도착역이 일치하는 검색 기록 하나를 삭제합니다.
  static void remove(String departure, String arrival) {
    final from = departure.trim();
    final to = arrival.trim();

    items.value = List<RecentRoute>.unmodifiable(
      items.value.where(
        (route) => !(route.departure == from && route.arrival == to),
      ),
    );
  }

  // 전체 검색 기록을 삭제합니다.
  static void clear() {
    items.value = const <RecentRoute>[];
  }
}
