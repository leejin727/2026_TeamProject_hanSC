import 'package:flutter_test/flutter_test.dart';
import 'package:subway_app/main.dart';

void main() {
  testWidgets('SubFit 홈 화면이 표시된다', (WidgetTester tester) async {
    // 테스트 환경에 앱을 표시합니다.
    await tester.pumpWidget(const SubFitApp());

    // 홈 화면의 주요 문구가 각각 하나씩 있는지 확인합니다.
    expect(find.text('SubFit'), findsOneWidget);
    expect(find.text('어디로 가시나요?'), findsOneWidget);
  });
}
