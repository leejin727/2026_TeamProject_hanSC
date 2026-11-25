// SubFit 서버(FastAPI) 호출. API 모양은 docs/api-spec.md를 따른다.
//
// 앱은 우리 서버만 부른다. Gemini 키 같은 비밀 값은 앱에 넣지 않는다 (AGENTS.md 보안).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

// Railway에 올린 SubFit 서버. 서버 주소가 바뀌면 여기만 고친다.
const _railwayServer = 'https://2026teamprojecthansc-production.up.railway.app';

/// 서버 주소. 기본은 Railway 서버라서 주소를 붙이지 않고 `flutter run`만 해도 된다
/// (iPhone 시뮬레이터, 안드로이드 에뮬레이터, 크롬, 실제 휴대폰 모두).
/// 내 컴퓨터에서 켠 서버로 시험할 때만 주소를 붙인다:
/// - iPhone 시뮬레이터·크롬: flutter run --dart-define=API_BASE_URL=http://localhost:8000
/// - 안드로이드 에뮬레이터: flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 (10.0.2.2 = 에뮬레이터를 실행한 내 컴퓨터)
/// - 실제 휴대폰: flutter run --dart-define=API_BASE_URL=http://내컴퓨터IP:8000
String get defaultApiBaseUrl {
  const override = String.fromEnvironment('API_BASE_URL');
  return override.isNotEmpty ? override : _railwayServer;
}

/// 서버 오류. [code]는 api-spec.md 5장의 오류 코드이거나, 서버에 닿지 못했을 때 'NETWORK'.
class ApiException implements Exception {
  ApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ApiException($code): $message';
}

/// 역 객체 {"id", "name"}. name은 요청한 언어(ko·en)의 이름.
class StationRef {
  const StationRef(this.id, this.name);

  factory StationRef.fromJson(Map<String, dynamic> json) =>
      StationRef(json['id'] as String, json['name'] as String);

  final String id;
  final String name;
}

/// GET /stations의 역 하나.
class Station {
  const Station(this.id, this.name, this.lines);

  factory Station.fromJson(Map<String, dynamic> json) => Station(
    json['id'] as String,
    json['name'] as String,
    (json['lines'] as List).cast<int>(),
  );

  final String id;
  final String name;
  final List<int> lines;
}

/// 한 노선을 이어서 탄 구간.
class RouteSegment {
  const RouteSegment({
    required this.line,
    required this.board,
    required this.alight,
    required this.direction,
    required this.stations,
    required this.rideSec,
  });

  factory RouteSegment.fromJson(Map<String, dynamic> json) => RouteSegment(
    line: json['line'] as int,
    board: StationRef.fromJson(json['board'] as Map<String, dynamic>),
    alight: StationRef.fromJson(json['alight'] as Map<String, dynamic>),
    direction: json['direction'] == null
        ? null
        : StationRef.fromJson(json['direction'] as Map<String, dynamic>),
    stations: [
      for (final s in json['stations'] as List)
        StationRef.fromJson(s as Map<String, dynamic>),
    ],
    rideSec: json['ride_sec'] as int,
  );

  final int line;
  final StationRef board;
  final StationRef alight;

  /// "○○ 방면"의 ○○ = 탑승 직후 다음 역 (ASSUMPTIONS.md 방면 안내 확정 사항)
  final StationRef? direction;

  /// 탑승역 ~ 하차역 (양 끝 포함)
  final List<StationRef> stations;
  final int rideSec;

  /// 이동하는 역 수 (탑승역 제외)
  int get stops => stations.length - 1;
}

class RouteTransfer {
  const RouteTransfer({
    required this.station,
    required this.fromLine,
    required this.toLine,
    required this.sec,
  });

  factory RouteTransfer.fromJson(Map<String, dynamic> json) => RouteTransfer(
    station: StationRef.fromJson(json['station'] as Map<String, dynamic>),
    fromLine: json['from_line'] as int,
    toLine: json['to_line'] as int,
    sec: json['sec'] as int,
  );

  final StationRef station;
  final int fromLine;
  final int toLine;
  final int sec;
}

/// POST /routes 응답 (api-spec.md 2장).
class RouteResult {
  const RouteResult({
    required this.criteria,
    required this.start,
    required this.end,
    required this.totalSec,
    required this.transferCount,
    required this.segments,
    required this.transfers,
  });

