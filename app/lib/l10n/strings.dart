// 화면 글자: 한국어·영어 두 가지 (외부 패키지 없이).
//
// 앱 언어가 ko면 한국어, 그 밖(en, ja, zh-Hans, zh-Hant, vi)이면 영어를 보여 준다 (챗봇 화면과 같은 규칙).
// 역 이름, AI 설명, 주변 시설은 서버가 준 언어 그대로 쓰므로 여기서 옮기지 않는다.
// 챗봇 화면(chat_screen.dart)은 자기 글자 표(_Labels)를 따로 쓴다.
//
// 새 글자를 넣을 때: 아래 두 표(koreanStrings, englishStrings)에 같은 키로 하나씩 넣는다.
// 두 표의 키가 같은지는 test/strings_test.dart가 확인한다.
import 'package:flutter/widgets.dart';

import '../widgets/language_selector.dart';

/// 화면에서 쓰는 법:
///   final t = Tr.of(context);
///   Text(t('nav.home'))
///   Text(t('route.summary', {'min': 42, 'n': 1}))   // 글자 안의 {min}, {n} 자리를 채운다
class Tr {
  const Tr._(this._table, this.isKorean);

  final Map<String, String> _table;

  /// 한국어로 보여 주는 중인지 (앱 언어가 ko일 때만 true)
  final bool isKorean;

  static const korean = Tr._(koreanStrings, true);
  static const english = Tr._(englishStrings, false);

  static Tr forLanguage(AppLanguage language) =>
      language == AppLanguage.korean ? korean : english;

  /// 화면을 그릴 때 부른다. main.dart의 [LanguageScope] 아래에서 부르면,
  /// 앱 언어가 바뀔 때 이 화면도 바로 다시 그려진다.
  static Tr of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LanguageScope>();
    return forLanguage(
      scope?.notifier?.value ?? LanguageSettings.selected.value,
    );
  }

  /// 지금 앱 언어의 글자 (화면을 그리는 중이 아닐 때. 예: 버튼을 눌렀을 때 띄우는 안내)
  static Tr get current => forLanguage(LanguageSettings.selected.value);

  String call(String key, [Map<String, Object?> args = const {}]) {
    var text = _table[key] ?? koreanStrings[key] ?? key;
    args.forEach((name, value) => text = text.replaceAll('{$name}', '$value'));
    return text;
  }

  /// 사람 이름표: 0번은 '나', 나머지는 '친구 1', '친구 2' …
  String person(int index) =>
      index == 0 ? call('person.me') : call('person.friend', {'n': index});

  /// 모임역 기준 이름: 'time', 'transfers', 'fairness'
  String criteria(String value) => call('criteria.$value');
}

/// 앱 언어가 바뀌면 [Tr.of]를 쓴 화면을 다시 그리게 한다. main.dart에서 MaterialApp을 감싼다.
class LanguageScope extends InheritedNotifier<ValueNotifier<AppLanguage>> {
  LanguageScope({super.key, required super.child})
    : super(notifier: LanguageSettings.selected);
}

