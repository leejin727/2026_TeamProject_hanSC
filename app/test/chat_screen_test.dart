// 챗봇 화면 테스트. 진짜 서버 대신 가짜 응답(MockClient)을 쓰므로 서버 없이 돌아간다.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:subway_app/api/api_client.dart';
import 'package:subway_app/main.dart';
import 'package:subway_app/screens/chat_screen.dart';
import 'package:subway_app/screens/route_result_screen.dart';
import 'package:subway_app/widgets/language_selector.dart';

http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

const emptyContext = {
  'start': null,
  'end': null,
  'criteria': null,
  'asked': null,
};

/// POST /routes 응답 모양 (docs/api-spec.md 2장): 신도림 → 교대, 최소 환승
const directRoute = {
  'criteria': 'transfers',
  'start': {'id': '101', 'name': '신도림'},
  'end': {'id': '207', 'name': '교대'},
  'total_sec': 2950,
  'transfer_count': 0,
  'cost_won': 2360,
  'segments': [
    {
      'line': 2,
      'board': {'id': '101', 'name': '신도림'},
      'alight': {'id': '207', 'name': '교대'},
      'direction': {'id': '201', 'name': '문래'},
      'stations': [
        {'id': '101', 'name': '신도림'},
        {'id': '201', 'name': '문래'},
        {'id': '207', 'name': '교대'},
      ],
      'ride_sec': 2950,
    },
  ],
  'transfers': [],
};

/// POST /chat 응답 모양 (docs/api-spec.md 4-2장)
http.Response chatReply({
  required String text,
  String intent = 'faq',
  String topic = 'ticket',
  String lang = 'ko',
  Map<String, dynamic>? route,
  List<Map<String, dynamic>> phrases = const [],
  List<Map<String, dynamic>> options = const [],
  Map<String, dynamic> context = emptyContext,
}) => jsonResponse({
  'intent': intent,
  'topic': topic,
  'lang': lang,
  'text': text,
  'route': route,
  'phrases': phrases,
  'options': options,
  'context': context,
});

/// 가짜 서버. 받은 요청 본문을 [requests]에 모으고, [answer]가 만든 응답을 돌려준다.
class FakeServer {
  FakeServer(this.answer);

  final FutureOr<http.Response> Function(Map<String, dynamic> body) answer;
  final requests = <Map<String, dynamic>>[];

  late final api = ApiClient(
    baseUrl: 'http://test',
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      requests.add(body);
      return answer(body);
    }),
  );
}

Future<void> openChat(WidgetTester tester, FakeServer server) =>
    tester.pumpWidget(MaterialApp(home: ChatScreen(client: server.api)));

/// 입력창에 [text]를 쓰고 보내기 버튼을 누른 뒤, 답이 올 때까지 기다린다.
Future<void> send(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump();
  await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
  await tester.pumpAndSettle();
}

/// 버튼(OutlinedButton 또는 IconButton)을 지금 누를 수 있는지
bool canPress(WidgetTester tester, Finder finder) {
  final button = tester.widget(finder);
  return button is IconButton
      ? button.onPressed != null
      : (button as ButtonStyleButton).onPressed != null;
}

