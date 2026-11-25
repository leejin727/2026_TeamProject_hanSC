// 홈 화면의 최근 검색 예시는 데이터에 있는 역만 써야 한다 (없는 역이면 눌렀을 때 "역을 찾을 수 없습니다").
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:subway_app/data/recent_routes.dart';

void main() {
  test('최근 검색 예시의 역은 모두 station_names.csv에 있다', () {
    // flutter test는 app 폴더에서 돈다
    final names = File('../data/extra/station_names.csv')
        .readAsLinesSync()
        .skip(1)
        .map((line) => line.split(',')[1])
        .toSet();
    expect(names, hasLength(111));

    for (final route in RecentRoutes.items.value) {
      for (final station in [route.departure, route.arrival]) {
        final name = names.contains(station)
            ? station
            : station.replaceFirst(RegExp(r'역$'), '');
        expect(names, contains(name), reason: station);
      }
    }
  });
}
