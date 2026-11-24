import '../widgets/language_selector.dart';

class AppStrings {
  AppStrings._();

  // 번역 배열 순서:
  // 영어, 일본어, 중국어 간체, 중국어 번체, 베트남어
  //
  // 한국어는 각 항목의 키를 그대로 사용합니다.
  static const Map<String, List<String>> _translations = {
    '출발': ['From', '出発', '出发', '出發', 'Từ'],
    '도착': ['To', '到着', '到达', '到達', 'Đến'],
    '출발역 입력': ['Starting station', '出発駅を入力', '输入出发站', '輸入出發站', 'Ga xuất phát'],
    '도착역 입력': ['Destination station', '到着駅を入力', '输入到达站', '輸入到達站', 'Ga đến'],
    '출발역과 도착역 교환': [
      'Swap stations',
      '出発駅と到着駅を入れ替え',
      '交换出发站和到达站',
      '交換出發站與到達站',
      'Đổi ga xuất phát và ga đến',
    ],
    '최근 검색': ['Recent searches', '最近の検索', '最近搜索', '最近搜尋', 'Tìm kiếm gần đây'],
    '전체보기': ['View all', 'すべて見る', '查看全部', '查看全部', 'Xem tất cả'],
    '최근 검색 전체보기': [
      'Search history',
      '検索履歴',
      '搜索历史',
      '搜尋紀錄',
      'Lịch sử tìm kiếm',
    ],
    '최신순으로 최대 10개까지 표시돼요.': [
      'Up to 10 searches, newest first.',
      '新しい順に最大10件表示します。',
      '按最新顺序显示，最多10条。',
      '依最新順序顯示，最多10筆。',
      'Hiển thị tối đa 10 lượt tìm kiếm, mới nhất trước.',
    ],
    '최근 검색 기록이 없어요': [
      'No recent searches',
      '検索履歴はありません',
      '暂无搜索记录',
      '尚無搜尋紀錄',
      'Chưa có tìm kiếm gần đây',
    ],
    '출발역과 도착역을 입력해 경로를 검색해 보세요.': [
      'Enter your starting and destination stations to find a route.',
      '出発駅と到着駅を入力して、ルートを検索してください。',
      '输入出发站和到达站，查询路线。',
      '輸入出發站與到達站，查詢路線。',
      'Nhập ga xuất phát và ga đến để tìm đường.',
    ],
    '최근 검색 전체 삭제': [
      'Clear search history',
      '検索履歴をすべて削除',
      '清空搜索历史',
      '清除搜尋紀錄',
      'Xóa lịch sử tìm kiếm',
    ],
    '검색 기록만 삭제되며 즐겨찾기는 유지돼요.': [
      'Only search history is deleted. Favorites are kept.',
      '検索履歴のみ削除します。お気に入りは残ります。',
      '仅删除搜索历史，收藏将保留。',
      '僅刪除搜尋紀錄，收藏將保留。',
      'Chỉ xóa lịch sử tìm kiếm. Mục yêu thích vẫn được giữ.',
    ],
    '검색 기록 삭제': [
      'Delete search',
      '検索履歴を削除',
      '删除搜索记录',
      '刪除搜尋紀錄',
      'Xóa lượt tìm kiếm',
    ],
    '즐겨찾기 선택': [
      'Add to favorites',
      'お気に入りに追加',
      '添加到收藏',
      '加入收藏',
      'Thêm vào yêu thích',
    ],
    '즐겨찾기 해제': [
      'Remove from favorites',
      'お気に入りから削除',
      '取消收藏',
      '取消收藏',
      'Bỏ yêu thích',
    ],
    '닫기': ['Close', '閉じる', '关闭', '關閉', 'Đóng'],
    '출발역과 도착역을 모두 입력해 주세요.': [
      'Enter both your starting and destination stations.',
      '出発駅と到着駅を両方入力してください。',
      '请输入出发站和到达站。',
      '請輸入出發站與到達站。',
      'Vui lòng nhập cả ga xuất phát và ga đến.',
    ],
    '출발역과 도착역을 다르게 입력해 주세요.': [
      'Choose different starting and destination stations.',
      '出発駅と到着駅は別の駅を指定してください。',
      '出发站和到达站不能相同。',
      '出發站與到達站不能相同。',
      'Vui lòng chọn ga xuất phát khác ga đến.',
    ],

    '어디로 가시나요?': [
      'Where are you going?',
      'どこへ行きますか？',
      '您要去哪里？',
      '您要去哪裡？',
      'Bạn muốn đi đâu?',
    ],
    '출발역을 입력하면 가장 빠른 길을 찾아드려요': [
      'Enter your starting station to find the fastest route.',
      '出発駅を入力すると、最も早いルートをご案内します。',
      '输入出发站，为您查找最快路线。',
      '輸入出發站，為您尋找最快路線。',
      'Nhập ga xuất phát để tìm tuyến đường nhanh nhất.',
    ],
    '경로 검색': ['Find a route', 'ルート検索', '路线查询', '路線查詢', 'Tìm đường'],
    '모임역 추천': ['Meeting station', '待ち合わせ駅', '推荐集合站', '推薦集合站', 'Ga hẹn gặp'],
    '홈': ['Home', 'ホーム', '首页', '首頁', 'Trang chủ'],
    '즐겨찾기': ['Favorites', 'お気に入り', '收藏', '收藏', 'Yêu thích'],
    '노선도': ['Route map', '路線図', '线路图', '路線圖', 'Sơ đồ tuyến'],
    '챗봇': ['Chatbot', 'チャットボット', '聊天助手', '聊天助手', 'Trợ lý trò chuyện'],
    '언어 선택': ['Select language', '言語を選択', '选择语言', '選擇語言', 'Chọn ngôn ngữ'],
  };

  static String text(String korean, {AppLanguage? language}) {
    final selected = language ?? LanguageSettings.selected.value;

    if (selected == AppLanguage.korean) {
      return korean;
    }

    final translations = _translations[korean];

    // 아직 번역하지 않은 문구는 한국어로 표시합니다.
    if (translations == null) {
      return korean;
    }

    final index = switch (selected) {
      AppLanguage.english => 0,
      AppLanguage.japanese => 1,
      AppLanguage.chineseSimplified => 2,
      AppLanguage.chineseTraditional => 3,
      AppLanguage.vietnamese => 4,
      AppLanguage.korean => 0,
    };

    return translations[index];
  }
}