  factory RouteResult.fromJson(Map<String, dynamic> json) => RouteResult(
    criteria: json['criteria'] as String,
    start: StationRef.fromJson(json['start'] as Map<String, dynamic>),
    end: StationRef.fromJson(json['end'] as Map<String, dynamic>),
    totalSec: json['total_sec'] as int,
    transferCount: json['transfer_count'] as int,
    segments: [
      for (final s in json['segments'] as List)
        RouteSegment.fromJson(s as Map<String, dynamic>),
    ],
    transfers: [
      for (final t in json['transfers'] as List)
        RouteTransfer.fromJson(t as Map<String, dynamic>),
    ],
  );

  /// 이 경로를 계산한 기준: 'time'(최단시간) 또는 'transfers'(최소환승)
  final String criteria;
  final StationRef start;
  final StationRef end;
  final int totalSec;
  final int transferCount;
  final List<RouteSegment> segments;

  /// transfers[i]는 segments[i]와 segments[i + 1] 사이의 환승
  final List<RouteTransfer> transfers;
}

/// 모임역 결과의 사람 한 명.
class MeetingParticipant {
  const MeetingParticipant({
    required this.start,
    required this.travelSec,
    required this.transferCount,
  });

  factory MeetingParticipant.fromJson(Map<String, dynamic> json) =>
      MeetingParticipant(
        start: StationRef.fromJson(json['start'] as Map<String, dynamic>),
        travelSec: json['travel_sec'] as int,
        transferCount: json['transfer_count'] as int,
      );

  final StationRef start;
  final int travelSec;
  final int transferCount;
}

/// POST /meeting-station 응답 (api-spec.md 3장). 사람별 상세 경로(segments 등)는 아직 화면에서 쓰지 않아 읽지 않는다.
class MeetingResult {
  const MeetingResult({
    required this.station,
    required this.participants,
    required this.totalTravelSec,
    required this.maxTravelSec,
  });

  factory MeetingResult.fromJson(Map<String, dynamic> json) => MeetingResult(
    station: StationRef.fromJson(json['station'] as Map<String, dynamic>),
    participants: [
      for (final p in json['participants'] as List)
        MeetingParticipant.fromJson(p as Map<String, dynamic>),
    ],
    totalTravelSec: json['total_travel_sec'] as int,
    maxTravelSec: json['max_travel_sec'] as int,
  );

  final StationRef station;

  /// 요청한 출발역 순서 그대로
  final List<MeetingParticipant> participants;
  final int totalTravelSec;
  final int maxTravelSec;
}

/// 주변 시설 종류. 화면에는 늘 이 순서로 보여 준다.
const facilityCategories = [
  'cafe',
  'restaurant',
  'convenience_store',
  'pharmacy',
  'restroom',
];

/// GET /stations/{id}/facilities의 시설 하나 (api-spec.md 4-1장).
/// 응답의 ai_generated 값은 읽지 않는다: 화면에 쓰지 않기로 했다 (2026-11-25 이진 결정).
class Facility {
  const Facility({
    required this.category,
    required this.name,
    required this.detail,
  });

  factory Facility.fromJson(Map<String, dynamic> json) => Facility(
    category: json['category'] as String,
    name: json['name'] as String,
    detail: json['detail'] as String,
  );

  /// cafe, restaurant, convenience_store, pharmacy, restroom 중 하나
  final String category;
  final String name;

  /// 위치 안내 한 줄. 예: "2번 출구 · 도보 3분"
  final String detail;
}

/// 챗봇 답에 딸려 오는 문장 카드: 역무원에게 보여 줄 한국어 문장.
class ChatPhrase {
  const ChatPhrase({
    required this.id,
    required this.korean,
    required this.meaning,
  });

  factory ChatPhrase.fromJson(Map<String, dynamic> json) => ChatPhrase(
    id: json['id'] as String,
    korean: json['korean'] as String,
    meaning: json['meaning'] as String?,
  );

  final String id;
  final String korean;

  /// 문장의 뜻. 영어로 답할 때만 있고, 한국어로 답할 때는 null
  final String? meaning;
}

/// POST /chat 응답 (api-spec.md 4-2장).
class ChatReply {
  const ChatReply({
    required this.intent,
    required this.topic,
    required this.lang,
    required this.text,
    required this.route,
    required this.phrases,
    required this.options,
    required this.context,
  });

  factory ChatReply.fromJson(Map<String, dynamic> json) => ChatReply(
    intent: json['intent'] as String,
    topic: json['topic'] as String,
    lang: json['lang'] as String,
    text: json['text'] as String,
    route: json['route'] == null
        ? null
        : RouteResult.fromJson(json['route'] as Map<String, dynamic>),
    phrases: [
      for (final p in json['phrases'] as List)
        ChatPhrase.fromJson(p as Map<String, dynamic>),
    ],
    options: [
      for (final o in json['options'] as List)
        StationRef.fromJson(o as Map<String, dynamic>),
    ],
    context: json['context'] as Map<String, dynamic>,
  );