void main() {
  // 앱 언어는 앱 전체가 함께 쓰는 값이라, 테스트마다 한국어로 되돌린다
  setUp(() => LanguageSettings.selected.value = AppLanguage.korean);
  tearDown(() => LanguageSettings.selected.value = AppLanguage.korean);

  testWidgets('처음에는 인사와 예시 질문이 보이고, 예시를 누르면 그 말을 보낸다', (tester) async {
    final server = FakeServer(
      (body) => chatReply(text: '교통카드는 편의점에서 살 수 있어요.'),
    );
    await openChat(tester, server);

    expect(find.text('챗봇'), findsOneWidget);
    expect(find.textContaining('안녕하세요!'), findsOneWidget);
    expect(find.text('신도림에서 강남까지 어떻게 가?'), findsOneWidget);
    expect(find.text('역무원에게 보여 줄 문장 알려줘'), findsOneWidget);
    expect(server.requests, isEmpty); // 화면을 열기만 해서는 서버를 부르지 않는다

    await tester.tap(find.text('교통카드는 어디서 사요?'));
    await tester.pumpAndSettle();

    expect(server.requests.single, {'message': '교통카드는 어디서 사요?', 'lang': 'ko'});
    expect(find.text('교통카드는 어디서 사요?'), findsNWidgets(2)); // 예시 버튼 + 내가 보낸 말
    expect(find.text('교통카드는 편의점에서 살 수 있어요.'), findsOneWidget);
  });

  testWidgets('다음 요청에 직전 답의 context와 언어를 넣는다 (이어 묻기)', (tester) async {
    const askedStart = {
      'start': null,
      'end': '208',
      'criteria': 'time',
      'asked': 'start',
    };
    final server = FakeServer(
      (body) => body['message'] == 'How do I get to Gangnam?'
          ? chatReply(
              intent: 'route',
              topic: 'ask_start',
              lang: 'en',
              text: 'Where are you starting from? (Destination: Gangnam)',
              context: askedStart,
            )
          : chatReply(
              intent: 'route',
              topic: 'result',
              lang: 'en',
              text: 'Sindorim → Gangnam · 51 min · Transfers: 2 (fastest)',
            ),
    );
    await openChat(tester, server);

    // 앱 언어는 한국어인데 영어로 묻는 경우
    await send(tester, 'How do I get to Gangnam?');
    expect(
      find.text('Where are you starting from? (Destination: Gangnam)'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '',
    );

    // 이번에는 버튼 대신 키보드의 '보내기'로 보낸다
    await tester.enterText(find.byType(TextField), 'Sindorim');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pumpAndSettle();

    expect(server.requests, [
      {'message': 'How do I get to Gangnam?', 'lang': 'ko'},
      // 역 이름만 보내도 답이 영어로 이어지게, 직전 답의 언어(en)를 보낸다
      {'message': 'Sindorim', 'lang': 'en', 'context': askedStart},
    ]);
    expect(
      find.text('Sindorim → Gangnam · 51 min · Transfers: 2 (fastest)'),
      findsOneWidget,
    );
  });

  testWidgets('경로 답에는 경로 카드가 있고, 자세히 보기는 같은 기준으로 경로 결과 화면을 연다', (tester) async {
    final server = FakeServer(
      (body) => chatReply(
        intent: 'route',
        topic: 'result',
        text: '신도림 → 교대 · 49분 · 환승 0회 (최소 환승)',
        route: directRoute,
      ),
    );
    await openChat(tester, server);
    await send(tester, '신도림에서 교대까지 환승 없이');

    expect(find.text('신도림 → 교대 · 49분 · 환승 0회 (최소 환승)'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // 노선 번호
    expect(find.text('신도림 → 교대'), findsOneWidget); // 타는 역 → 내리는 역

    await tester.tap(find.text('자세히 보기'));
    await tester.pumpAndSettle();

    final screen = tester.widget<RouteResultScreen>(
      find.byType(RouteResultScreen),
    );
    expect(screen.departure, '신도림');
    expect(screen.arrival, '교대');
    expect(screen.criteria, 'transfers');
  });

  testWidgets('답에 딸린 버튼 글자는 답의 언어를 따른다 (한국어 앱에서 영어로 물었을 때)', (tester) async {
    final server = FakeServer(
      (body) => chatReply(
        intent: 'route',
        topic: 'result',
        lang: 'en',
        text: 'Sindorim → Gyodae · 49 min · Transfers: 0 (fewest transfers)',
        route: directRoute,
      ),
    );
    await openChat(tester, server);
    await send(tester, 'from Sindorim to Gyodae with no transfers');

    expect(find.text('View details'), findsOneWidget);
    expect(find.text('자세히 보기'), findsNothing);
    expect(find.text('챗봇'), findsOneWidget); // 화면 제목은 앱 언어(한국어) 그대로
  });

  testWidgets('문장 카드: 한국어 문장과 뜻(영어로 답할 때)을 보여 준다', (tester) async {
    final server = FakeServer(
      (body) => chatReply(
        intent: 'phrase',
        topic: 'list',
        lang: 'en',
        text: 'Here are Korean sentences you can show to the station staff.',
        phrases: [
          {
            'id': 'which_side',
            'korean': '어느 쪽에서 타야 하나요?',
            'meaning': 'Which side should I board from?',
          },
          {'id': 'no_korean', 'korean': '한국어를 잘 못해요.', 'meaning': null},
        ],
      ),
    );
    await openChat(tester, server);
    await send(tester, 'Show me useful Korean phrases');

    expect(find.text('어느 쪽에서 타야 하나요?'), findsOneWidget);
    expect(find.text('Which side should I board from?'), findsOneWidget);
    expect(find.text('한국어를 잘 못해요.'), findsOneWidget);
  });

  testWidgets('역이 여럿이면 버튼으로 고르고, 누르면 그 역 이름을 보낸다', (tester) async {
    const askedStart = {
      'start': null,
      'end': '208',
      'criteria': 'time',
      'asked': 'start',
    };
    final server = FakeServer(
      (body) => body['message'] == '종로에서 강남까지'
          ? chatReply(
              intent: 'route',
              topic: 'choose_station',
              text: '‘종로’ — 어느 역을 말씀하시나요?',
              options: [
                {'id': '107', 'name': '종로3가'},
                {'id': '108', 'name': '종로5가'},
              ],
              context: askedStart,
            )
          : chatReply(
              intent: 'route',
              topic: 'result',
              text: '종로3가 → 강남 · 77분 · 환승 1회 (최단 시간)',
            ),
    );
    await openChat(tester, server);
    await send(tester, '종로에서 강남까지');

    final option5 = find.widgetWithText(OutlinedButton, '종로5가');
    expect(canPress(tester, option5), isTrue);

    await tester.tap(find.widgetWithText(OutlinedButton, '종로3가'));
    await tester.pumpAndSettle();

    expect(server.requests.last, {
      'message': '종로3가',
      'lang': 'ko',
      'context': askedStart,
    });
    expect(find.text('종로3가 → 강남 · 77분 · 환승 1회 (최단 시간)'), findsOneWidget);
    // 지나간 질문의 버튼은 더 누를 수 없다
    expect(canPress(tester, option5), isFalse);
  });

  testWidgets('서버에 연결할 수 없으면 오류와 다시 시도를 보여 주고, 다시 시도는 같은 말을 같은 context로 보낸다', (
    tester,
  ) async {
    const afterRoute = {
      'start': '101',
      'end': '208',
      'criteria': 'time',
      'asked': null,
    };
    var serverUp = true;
    final server = FakeServer((body) {
      if (!serverUp) throw http.ClientException('Connection refused');
      return body['message'] == '신도림에서 강남까지'
          ? chatReply(
              intent: 'route',
              topic: 'result',
              text: '신도림 → 강남 · 51분 · 환승 2회 (최단 시간)',
              context: afterRoute,
            )
          : chatReply(
              intent: 'route',
              topic: 'result',
              text: '강남 → 신도림 · 51분 · 환승 2회 (최단 시간)',
            );
    });
    await openChat(tester, server);
    await send(tester, '신도림에서 강남까지');

    serverUp = false;
    await send(tester, '반대로는?');

    expect(find.textContaining('서버에 연결할 수 없습니다.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);

    serverUp = true;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();

    const reverse = {'message': '반대로는?', 'lang': 'ko', 'context': afterRoute};
    expect(server.requests.sublist(1), [reverse, reverse]);
    expect(find.text('반대로는?'), findsOneWidget); // 내 말풍선이 두 번 생기지 않는다
    expect(find.textContaining('서버에 연결할 수 없습니다.'), findsNothing);
    expect(find.text('다시 시도'), findsNothing);
    expect(find.text('강남 → 신도림 · 51분 · 환승 2회 (최단 시간)'), findsOneWidget);
  });

  testWidgets('챗봇을 쓸 수 없거나(503) 응답을 읽지 못해도 멈추지 않고 안내를 보여 준다', (tester) async {
    final server = FakeServer(
      (body) => body['message'] == '안녕'
          ? jsonResponse({
              'error': {
                'code': 'CHAT_UNAVAILABLE',
                'message': '지금은 챗봇을 쓸 수 없습니다',
              },
            }, 503)
          : jsonResponse({'unexpected': true}), // 4-2장과 다른 모양
    );
    await openChat(tester, server);

    await send(tester, '안녕');
    expect(find.textContaining('지금은 챗봇을 쓸 수 없습니다.'), findsOneWidget);

    await send(tester, '고마워');
    expect(find.textContaining('답을 받지 못했습니다.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('다시 시도'), findsOneWidget); // 마지막 오류에만 붙는다
  });

  testWidgets('새 대화를 누르면 대화가 지워지고, 다음 요청에 context를 넣지 않는다', (tester) async {
    final server = FakeServer(
      (body) => chatReply(
        intent: 'route',
        topic: 'result',
        lang: 'en',
        text: 'Sindorim → Gangnam · 51 min · Transfers: 2 (fastest)',
        context: const {
          'start': '101',
          'end': '208',
          'criteria': 'time',
          'asked': null,
        },
      ),
    );
    await openChat(tester, server);
    final newChat = find.widgetWithIcon(IconButton, Icons.add_comment_outlined);
    expect(canPress(tester, newChat), isFalse); // 지울 대화가 없다

    await send(tester, 'from Sindorim to Gangnam');
    await tester.tap(find.byTooltip('새 대화'));
    await tester.pumpAndSettle();

    expect(find.text('from Sindorim to Gangnam'), findsNothing);
    expect(
      find.text('Sindorim → Gangnam · 51 min · Transfers: 2 (fastest)'),
      findsNothing,
    );
    expect(find.textContaining('안녕하세요!'), findsOneWidget);

    await send(tester, '반대로는?');
    // 직전 대화의 context도, 직전 답의 언어(en)도 쓰지 않는다
    expect(server.requests.last, {'message': '반대로는?', 'lang': 'ko'});
  });

  testWidgets('답을 기다리는 동안에는 보낼 수 없고, 새 대화 뒤에 늦게 온 답은 버린다', (tester) async {
    final late = Completer<http.Response>();
    final server = FakeServer((body) => late.future);
    await openChat(tester, server);

    await tester.enterText(find.byType(TextField), '신도림에서 강남까지');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final sendButton = find.widgetWithIcon(
      IconButton,
      Icons.arrow_upward_rounded,
    );
    final example = find.widgetWithText(OutlinedButton, '교통카드는 어디서 사요?');
    await tester.enterText(find.byType(TextField), '그럼 반대로는?');
    await tester.pump();
    expect(canPress(tester, sendButton), isFalse);
    expect(canPress(tester, example), isFalse);
    // 키보드의 '보내기'로도 보낼 수 없고, 쓴 글은 입력창에 그대로 남는다
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    expect(server.requests.length, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '그럼 반대로는?',
    );

    await tester.tap(find.byTooltip('새 대화'));
    await tester.pump();
    late.complete(chatReply(text: '늦게 온 답'));
    await tester.pumpAndSettle();

    expect(find.text('늦게 온 답'), findsNothing);
    expect(find.text('신도림에서 강남까지'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(server.requests.length, 1);
    expect(canPress(tester, sendButton), isTrue); // 다시 보낼 수 있다
  });

  testWidgets('글은 서버가 받는 300자까지만 보낸다 (이모지도 서버와 같은 방법으로 센다)', (tester) async {
    final server = FakeServer((body) => chatReply(text: '답'));
    await openChat(tester, server);

    await tester.enterText(find.byType(TextField), '가' * 400);
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      '가' * 300, // 입력창이 300자에서 막는다
    );
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pumpAndSettle();
    expect(server.requests.last['message'], '가' * 300);

    // 가족 이모지 하나는 화면에서는 1글자지만 서버에서는 5글자(코드 포인트)다
    const family = '\u{1F468}‍\u{1F469}‍\u{1F467}';
    await send(tester, family * 100);
    final sent = server.requests.last['message'] as String;
    expect(sent.runes.length, 300);
    expect(sent, family * 60);
  });

  testWidgets('앱 언어가 한국어가 아니면 화면 글자는 영어이고, 서버에는 그 언어 코드를 보낸다', (tester) async {
    LanguageSettings.selected.value = AppLanguage.japanese;
    final server = FakeServer(
      (body) => chatReply(
        intent: 'out_of_scope',
        topic: 'unsupported_language',
        lang: 'en',
        text: 'For now I can only understand Korean and English.',
      ),
    );
    await openChat(tester, server);

    expect(find.text('Chatbot'), findsOneWidget);
    expect(find.textContaining('Ask me in Korean or English.'), findsOneWidget);
    expect(find.text('How do I get from Sindorim to Gangnam?'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(find.byTooltip('New chat'), findsOneWidget);

    await send(tester, '切符はどこで買えますか');
    expect(server.requests.single, {'message': '切符はどこで買えますか', 'lang': 'ja'});
    expect(
      find.text('For now I can only understand Korean and English.'),
      findsOneWidget,
    );
  });

  testWidgets('홈 화면의 챗봇 버튼을 누르면 챗봇 화면이 열리고, 뒤로가기로 돌아온다', (tester) async {
    await tester.pumpWidget(const SubFitApp());
    expect(find.byType(ChatScreen), findsNothing);

    await tester.tap(find.byTooltip('챗봇'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsOneWidget);
    expect(find.textContaining('안녕하세요!'), findsOneWidget);

    await tester.tap(find.byTooltip('뒤로가기'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatScreen), findsNothing);
    expect(find.text('어디로 가시나요?'), findsOneWidget);
  });
}
