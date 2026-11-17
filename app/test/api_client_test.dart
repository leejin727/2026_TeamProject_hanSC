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
    {'id': '101', 'name': '신도림', 'lines': [1, 2]},
    {'id': '104', 'name': '서울역', 'lines': [1]},
    {'id': '207', 'name': '교대', 'lines': [2, 3]},
  ],
};
const stationsEn = {
  'stations': [
    {'id': '101', 'name': 'Sindorim', 'lines': [1, 2]},
    {'id': '104', 'name': 'Seoul Station', 'lines': [1]},
    {'id': '207', 'name': "Seoul Nat'l Univ. of Education", 'lines': [2, 3]},
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
        return jsonResponse({'explanation': '신도림에서 1호선을 타세요.', 'cached': false});
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
}