  /// 답의 종류 (route, faq, phrase, …)와 세부 종류. 화면은 이 값을 몰라도 그릴 수 있다.
  final String intent;
  final String topic;

  /// 답한 언어: 'ko' 또는 'en'
  final String lang;

  /// 보여 줄 답. 줄바꿈이 들어 있을 수 있다.
  final String text;

  /// 경로를 찾았을 때만 있다.
  final RouteResult? route;
  final List<ChatPhrase> phrases;

  /// 어느 역인지 골라야 할 때의 후보. 고른 역의 이름을 다음 메시지로 보내면 된다.
  final List<StationRef> options;

  /// 다음 요청에 그대로 돌려보낼 값 (이어 묻기용). 앱은 안을 들여다보지 않는다.
  final Map<String, dynamic> context;
}

/// 초 → 분 (반올림). 서버 AI 설명과 같은 방식.
int minutesOf(int seconds) => (seconds / 60).round();

class ApiClient {
  ApiClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? defaultApiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// 역 목록은 바뀌지 않으므로 언어별로 한 번만 받아 둔다.
  final Map<String, Future<List<Station>>> _stations = {};

  /// 주변 시설도 같은 역·언어면 바뀌지 않으므로 한 번만 받아 둔다 ('역 ID/언어' → 목록).
  final Map<String, Future<List<Facility>>> _facilities = {};

  Future<List<Station>> stations(String lang) {
    return _stations[lang] ??= _get('/stations?lang=$lang')
        .then(
          (json) => [
            for (final s in json['stations'] as List)
              Station.fromJson(s as Map<String, dynamic>),
          ],
        )
        .catchError((Object error) {
          _stations.remove(lang); // 실패한 결과는 저장하지 않는다 (다시 시도할 수 있게)
          throw error;
        });
  }

  /// 사용자가 입력한 역 이름 → 역 ID. 못 찾으면 null.
  /// '신도림', '신도림역', 'Sindorim', 'sindorim', '101' 모두 찾는다.
  Future<String?> findStationId(String input) async {
    final query = input.trim();
    final all = [...await stations('ko'), ...await stations('en')];
    for (final station in all) {
      if (station.id == query || _sameName(station.name, query)) {
        return station.id;
      }
    }
    return null;
  }

  static bool _sameName(String name, String query) {
    String normalize(String s) {
      final compact = s.replaceAll(' ', '').toLowerCase();
      // '서울역'처럼 이름에 '역'이 들어 있어도, 사용자가 '역'을 붙이든 빼든 찾는다
      return compact.endsWith('역')
          ? compact.substring(0, compact.length - 1)
          : compact;
    }

    return normalize(name) == normalize(query);
  }

  /// POST /routes. [criteria]는 'time'(최단시간) 또는 'transfers'(최소환승).
  Future<RouteResult> route({
    required String startId,
    required String endId,
    required String criteria,
    required String lang,
  }) async {
    final json = await _post('/routes', {
      'start_station_id': startId,
      'end_station_id': endId,
      'criteria': criteria,
      'lang': lang,
    });
    return RouteResult.fromJson(json);
  }

  /// 역 ID로 역 정보(이름, 노선)를 찾는다. 역 목록은 한 번만 받아 둔 것을 쓴다.
  Future<Station?> stationById(String id, String lang) async {
    for (final station in await stations(lang)) {
      if (station.id == id) return station;
    }
    return null;
  }

  /// POST /meeting-station. [criteria]는 'time'(최단시간), 'fairness'(공평성), 'transfers'(최소환승).
  Future<MeetingResult> meeting({
    required List<String> startIds,
    required String criteria,
    required String lang,
  }) async {
    final json = await _post('/meeting-station', {
      'start_station_ids': startIds,
      'criteria': criteria,
      'lang': lang,
    });
    return MeetingResult.fromJson(json);
  }

