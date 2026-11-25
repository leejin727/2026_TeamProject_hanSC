// 모임역 결과 화면의 주변 시설 테스트. 진짜 서버 대신 가짜 응답(MockClient)을 쓰므로 서버 없이 돌아간다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:subway_app/api/api_client.dart';
import 'package:subway_app/screens/meeting_result_screen.dart';
import 'package:subway_app/widgets/language_selector.dart';

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

const _names = {
  'ko': {'101': '신도림', '416': '노원', '805': '장지', '701': '먹골'},
  'en': {'101': 'Sindorim', '416': 'Nowon', '805': 'Jangji', '701': 'Meokgol'},
};

/// 서버의 실제 응답 모양 (docs/api-spec.md 4-1장). 일부러 순서를 섞어 보낸다: 화면은 정해진 순서로 보여야 한다.
const _facilities = {
  'ko': [
    {'category': 'restroom', 'name': '역사 내 공중화장실', 'detail': '대합실 지하 1층'},
    {'category': 'cafe', 'name': '스타벅스 먹골역점', 'detail': '1번 출구 · 도보 1분'},
    {'category': 'restaurant', 'name': '먹골 숯불갈비', 'detail': '2번 출구 · 도보 3분'},
    {
      'category': 'convenience_store',
      'name': 'CU 먹골역점',
      'detail': '3번 출구 · 지하 1층',
    },
    {'category': 'pharmacy', 'name': '온누리 약국', 'detail': '4번 출구 · 도보 2분'},
  ],
  'en': [
    {
      'category': 'cafe',
      'name': 'Starbucks Meokgol Station',
      'detail': 'Exit 1 · 1 min walk',
    },
    {
      'category': 'restaurant',
      'name': 'Meokgol Charcoal Galbi',
      'detail': 'Exit 2 · 3 min walk',
    },
    {
      'category': 'convenience_store',
      'name': 'CU Meokgol Station',
      'detail': 'Exit 3 · B1',
    },
    {
      'category': 'pharmacy',
      'name': 'Onnuri Pharmacy',
      'detail': 'Exit 4 · 2 min walk',
    },
    {
      'category': 'restroom',
      'name': 'Station Public Restroom',
      'detail': 'Concourse B1',
    },
  ],
};

/// 가짜 서버: 역 목록, 모임역, 추천 이유, 주변 시설에 답한다.
class FakeServer {
  /// 주변 시설을 부른 언어를 부른 순서대로
  final facilityCalls = <String>[];

  /// 이 횟수만큼 주변 시설 요청에 503으로 답한다
  int failFacilities = 0;

  /// 있으면 이것이 끝날 때까지 주변 시설 응답을 붙잡아 둔다 (불러오는 중 화면을 보려고)
  Completer<void>? hold;

  late final client = ApiClient(
    baseUrl: 'http://test',
    client: MockClient((request) async {
      final path = request.url.path;
      final lang = request.url.queryParameters['lang'];
      if (path == '/stations') {
        final names = _names[lang]!;
        return jsonResponse({
          'stations': [
            for (final e in names.entries)
              {
                'id': e.key,
                'name': e.value,
                'lines': [1],
              },
          ],
        });
      }
      if (path == '/meeting-station') {
        final names = _names[jsonDecode(request.body)['lang']]!;
        StationRefJson ref(String id) => {'id': id, 'name': names[id]};
        return jsonResponse({
          'criteria': 'fairness',
          'station': ref('701'),
          'participants': [
            {'start': ref('101'), 'travel_sec': 2820, 'transfer_count': 2},
            {'start': ref('416'), 'travel_sec': 2580, 'transfer_count': 0},
            {'start': ref('805'), 'travel_sec': 2820, 'transfer_count': 1},
          ],
          'total_travel_sec': 8220,
          'max_travel_sec': 2820,
        });
      }
      if (path == '/explain') {
        return jsonResponse({
          'explanation': '세 사람 모두 43~47분 걸립니다.',
          'cached': true,
        });
      }
      if (path == '/stations/701/facilities') {
        facilityCalls.add(lang!);
        if (hold != null) await hold!.future;
        if (failFacilities > 0) {
          failFacilities--;
          return jsonResponse({
            'error': {
              'code': 'AI_UNAVAILABLE',
              'message': '지금은 주변 시설 정보를 만들 수 없습니다',
            },
          }, 503);
        }
        return jsonResponse({
          'station': {
            'id': '701',
            'name': _names[lang == 'ko' ? 'ko' : 'en']!['701'],
          },
          'facilities': _facilities[lang],
          'ai_generated': true,
          'cached': true,
        });
      }
      return jsonResponse({
        'error': {'code': 'NOT_FOUND', 'message': path},
      }, 404);
    }),
  );
}

