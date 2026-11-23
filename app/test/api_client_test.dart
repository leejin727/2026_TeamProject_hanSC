// ApiClient 테스트. 진짜 서버 대신 가짜 응답(MockClient)을 쓰므로 서버 없이 돌아간다.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:subway_app/api/api_client.dart';

// 실제 서버처럼 charset 없이 UTF-8 JSON을 보낸다 (한글이 깨지지 않는지 확인하려고)
http.Response jsonResponse(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

const stationsKo = {
  'stations': [
    {
      'id': '101',
      'name': '신도림',
      'lines': [1, 2],
    },
    {
      'id': '104',
      'name': '서울역',
      'lines': [1],
    },
    {
      'id': '207',
      'name': '교대',
      'lines': [2, 3],
    },
  ],
};
const stationsEn = {
  'stations': [
    {
      'id': '101',
      'name': 'Sindorim',
      'lines': [1, 2],
    },
    {
      'id': '104',
      'name': 'Seoul Station',
      'lines': [1],
    },
    {
      'id': '207',
      'name': "Seoul Nat'l Univ. of Education",
      'lines': [2, 3],
    },
  ],
};

// docs/api-spec.md 2장 첫 예시 (101 → 207, time)
const routeExample = {
  'criteria': 'time',
  'start': {'id': '101', 'name': '신도림'},
  'end': {'id': '207', 'name': '교대'},
  'total_sec': 2510,
  'transfer_count': 1,
  'cost_won': 4190,
  'segments': [
    {
      'line': 1,
      'board': {'id': '101', 'name': '신도림'},
      'alight': {'id': '123', 'name': '압구정'},
      'direction': {'id': '123', 'name': '압구정'},
      'stations': [
        {'id': '101', 'name': '신도림'},
        {'id': '123', 'name': '압구정'},
      ],
      'ride_sec': 480,
    },
    {
      'line': 3,
      'board': {'id': '123', 'name': '압구정'},
      'alight': {'id': '207', 'name': '교대'},
      'direction': {'id': '304', 'name': '신사'},
      'stations': [
        {'id': '123', 'name': '압구정'},
        {'id': '304', 'name': '신사'},
        {'id': '303', 'name': '고속터미널'},
        {'id': '302', 'name': '잠원'},
        {'id': '301', 'name': '남부터미널'},
        {'id': '207', 'name': '교대'},
      ],
      'ride_sec': 1730,
    },
  ],
  'transfers': [
    {
      'station': {'id': '123', 'name': '압구정'},
      'from_line': 1,
      'to_line': 3,
      'sec': 300,
    },
  ],
};

void main() {
  test('입력한 역 이름으로 역 ID를 찾는다 (역 목록은 언어별로 한 번만 받는다)', () async {
    final requests = <String>[];
    final api = ApiClient(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        requests.add(request.url.toString());
        return jsonResponse(
          request.url.queryParameters['lang'] == 'ko' ? stationsKo : stationsEn,
        );
      }),
    );

    expect(await api.findStationId('신도림'), '101');
    expect(await api.findStationId('신도림역'), '101');
    expect(await api.findStationId('Sindorim'), '101');
    expect(await api.findStationId(' sindorim '), '101');
    expect(await api.findStationId('101'), '101');
    expect(await api.findStationId('서울'), '104'); // 이름에 '역'이 들어 있는 역
    expect(await api.findStationId('서울역'), '104');
    expect(await api.findStationId('seoul station'), '104');
    expect(await api.findStationId('없는역'), isNull);
    expect(requests, [
      'http://test/stations?lang=ko',
      'http://test/stations?lang=en',
    ]);
  });

  test('경로 응답을 읽는다 (한글, 방면, 역 수, 환승)', () async {
    late Map<String, dynamic> sentBody;
    final api = ApiClient(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        expect(request.url.path, '/routes');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse(routeExample);
      }),
    );

    final route = await api.route(
      startId: '101',
      endId: '207',
      criteria: 'time',
      lang: 'ko',
    );

    expect(sentBody, {
      'start_station_id': '101',
      'end_station_id': '207',
      'criteria': 'time',
      'lang': 'ko',
    });
    expect(route.start.name, '신도림');
    expect(minutesOf(route.totalSec), 42);
    expect(route.transferCount, 1);
    expect(route.segments[1].direction?.name, '신사');
    expect(route.segments[1].stops, 5);
    expect(route.transfers.single.station.name, '압구정');
  });

  test('AI 설명 요청은 /routes와 같은 요청을 request에 넣어 보낸다', () async {
    late Map<String, dynamic> sentBody;
    final api = ApiClient(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        expect(request.url.path, '/explain');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return jsonResponse({
          'explanation': '신도림에서 1호선을 타세요.',
          'cached': false,
        });
      }),
    );

    final text = await api.explainRoute(
      startId: '101',
      endId: '207',
      criteria: 'transfers',
      lang: 'en',
      explainLang: 'ja',
    );

    expect(text, '신도림에서 1호선을 타세요.');
    expect(sentBody, {
      'type': 'route',
      'request': {
        'start_station_id': '101',
        'end_station_id': '207',
        'criteria': 'transfers',
        'lang': 'en',
      },
      'lang': 'ja',
    });
  });

  test('모임역 응답을 읽고, AI 설명은 같은 요청을 request에 넣어 보낸다', () async {
    final sent = <String, Map<String, dynamic>>{};
    final api = ApiClient(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        if (request.method == 'GET') return jsonResponse(stationsKo);
        sent[request.url.path] =
            jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path == '/explain') {
          return jsonResponse({
            'explanation': '모두의 이동 시간 합이 가장 작아요.',
            'cached': true,
          });
        }
        // docs/api-spec.md 3장 예시 (101·416·805 → 모란, time)에서 화면에 쓰는 값만
        return jsonResponse({
          'criteria': 'time',
          'station': {'id': '705', 'name': '모란'},
          'participants': [
            {
              'start': {'id': '101', 'name': '신도림'},
              'travel_sec': 4540,
              'transfer_count': 2,
            },
            {
              'start': {'id': '416', 'name': '노원'},
              'travel_sec': 900,
              'transfer_count': 0,
            },
            {
              'start': {'id': '805', 'name': '장지'},
              'travel_sec': 810,
              'transfer_count': 0,
            },
          ],
          'total_travel_sec': 6250,
          'total_transfer_count': 2,
          'max_travel_sec': 4540,
          'nearby_facilities': [],
        });
      }),
    );

    final result = await api.meeting(
      startIds: ['101', '416', '805'],
      criteria: 'time',
      lang: 'ko',
    );
    expect(sent['/meeting-station'], {
      'start_station_ids': ['101', '416', '805'],
      'criteria': 'time',
      'lang': 'ko',
    });
    expect(result.station.name, '모란');
    expect(
      [for (final p in result.participants) p.start.name],
      ['신도림', '노원', '장지'],
    );
    expect(minutesOf(result.participants.first.travelSec), 76);
    expect(result.totalTravelSec, 6250);

    final text = await api.explainMeeting(
      startIds: ['101', '416', '805'],
      criteria: 'fairness',
      lang: 'ko',
      explainLang: 'vi',
    );
    expect(text, '모두의 이동 시간 합이 가장 작아요.');
    expect(sent['/explain'], {
      'type': 'meeting',
      'request': {
        'start_station_ids': ['101', '416', '805'],
        'criteria': 'fairness',
        'lang': 'ko',
      },
      'lang': 'vi',
    });

    expect((await api.stationById('207', 'ko'))?.lines, [2, 3]);
    expect(await api.stationById('999', 'ko'), isNull);
  });

  test('서버 오류는 오류 코드로 바꾼다', () async {
    final api = ApiClient(
      baseUrl: 'http://test',
      client: MockClient(
        (request) async => jsonResponse({
          'error': {
            'code': 'AI_UNAVAILABLE',
            'message': '지금은 AI 설명을 만들 수 없습니다',
          },
        }, 503),
      ),
    );

    expect(
      () => api.explainRoute(
        startId: '101',
        endId: '207',
        criteria: 'time',
        lang: 'ko',
        explainLang: 'ko',
      ),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'AI_UNAVAILABLE'),
      ),
    );
  });

  test('서버에 연결할 수 없으면 NETWORK 오류, 다음에 다시 시도할 수 있다', () async {
    var serverUp = false;
    final api = ApiClient(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        if (!serverUp) throw http.ClientException('Connection refused');
        return jsonResponse(stationsKo);
      }),
    );

    await expectLater(
      api.stations('ko'),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')),
    );

    serverUp = true; // 실패한 결과를 저장해 두지 않았는지 확인
    expect((await api.stations('ko')).length, 3);
  });

  test('챗봇: 첫 메시지는 context 없이 보내고, 경로가 든 답을 읽는다', () async {
    late Map<String, dynamic> sentBody;
    final api = ApiClient(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        expect(request.url.path, '/chat');
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        // docs/api-spec.md 4-2장 응답 모양. route는 2장(POST /routes) 응답과 같다
        return jsonResponse({
          'intent': 'route',
          'topic': 'result',
          'lang': 'ko',
          'text': '신도림 → 교대 · 42분 · 환승 1회 (최단 시간)',
          'route': routeExample,
          'phrases': [],
          'options': [],
          'context': {
            'start': '101',
            'end': '207',
            'criteria': 'time',
            'asked': null,
          },
        });
      }),
    );

    final reply = await api.chat(message: '신도림에서 교대까지', lang: 'ko');

    // context 항목이 아예 없다 (null로도 보내지 않는다)
    expect(sentBody, {'message': '신도림에서 교대까지', 'lang': 'ko'});
    expect(reply.intent, 'route');
    expect(reply.topic, 'result');
    expect(reply.lang, 'ko');
    expect(reply.text, '신도림 → 교대 · 42분 · 환승 1회 (최단 시간)');
    expect(reply.route?.criteria, 'time');
    expect(reply.route?.start.name, '신도림');
    expect(reply.route?.segments.length, 2);
    expect(reply.phrases, isEmpty);
    expect(reply.options, isEmpty);
    expect(reply.context, {
      'start': '101',
      'end': '207',
      'criteria': 'time',
      'asked': null,
    });
  });

  test('챗봇: 직전 context를 그대로 돌려보내고, 역 선택과 문장 카드를 읽는다', () async {
    final sent = <Map<String, dynamic>>[];
    const askedStart = {
      'start': null,
      'end': '208',
      'criteria': 'time',
      'asked': 'start',
    };
    final api = ApiClient(
      baseUrl: 'http://test',
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        sent.add(body);
        if (body['message'] == 'from Jongno to Gangnam') {
          return jsonResponse({
            'intent': 'route',
            'topic': 'choose_station',
            'lang': 'en',
            'text': 'Which station do you mean by ‘Jongno’?',
            'route': null,
            'phrases': [],
            'options': [
              {'id': '107', 'name': 'Jongno 3(sam)-ga'},
              {'id': '108', 'name': 'Jongno 5(o)-ga'},
            ],
            'context': askedStart,
          });
        }
        return jsonResponse({
          'intent': 'emergency',
          'topic': 'feel_sick',
          'lang': body['lang'],
          'text': '급하면 119에 전화하세요.',
          'route': null,
          'phrases': [
            {
              'id': 'feel_sick',
              'korean': '몸이 아파요. 도와주세요.',
              'meaning': body['lang'] == 'en' ? 'I feel sick.' : null,
            },
          ],
          'options': [],
          // 진짜 서버처럼: 받은 context를 그대로 돌려주고, 없었으면 빈 context
          'context':
              body['context'] ??
              {'start': null, 'end': null, 'criteria': null, 'asked': null},
        });
      }),
    );

    final first = await api.chat(message: 'from Jongno to Gangnam', lang: 'ko');
    expect(first.route, isNull);
    expect(
      [for (final o in first.options) o.name],
      ['Jongno 3(sam)-ga', 'Jongno 5(o)-ga'],
    );
    expect(first.options.first.id, '107');

    // 직전 답의 context와 언어를 그대로 넣어 보낸다
    final second = await api.chat(
      message: 'I feel sick',
      lang: first.lang,
      context: first.context,
    );
    expect(sent.last, {
      'message': 'I feel sick',
      'lang': 'en',
      'context': askedStart,
    });
    expect(second.phrases.single.korean, '몸이 아파요. 도와주세요.');
    expect(second.phrases.single.meaning, 'I feel sick.');
    expect(second.context, askedStart); // 길찾기가 아닌 답은 context를 바꾸지 않는다

    final korean = await api.chat(message: '몸이 아파요', lang: 'ko');
    expect(korean.phrases.single.meaning, isNull); // 한국어로 답할 때는 뜻이 없다
  });

  test('챗봇을 쓸 수 없으면 CHAT_UNAVAILABLE 오류', () async {
    final api = ApiClient(
      baseUrl: 'http://test',
      client: MockClient(
        (request) async => jsonResponse({
          'error': {'code': 'CHAT_UNAVAILABLE', 'message': '지금은 챗봇을 쓸 수 없습니다'},
        }, 503),
      ),
    );

    expect(
      () => api.chat(message: '안녕', lang: 'ko'),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'CHAT_UNAVAILABLE'),
      ),
    );
  });
}