  /// GET /stations/{id}/facilities?lang=. [lang]은 앱 언어 코드 (ko, en, ja, zh-Hans, zh-Hant, vi).
  /// 늘 [facilityCategories] 순서로 돌려준다. 실패한 결과는 저장하지 않는다 (다시 시도할 수 있게).
  Future<List<Facility>> facilities(String stationId, String lang) {
    final key = '$stationId/$lang';
    return _facilities[key] ??=
        _get(
              '/stations/${Uri.encodeComponent(stationId)}/facilities'
              '?lang=${Uri.encodeQueryComponent(lang)}',
            )
            .then((json) {
              final items = [
                for (final f in json['facilities'] as List)
                  Facility.fromJson(f as Map<String, dynamic>),
              ];
              int rank(Facility f) {
                final i = facilityCategories.indexOf(f.category);
                return i < 0 ? facilityCategories.length : i;
              }

              items.sort((a, b) => rank(a).compareTo(rank(b)));
              return items;
            })
            .catchError((Object error) {
              _facilities.remove(key);
              throw error;
            });
  }

  /// POST /explain (type=route). 서버가 경로를 다시 계산해서 [explainLang]으로 설명한다.
  /// [lang]은 역 이름 언어(ko·en), [explainLang]은 설명 언어(ko, en, ja, zh-Hans, zh-Hant, vi).
  Future<String> explainRoute({
    required String startId,
    required String endId,
    required String criteria,
    required String lang,
    required String explainLang,
  }) => _explain('route', {
    'start_station_id': startId,
    'end_station_id': endId,
    'criteria': criteria,
    'lang': lang,
  }, explainLang);

  /// POST /explain (type=meeting). 서버가 모임역을 다시 계산해서 추천 이유를 설명한다.
  Future<String> explainMeeting({
    required List<String> startIds,
    required String criteria,
    required String lang,
    required String explainLang,
  }) => _explain('meeting', {
    'start_station_ids': startIds,
    'criteria': criteria,
    'lang': lang,
  }, explainLang);

  /// [request]에는 /routes 또는 /meeting-station에 보내는 요청 본문을 그대로 넣는다 (api-spec.md 4장).
  Future<String> _explain(
    String type,
    Map<String, dynamic> request,
    String explainLang,
  ) async {
    final json = await _post(
      '/explain',
      {'type': type, 'request': request, 'lang': explainLang},
      // 서버가 Gemini를 12초에 끊으므로 그보다 조금 더 기다린다
      timeout: const Duration(seconds: 15),
    );
    return json['explanation'] as String;
  }

  /// POST /chat. 챗봇에게 [message]를 보내고 답을 받는다.
  /// [lang]은 사용자가 쓴 언어를 알 수 없을 때(역 이름만 보냈을 때 등) 서버가 답할 언어:
  /// 첫 메시지는 앱의 언어 설정, 그 뒤로는 직전 답의 [ChatReply.lang]을 넣는다.
  /// [context]에는 직전 답의 [ChatReply.context]를 그대로 넣는다. 첫 메시지면 넣지 않는다.
  Future<ChatReply> chat({
    required String message,
    required String lang,
    Map<String, dynamic>? context,
  }) async {
    final json = await _post('/chat', {
      'message': message,
      'lang': lang,
      'context': ?context, // 없으면(null) 이 항목을 아예 보내지 않는다
    });
    return ChatReply.fromJson(json);
  }

  Future<Map<String, dynamic>> _get(String path) =>
      _send(() => _client.get(Uri.parse('$_baseUrl$path')));

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 10),
  }) => _send(
    () => _client.post(
      Uri.parse('$_baseUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    ),
    timeout: timeout,
  );

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException('NETWORK', '서버 응답이 너무 늦습니다.');
    } on Exception {
      // 서버가 꺼져 있음, 주소가 틀림 등 (http.ClientException, SocketException)
      throw ApiException('NETWORK', '서버에 연결할 수 없습니다.');
    }

    // 서버가 charset 없이 JSON을 보내므로 직접 UTF-8로 읽는다 (한글이 깨지지 않게)
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException('INTERNAL_ERROR', '서버 응답을 읽을 수 없습니다.');
    }
    if (response.statusCode == 200 && json is Map<String, dynamic>) {
      return json;
    }
    // 오류 모양: {"error": {"code", "message", "details"}} (api-spec.md 5장)
    final error = json is Map<String, dynamic> ? json['error'] : null;
    if (error is Map<String, dynamic>) {
      throw ApiException(
        error['code'] as String? ?? 'INTERNAL_ERROR',
        error['message'] as String? ?? '서버 오류',
      );
    }
    throw ApiException('INTERNAL_ERROR', '서버 오류 (${response.statusCode})');
  }
}

/// 앱 전체가 함께 쓰는 서버 연결 (역 목록을 한 번만 받기 위해).
final apiClient = ApiClient();
