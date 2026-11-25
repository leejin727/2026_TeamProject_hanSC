// 화면 글자 표(l10n/strings.dart) 검사: 한국어·영어 표의 키와 채울 자리({n} 같은 것)가 같아야 한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:subway_app/l10n/strings.dart';
import 'package:subway_app/widgets/language_selector.dart';

Set<String> slots(String text) =>
    RegExp(r'\{(\w+)\}').allMatches(text).map((m) => m.group(1)!).toSet();

void main() {
  test('한국어 표와 영어 표의 키가 같다', () {
    expect(englishStrings.keys.toSet(), koreanStrings.keys.toSet());
  });

  test('같은 키는 채울 자리도 같다', () {
    for (final key in koreanStrings.keys) {
      expect(
        slots(englishStrings[key]!),
        slots(koreanStrings[key]!),
        reason: key,
      );
    }
  });

  test('비어 있는 글자가 없다 (영어 단위 "회"처럼 일부러 비운 것만 예외)', () {
    for (final entry in koreanStrings.entries) {
      expect(entry.value, isNotEmpty, reason: entry.key);
    }
    final emptyEnglish = englishStrings.entries
        .where((e) => e.value.isEmpty)
        .map((e) => e.key);
    expect(emptyEnglish, ['route.unitTimes']);
  });

  test('ko는 한국어, 그 밖의 언어는 모두 영어', () {
    expect(Tr.forLanguage(AppLanguage.korean)('nav.home'), '홈');
    for (final language in AppLanguage.values.skip(1)) {
      expect(
        Tr.forLanguage(language)('nav.home'),
        'Home',
        reason: language.code,
      );
    }
  });

  test('자리를 채우고, 사람·기준 이름을 만든다', () {
    expect(
      Tr.korean('route.summary', {'min': 42, 'n': 1}),
      '예상 소요 42분 · 환승 1회',
    );
    expect(
      Tr.english('route.summary', {'min': 42, 'n': 1}),
      'About 42 min · Transfers: 1',
    );
    expect(Tr.korean.person(0), '나');
    expect(Tr.english.person(2), 'Friend 2');
    expect(Tr.english.criteria('fairness'), 'Fairest');
    expect(Tr.korean('없는.키'), '없는.키'); // 없는 키는 키 그대로 (화면이 멈추지 않게)
  });
}