const koreanStrings = <String, String>{
  // 공통
  'nav.home': '홈',
  'nav.favorites': '즐겨찾기',
  'nav.map': '노선도',
  'common.back': '뒤로가기',
  'common.retry': '다시 시도',
  'common.close': '닫기',
  'common.serverDown': '서버에 연결할 수 없습니다.\n서버가 켜져 있는지 확인해 주세요.',
  'common.serverDownShort': '서버에 연결할 수 없습니다.',
  'common.unknownError': '알 수 없는 오류가 발생했습니다.',
  'common.aiUnavailable': '지금은 AI 설명을 만들 수 없습니다. 잠시 후 다시 시도해 주세요.',
  'common.line': '{n}호선',
  'common.min': '{n}분',
  'common.stationNotFound': "'{name}' 역을 찾을 수 없습니다.",
  'common.favoriteAdd': '즐겨찾기 선택',
  'common.favoriteRemove': '즐겨찾기 해제',
  'common.whereTo': '어디로 가시나요?',
  'common.departureHint': '출발역 입력',
  'common.language': '언어 선택',
  'tab.route': '경로 검색',
  'tab.meeting': '모임역 추천',
  'criteria.time': '최단시간',
  'criteria.transfers': '최소환승',
  'criteria.fairness': '공평성',
  'person.me': '나',
  'person.friend': '친구 {n}',
  // 모임역 입력
  'meetingInput.subtitle': '각자의 출발역을 입력하면 만나기 좋은 역을 찾아드려요',
  'meetingInput.criteria': '추천 기준',
  'meetingInput.find': '추천역 찾기',
  'meetingInput.needDeparture': '{person}의 출발역을 입력해 주세요.',
  'meetingInput.departureOf': '{person}의 출발역',
  'meetingInput.remove': '{person} 삭제',
  'meetingInput.addFriend': '친구 추가 (나 포함 최대 4명)',
  'meetingInput.max': '최대 4명까지 입력할 수 있어요',
  // 모임역 결과
  'meetingResult.notFound': "{person}의 '{name}' 역을 찾을 수 없습니다.",
  'meetingResult.badCount': '참여 인원은 2~4명이어야 합니다.',
  'meetingResult.noStation': '모두가 갈 수 있는 모임역이 없습니다.',
  'meetingResult.myStation': '나의 출발역이 추천 만남역입니다.',
  'meetingResult.title': '추천 결과',
  'meetingResult.station': '추천 만남역',
  'meetingResult.summary': '평균 이동시간 {avg}분 · 최대 환승 {max}회',
  'meetingResult.reason': '추천 이유',
  'meetingResult.criteriaUsed': '선택한 기준: {criteria} · 참여 인원: {n}명',
  'meetingResult.travel': '{min}분 · 환승 {n}회',
  'meetingResult.aiReason': 'AI 추천 이유',
  'meetingResult.reasonLoading': '추천 이유를 만드는 중입니다…',
  'meetingResult.facilities': '주변 인프라',
  'meetingResult.facilitiesLoading': '주변 시설을 불러오는 중입니다…',
  'meetingResult.facilitiesError': '주변 시설을 불러오지 못했습니다.',
  'meetingResult.facilitiesEmpty': '주변 시설 정보가 없습니다.',
  'meetingResult.shareLater': '공유하기 기능은 추후 연결할 예정입니다.',
  'meetingResult.share': '공유하기',
  'meetingResult.route': '길찾기',
  // 경로 결과
  'route.sameStation': '출발역과 도착역이 같습니다.',
  'route.noRoute': '두 역을 잇는 경로가 없습니다.',
  'route.stopList': '정차역 목록',
  'route.stopCount': '출발역부터 도착역까지 {n}개 역',
  'route.detail': '상세 경로',
  'route.showStops': '정차역 모두 보기',
  'route.title': '경로 결과',
  'route.favoriteRemoved': '즐겨찾기에서 해제했습니다.',
  'route.favoriteAdded': '즐겨찾기에 추가했습니다. 앱 재시작 시 초기화됩니다.',
  'route.summary': '예상 소요 {min}분 · 환승 {n}회',
  'route.rideTime': '{line}호선 {min}분',
  'route.transferTime': '환승 {min}분',
  'route.total': '총 소요시간',
  'route.unitMin': '분',
  'route.transfers': '환승',
  'route.unitTimes': '회',
  'route.aiTitle': 'AI 경로 설명',
  'route.aiLoading': '설명을 만드는 중입니다…',
  'route.direction': ' · {name} 방면',
  'route.board': '{name} 승차',
  'route.rideInfo': '{line}호선{direction} · {n}개 역 이동',
  'route.transferAt': '{name} 환승',
  'route.lineChange': '{from}호선 → {to}호선',
  'route.alight': '{name} 하차',
  // 홈
  'home.bothNeeded': '출발역과 도착역을 모두 입력해 주세요.',
  'home.different': '출발역과 도착역을 다르게 입력해 주세요.',
  'home.subtitle': '출발역을 입력하면 가장 빠른 길을 찾아드려요',
  'home.chatbot': '챗봇',
  'home.from': '출발',
  'home.to': '도착',
  'home.arrivalHint': '도착역 입력',
  'home.swap': '출발역과 도착역 교환',
  'home.search': '경로 검색',
  'home.recent': '최근 검색',
  'home.seeAll': '전체보기',
  'home.deleteRecent': '{from} → {to} 검색 기록 삭제',
  'home.noRecent': '최근 검색 기록이 없어요',
  'home.noRecentHint': '출발역과 도착역을 입력해 경로를 검색해 보세요.',
  'home.allRecent': '최근 검색 전체보기',
  'home.recentLimit': '최신순으로 최대 10개까지 표시돼요.',
  'home.clearRecent': '최근 검색 전체 삭제',
  'home.clearRecentNote': '검색 기록만 삭제되며 즐겨찾기는 유지돼요.',
  // 즐겨찾기
  'fav.title': '즐겨찾기',
  'fav.saved': '저장한 경로',
  'fav.count': '{n}개',
  'fav.note': '현재 즐겨찾기는 앱 실행 중에만 유지돼요.\n새로고침하거나 재시작하면 초기화됩니다.',
  'fav.empty': '아직 저장한 경로가 없어요',
  'fav.emptyHint': '최근 검색이나 경로 결과의 별을 눌러\n자주 찾는 경로를 추가해 보세요.',
  'fav.open': '경로 결과 보기 · 상세 정보는 예시',
  // 노선도
  'map.title': '노선도',
  'map.subtitle': '임시 노선도 · 역 번호로 검색할 수 있어요',
  'map.enterNumber': '역 번호를 입력해 주세요. 예: 101',
  'map.noMatch': '일치하는 역이 없어요. 현재는 임시 역 번호로 검색해 주세요.',
  'map.station': '역 {id}',
  'map.tempNumber': '임시 번호 {id} · {kind}',
  'map.transfer': '환승역',
  'map.regular': '일반역',
  'map.tempNote': '현재는 임시 노선 데이터입니다.\n역 이름과 실제 연결 정보는 추후 반영합니다.',
  'map.searchHint': '역 이름 또는 번호 검색',
  'map.search': '역 검색',
  'map.clear': '검색어 지우기',
  'map.all': '전체',
  'map.zoomIn': '확대',
  'map.zoomOut': '축소',
  'map.reset': '원래 크기',
};