typedef StationRefJson = Map<String, Object?>;

Future<FakeServer> openResult(WidgetTester tester, {FakeServer? server}) async {
  final fake = server ?? FakeServer();
  await tester.pumpWidget(
    MaterialApp(
      home: MeetingResultScreen(
        departures: const ['신도림', '노원', '장지'],
        criteria: 'fairness',
        criteriaLabel: '공평성',
        client: fake.client,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  setUp(() => LanguageSettings.selected.value = AppLanguage.korean);
  tearDown(() => LanguageSettings.selected.value = AppLanguage.korean);

  testWidgets('추천역 주변 시설을 정해진 순서로 보여 주고, AI가 만들었다는 글자는 없다', (tester) async {
    final server = await openResult(tester);

    expect(find.text('먹골'), findsWidgets); // 추천 만남역
    for (final name in [
      '스타벅스 먹골역점',
      '먹골 숯불갈비',
      'CU 먹골역점',
      '온누리 약국',
      '역사 내 공중화장실',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('1번 출구 · 도보 1분'), findsOneWidget);
    // 서버가 섞어 보내도 카페 → 음식점 → 편의점 → 약국 → 화장실 순서
    final cafe = tester.getTopLeft(find.text('스타벅스 먹골역점')).dy;
    final restaurant = tester.getTopLeft(find.text('먹골 숯불갈비')).dy;
    final restroom = tester.getTopLeft(find.text('역사 내 공중화장실')).dy;
    expect(cafe < restaurant && restaurant < restroom, isTrue);
    expect(find.byIcon(Icons.local_cafe_outlined), findsOneWidget);
    expect(find.byIcon(Icons.wc_outlined), findsOneWidget);

    // AI가 만든 예시라는 사실은 화면에 쓰지 않는다 (API의 ai_generated로만 구분, 2026-11-25 이진 결정)
    expect(find.textContaining('AI가 만든'), findsNothing);
    expect(find.textContaining('실제와 다를'), findsNothing);
    expect(find.textContaining('AI 예시'), findsNothing);
    expect(find.textContaining('아직 제공되지 않습니다'), findsNothing);
    expect(server.facilityCalls, ['ko']);
  });

  testWidgets('앱 언어를 바꾸면 그 언어로 다시 부르고, 같은 역·언어는 한 번만 부른다', (tester) async {
    final server = await openResult(tester);

    LanguageSettings.selected.value = AppLanguage.english;
    await tester.pumpAndSettle();
    expect(find.text('Starbucks Meokgol Station'), findsOneWidget);
    expect(find.text('스타벅스 먹골역점'), findsNothing);

    LanguageSettings.selected.value = AppLanguage.korean;
    await tester.pumpAndSettle();
    expect(find.text('스타벅스 먹골역점'), findsOneWidget);
    expect(server.facilityCalls, ['ko', 'en']); // 한국어로 돌아와도 다시 부르지 않는다
  });

  testWidgets('불러오지 못하면 짧은 안내와 다시 시도 버튼을 보여 준다', (tester) async {
    final server = await openResult(
      tester,
      server: FakeServer()..failFacilities = 1,
    );

    expect(find.text('주변 시설을 불러오지 못했습니다.'), findsOneWidget);
    expect(
      find.textContaining('주변 시설 정보를 만들 수 없습니다'),
      findsNothing,
    ); // 서버 문장은 그대로 보이지 않는다

    final retry = find.byKey(const Key('facilities-retry'));
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('스타벅스 먹골역점'), findsOneWidget);
    expect(server.facilityCalls, ['ko', 'ko']);
  });

  testWidgets('불러오는 동안은 불러오는 중이라고 보여 준다', (tester) async {
    final server = FakeServer()..hold = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: MeetingResultScreen(
          departures: const ['신도림', '노원', '장지'],
          criteria: 'fairness',
          criteriaLabel: '공평성',
          client: server.client,
        ),
      ),
    );
    // 돌고 있는 표시가 있어서 pumpAndSettle은 끝나지 않는다. 조금씩 시간을 보낸다
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(find.text('주변 인프라'), findsOneWidget); // 결과는 이미 보이고
    expect(find.text('주변 시설을 불러오는 중입니다…'), findsOneWidget); // 시설만 기다린다

    server.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('주변 시설을 불러오는 중입니다…'), findsNothing);
    expect(find.text('스타벅스 먹골역점'), findsOneWidget);
  });
}
