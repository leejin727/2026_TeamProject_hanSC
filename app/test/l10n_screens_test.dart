// 화면 글자 한국어·영어 테스트: 앱 언어가 ko가 아니면 시연 화면의 주요 버튼이 영어로 보여야 한다.
// 서버를 부르는 화면은 가짜 서버(MockClient)를 쓴다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:subway_app/api/api_client.dart';
import 'package:subway_app/l10n/strings.dart';
import 'package:subway_app/data/favorite_routes.dart';
import 'package:subway_app/screens/favorites_screen.dart';
import 'package:subway_app/screens/home_screen.dart';
import 'package:subway_app/screens/meeting_input_screen.dart';
import 'package:subway_app/screens/meeting_result_screen.dart';
import 'package:subway_app/screens/route_result_screen.dart';
import 'package:subway_app/widgets/language_selector.dart';

Future<void> show(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(LanguageScope(child: MaterialApp(home: screen)));
  await tester.pumpAndSettle();
}

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

/// 가짜 서버: 역 이름은 요청한 언어(ko·en)로, 그 밖은 영어로 답한다.
ApiClient fakeClient() => ApiClient(
  baseUrl: 'http://test',
  client: MockClient((request) async {
    final path = request.url.path;
    final lang =
        request.url.queryParameters['lang'] ??
        (jsonDecode(request.body) as Map<String, dynamic>)['lang'] as String;
    final names = lang == 'ko'
        ? {
            '101': '신도림',
            '416': '노원',
            '805': '장지',
            '701': '먹골',
            '207': '교대',
            '201': '문래',
          }
        : {
            '101': 'Sindorim',
            '416': 'Nowon',
            '805': 'Jangji',
            '701': 'Meokgol',
            '207': "Seoul Nat'l Univ. of Education",
            '201': 'Mullae',
          };
    Map<String, Object?> ref(String id) => {'id': id, 'name': names[id]};
    switch (path) {
      case '/stations':
        return jsonResponse({
          'stations': [
            for (final e in names.entries)
              {
                'id': e.key,
                'name': e.value,
                'lines': [7],
              },
          ],
        });
      case '/meeting-station':
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
      case '/routes':
        return jsonResponse({
          'criteria':
              (jsonDecode(request.body) as Map<String, dynamic>)['criteria'],
          'start': ref('101'),
          'end': ref('207'),
          'total_sec': 3180,
          'transfer_count': 0,
          'cost_won': 2560,
          'segments': [
            {
              'line': 2,
              'board': ref('101'),
              'alight': ref('207'),
              'direction': ref('201'),
              'stations': [ref('101'), ref('201'), ref('207')],
              'ride_sec': 3180,
            },
          ],
          'transfers': [],
        });
      case '/explain':
        return jsonResponse({
          'explanation': 'Everyone arrives in 43 to 47 minutes.',
          'cached': true,
        });
      case '/stations/701/facilities':
        return jsonResponse({
          'station': ref('701'),
          'facilities': [
            {
              'category': 'cafe',
              'name': 'Starbucks Meokgol Station',
              'detail': 'Exit 1 · 1 min walk',
            },
          ],
          'ai_generated': true,
          'cached': true,
        });
    }
    return jsonResponse({
      'error': {'code': 'NOT_FOUND', 'message': path},
    }, 404);
  }),
);

