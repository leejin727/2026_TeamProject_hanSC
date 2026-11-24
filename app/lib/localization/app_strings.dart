import '../widgets/language_selector.dart';

class AppStrings {
  AppStrings._();

  // 번역 배열 순서:
  // 영어, 일본어, 중국어 간체, 중국어 번체, 베트남어
  //
  // 한국어는 각 항목의 키를 그대로 사용합니다.
  static const Map<String, List<String>> _translations = {
    '경로 결과': ['Route results', 'ルート検索結果', '路线结果', '路線結果', 'Kết quả tìm đường'],
    '뒤로가기': ['Back', '戻る', '返回', '返回', 'Quay lại'],
    '상세 경로': ['Route details', 'ルート詳細', '路线详情', '路線詳情', 'Chi tiết lộ trình'],
    '정차역 모두 보기': [
      'View all stops',
      'すべての停車駅を見る',
      '查看所有停靠站',
      '查看所有停靠站',
      'Xem tất cả ga dừng',
    ],
    '정차역 목록': ['All stops', '停車駅一覧', '停靠站列表', '停靠站清單', 'Danh sách ga dừng'],
    '다시 시도': ['Try again', '再試行', '重试', '重試', 'Thử lại'],
    'AI 경로 설명': [
      'AI route guide',
      'AIルート案内',
      'AI路线说明',
      'AI路線說明',
      'Hướng dẫn lộ trình AI',
    ],
    '설명을 만드는 중입니다…': [
      'Preparing your guide…',
      '案内を作成しています…',
      '正在生成说明…',
      '正在產生說明…',
      'Đang tạo hướng dẫn…',
    ],
    '즐겨찾기에서 해제했습니다.': [
      'Removed from favorites.',
      'お気に入りから削除しました。',
      '已取消收藏。',
      '已取消收藏。',
      'Đã xóa khỏi mục yêu thích.',
    ],
    '즐겨찾기에 추가했습니다. 앱 재시작 시 초기화됩니다.': [
      'Added to favorites. Favorites reset when the app restarts.',
      'お気に入りに追加しました。アプリを再起動するとリセットされます。',
      '已添加到收藏。重启应用后收藏将重置。',
      '已加入收藏。重新啟動應用程式後收藏將重設。',
      'Đã thêm vào mục yêu thích. Danh sách sẽ được đặt lại khi khởi động lại ứng dụng.',
    ],

    '각자의 출발역을 입력하면 만나기 좋은 역을 찾아드려요': [
      'Enter everyone’s starting station to find a place to meet.',
      'それぞれの出発駅から、集まりやすい駅を探します。',
      '输入每个人的出发站，寻找适合见面的车站。',
      '輸入每個人的出發站，尋找適合見面的車站。',
      'Nhập ga xuất phát của từng người để tìm ga hẹn gặp.',
    ],
    '나': ['Me', '自分', '我', '我', 'Tôi'],
    '친구 {number}': [
      'Friend {number}',
      '友達 {number}',
      '朋友 {number}',
      '朋友 {number}',
      'Bạn {number}',
    ],
    '{person}의 출발역을 입력해 주세요.': [
      'Enter the starting station for {person}.',
      '{person}の出発駅を入力してください。',
      '请输入{person}的出发站。',
      '請輸入{person}的出發站。',
      'Vui lòng nhập ga xuất phát của {person}.',
    ],
    '{person}의 출발역': [
      'Starting station for {person}',
      '{person}の出発駅',
      '{person}的出发站',
      '{person}的出發站',
      'Ga xuất phát của {person}',
    ],
    '{person} 삭제': [
      'Remove {person}',
      '{person}を削除',
      '移除{person}',
      '移除{person}',
      'Xóa {person}',
    ],
    '친구 추가 (나 포함 최대 4명)': [
      'Add a friend (up to 4 people including you)',
      '友達を追加（自分を含めて最大4人）',
      '添加朋友（含自己最多4人）',
      '新增朋友（含自己最多4人）',
      'Thêm bạn (tối đa 4 người, bao gồm bạn)',
    ],
    '최대 4명까지 입력할 수 있어요': [
      'You can add up to 4 people',
      '最大4人まで入力できます',
      '最多可添加4人',
      '最多可新增4人',
      'Có thể thêm tối đa 4 người',
    ],
    '추천 기준': [
      'Recommendation criteria',
      'おすすめの基準',
      '推荐标准',
      '推薦標準',
      'Tiêu chí đề xuất',
    ],
    '최단시간': ['Fastest', '最短時間', '最短时间', '最短時間', 'Nhanh nhất'],
    '공평성': ['Fairness', '公平性', '公平性', '公平性', 'Công bằng'],
    '최소환승': ['Fewest transfers', '乗換最少', '最少换乘', '最少轉乘', 'Ít chuyển tuyến'],
    '추천역 찾기': [
      'Find a meeting station',
      '待ち合わせ駅を探す',
      '查找集合站',
      '尋找集合站',
      'Tìm ga hẹn gặp',
    ],

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