const englishStrings = <String, String>{
  // 공통
  'nav.home': 'Home',
  'nav.favorites': 'Favorites',
  'nav.map': 'Map',
  'common.back': 'Back',
  'common.retry': 'Try again',
  'common.close': 'Close',
  'common.serverDown':
      "Can't reach the server.\nPlease check that it is running.",
  'common.serverDownShort': "Can't reach the server.",
  'common.unknownError': 'Something went wrong.',
  'common.aiUnavailable':
      "Can't write the AI explanation right now. Please try again later.",
  'common.line': 'Line {n}',
  'common.min': '{n} min',
  'common.stationNotFound': "Can't find the station '{name}'.",
  'common.favoriteAdd': 'Add to favorites',
  'common.favoriteRemove': 'Remove from favorites',
  'common.whereTo': 'Where are you going?',
  'common.departureHint': 'Departure station',
  'common.language': 'Language',
  'tab.route': 'Route',
  'tab.meeting': 'Meeting spot',
  'criteria.time': 'Fastest',
  'criteria.transfers': 'Fewest transfers',
  'criteria.fairness': 'Fairest',
  'person.me': 'Me',
  'person.friend': 'Friend {n}',
  // 모임역 입력
  'meetingInput.subtitle':
      "Enter everyone's departure station and we'll find a good place to meet",
  'meetingInput.criteria': 'Recommend by',
  'meetingInput.find': 'Find a meeting station',
  'meetingInput.needDeparture':
      'Please enter a departure station for {person}.',
  'meetingInput.departureOf': 'Departure station for {person}',
  'meetingInput.remove': 'Remove {person}',
  'meetingInput.addFriend': 'Add a friend (up to 4 people, including you)',
  'meetingInput.max': 'You can add up to 4 people',
  // 모임역 결과
  'meetingResult.notFound': "Can't find the station '{name}' for {person}.",
  'meetingResult.badCount': 'You need 2 to 4 people.',
  'meetingResult.noStation': 'There is no station everyone can reach.',
  'meetingResult.myStation': 'Your departure station is the meeting station.',
  'meetingResult.title': 'Recommendation',
  'meetingResult.station': 'Meeting station',
  'meetingResult.summary': 'Average {avg} min · Up to {max} transfers',
  'meetingResult.reason': 'Why this station',
  'meetingResult.criteriaUsed': 'Recommended by: {criteria} · People: {n}',
  'meetingResult.travel': '{min} min · {n} transfers',
  'meetingResult.aiReason': 'AI explanation',
  'meetingResult.reasonLoading': 'Writing the explanation…',
  'meetingResult.facilities': 'Nearby places',
  'meetingResult.facilitiesLoading': 'Loading nearby places…',
  'meetingResult.facilitiesError': "Couldn't load nearby places.",
  'meetingResult.facilitiesEmpty': 'No nearby places.',
  'meetingResult.shareLater': 'Sharing is coming soon.',
  'meetingResult.share': 'Share',
  'meetingResult.route': 'Directions',
  // 경로 결과
  'route.sameStation': 'Departure and arrival are the same station.',
  'route.noRoute': 'There is no route between these stations.',
  'route.stopList': 'Stops',
  'route.stopCount': '{n} stations from departure to arrival',
  'route.detail': 'Route details',
  'route.showStops': 'Show all stops',
  'route.title': 'Route',
  'route.favoriteRemoved': 'Removed from favorites.',
  'route.favoriteAdded':
      'Added to favorites. Favorites reset when the app restarts.',
  'route.summary': 'About {min} min · {n} transfers',
  'route.rideTime': 'Line {line} {min} min',
  'route.transferTime': 'Transfer {min} min',
  'route.total': 'Total time',
  'route.unitMin': 'min',
  'route.transfers': 'Transfers',
  'route.unitTimes': '',
  'route.aiTitle': 'AI route guide',
  'route.aiLoading': 'Writing the explanation…',
  'route.direction': ' · toward {name}',
  'route.board': 'Board at {name}',
  'route.rideInfo': 'Line {line}{direction} · {n} stops',
  'route.transferAt': 'Transfer at {name}',
  'route.lineChange': 'Line {from} → Line {to}',
  'route.alight': 'Get off at {name}',
  // 홈
  'home.bothNeeded': 'Please enter both departure and arrival stations.',
  'home.different': 'Departure and arrival must be different stations.',
  'home.subtitle': "Enter your stations and we'll find the fastest way",
  'home.chatbot': 'Chatbot',
  'home.from': 'From',
  'home.to': 'To',
  'home.arrivalHint': 'Arrival station',
  'home.swap': 'Swap departure and arrival',
  'home.search': 'Search route',
  'home.recent': 'Recent searches',
  'home.seeAll': 'See all',
  'home.deleteRecent': 'Delete {from} → {to} from history',
  'home.noRecent': 'No recent searches',
  'home.noRecentHint':
      'Enter departure and arrival stations to search for a route.',
  'home.allRecent': 'All recent searches',
  'home.recentLimit': 'Shows up to 10, newest first.',
  'home.clearRecent': 'Clear recent searches',
  'home.clearRecentNote': 'Only the search history is deleted. Favorites stay.',
  // 즐겨찾기
  'fav.title': 'Favorites',
  'fav.saved': 'Saved routes',
  'fav.count': '{n}',
  'fav.note': 'Favorites are kept only while the app is running.\nThey reset when you reload or restart the app.',
  'fav.empty': 'No saved routes yet',
  'fav.emptyHint': 'Tap the star on a recent search or a route\nto save routes you use often.',
  'fav.open': 'View route · details are examples',
  // 노선도
  'map.title': 'Subway map',
  'map.subtitle': 'Temporary map · Search by station number',
  'map.enterNumber': 'Enter a station number. Example: 101',
  'map.noMatch': 'No matching station. For now, search by station number.',
  'map.station': 'Station {id}',
  'map.tempNumber': 'Temporary number {id} · {kind}',
  'map.transfer': 'Transfer station',
  'map.regular': 'Station',
  'map.tempNote': 'This map uses temporary data.\nStation names and real connections will be added later.',
  'map.searchHint': 'Search by station name or number',
  'map.search': 'Search stations',
  'map.clear': 'Clear search',
  'map.all': 'All',
  'map.zoomIn': 'Zoom in',
  'map.zoomOut': 'Zoom out',
  'map.reset': 'Reset zoom',
};