void main() {
  setUp(() => LanguageSettings.selected.value = AppLanguage.korean);
  tearDown(() => LanguageSettings.selected.value = AppLanguage.korean);

  group('모임역 입력', () {
    testWidgets('영어 모드에서 주요 버튼이 영어', (tester) async {
      LanguageSettings.selected.value = AppLanguage.english;
      await show(tester, const MeetingInputScreen());
      for (final text in [
        'Find a meeting station',
        'Fastest',
        'Fairest',
        'Fewest transfers',
        'Me',
        'Friend 1',
        'Meeting spot',
        'Home',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
      expect(find.text('추천역 찾기'), findsNothing);
    });

    testWidgets('일본어를 고르면 영어로, 다시 한국어를 고르면 바로 한국어로', (tester) async {
      await show(tester, const MeetingInputScreen());
      expect(find.text('추천역 찾기'), findsOneWidget);

      LanguageSettings.selected.value = AppLanguage.japanese;
      await tester.pumpAndSettle();
      expect(find.text('Find a meeting station'), findsOneWidget);

      LanguageSettings.selected.value = AppLanguage.korean;
      await tester.pumpAndSettle();
      expect(find.text('추천역 찾기'), findsOneWidget);
    });

    testWidgets('빈 칸으로 찾으면 영어 안내가 뜬다', (tester) async {
      LanguageSettings.selected.value = AppLanguage.english;
      await show(tester, const MeetingInputScreen());
      final button = find.text('Find a meeting station');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(
        find.text('Please enter a departure station for Me.'),
        findsOneWidget,
      );
    });
  });

  group('모임역 결과', () {
    testWidgets('영어 모드에서 제목·버튼·기준이 영어이고 한국어 글자가 없다', (tester) async {
      LanguageSettings.selected.value = AppLanguage.english;
      await show(
        tester,
        MeetingResultScreen(
          departures: const ['신도림', '노원', '장지'],
          criteria: 'fairness',
          criteriaLabel: '공평성',
          client: fakeClient(),
        ),
      );
      for (final text in [
        'Recommendation',
        'Meeting station',
        'Why this station',
        'Recommended by: Fairest · People: 3',
        'Me · Sindorim',
        'Friend 1 · Nowon',
        '47 min · 2 transfers',
        'AI explanation',
        'Nearby places',
        'Share',
        'Directions',
        'Line 7',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.text('Starbucks Meokgol Station'), findsOneWidget);
      expect(find.textContaining(RegExp('[가-힣]')), findsNothing);
    });

    testWidgets('결과 화면에서 언어를 바꾸면 글자가 바로 바뀐다', (tester) async {
      await show(
        tester,
        MeetingResultScreen(
          departures: const ['신도림', '노원', '장지'],
          criteria: 'fairness',
          criteriaLabel: '공평성',
          client: fakeClient(),
        ),
      );
      expect(find.text('추천 만남역'), findsOneWidget);
      LanguageSettings.selected.value = AppLanguage.vietnamese;
      await tester.pumpAndSettle();
      expect(find.text('Meeting station'), findsOneWidget);
      expect(find.text('Starbucks Meokgol Station'), findsOneWidget);
    });

    testWidgets('한국어 모드는 예전 글자 그대로', (tester) async {
      await show(
        tester,
        MeetingResultScreen(
          departures: const ['신도림', '노원', '장지'],
          criteria: 'fairness',
          criteriaLabel: '공평성',
          client: fakeClient(),
        ),
      );
      for (final text in [
        '추천 결과',
        '추천 만남역',
        '선택한 기준: 공평성 · 참여 인원: 3명',
        '나 · 신도림',
        '47분 · 환승 2회',
        '주변 인프라',
        '길찾기',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
    });
  });

  group('홈', () {
    testWidgets('영어 모드에서 주요 버튼이 영어', (tester) async {
      LanguageSettings.selected.value = AppLanguage.english;
      await show(tester, const HomeScreen());
      for (final text in [
        'Where are you going?',
        'Search route',
        'Recent searches',
        'See all',
        'From',
        'To',
        'Route',
        'Meeting spot',
        'Home',
        'Favorites',
        'Map',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.byTooltip('Chatbot'), findsOneWidget);
      expect(find.text('경로 검색'), findsNothing);
    });

    testWidgets('빈 칸으로 검색하면 영어 안내가 뜬다', (tester) async {
      LanguageSettings.selected.value = AppLanguage.english;
      await show(tester, const HomeScreen());
      final button = find.text('Search route');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pump();
      expect(
        find.text('Please enter both departure and arrival stations.'),
        findsOneWidget,
      );
    });
  });

  group('즐겨찾기', () {
    testWidgets('영어 모드에서 글자가 영어', (tester) async {
      FavoriteRoutes.items.value = const [];
      LanguageSettings.selected.value = AppLanguage.english;
      await show(tester, const FavoritesScreen());
      for (final text in [
        'Favorites',
        'Saved routes',
        'No saved routes yet',
        'Home',
        'Map',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.textContaining(RegExp('[가-힣]')), findsNothing);
    });
  });

  group('경로 결과', () {
    testWidgets('영어 모드에서 제목·탭·상세 경로가 영어', (tester) async {
      LanguageSettings.selected.value = AppLanguage.english;
      await show(
        tester,
        RouteResultScreen(
          departure: 'Sindorim',
          arrival: "Seoul Nat'l Univ. of Education",
          client: fakeClient(),
        ),
      );
      for (final text in [
        'Route',
        'Fastest',
        'Fewest transfers',
        'About 53 min · 0 transfers',
        'AI route guide',
        'Route details',
        'Show all stops',
        'Total time',
        'Board at Sindorim',
        'Line 2 · toward Mullae · 2 stops',
        "Get off at Seoul Nat'l Univ. of Education",
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
      expect(find.textContaining(RegExp('[가-힣]')), findsNothing);
    });

    testWidgets('한국어 모드는 예전 글자 그대로', (tester) async {
      await show(
        tester,
        RouteResultScreen(
          departure: '신도림',
          arrival: '교대',
          client: fakeClient(),
        ),
      );
      for (final text in [
        '경로 결과',
        '최단시간',
        '예상 소요 53분 · 환승 0회',
        'AI 경로 설명',
        '상세 경로',
        '신도림 승차',
        '2호선 · 문래 방면 · 2개 역 이동',
        '교대 하차',
      ]) {
        expect(find.text(text), findsWidgets, reason: text);
      }
    });
  });
}
