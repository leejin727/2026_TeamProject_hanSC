// 화면 글자 한국어·영어 테스트: 앱 언어가 ko가 아니면 시연 화면의 주요 버튼이 영어로 보여야 한다.
// 서버를 부르는 화면은 가짜 서버(MockClient)를 쓴다.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subway_app/l10n/strings.dart';
import 'package:subway_app/screens/meeting_input_screen.dart';
import 'package:subway_app/widgets/language_selector.dart';

Future<void> show(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(LanguageScope(child: MaterialApp(home: screen)));
  await tester.pumpAndSettle();
}

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
}
