import '../widgets/language_selector.dart';

class AppStrings {
  AppStrings._();

  // 배열 순서:
  // 영어 → 일본어 → 중국어 간체 → 중국어 번체 → 베트남어
  //
  // 한국어는 각 항목의 키를 그대로 표시합니다.
  // {number}, {station} 같은 자리에는 화면 코드가 실제 값을 넣습니다.
  static const Map<String, List<String>> _translations = {
    // ─────────────────────────────────────
    // 공통 / 하단 메뉴 / 언어 선택
    // ─────────────────────────────────────
    '전체': ['All', 'すべて', '全部', '全部', 'Tất cả'],
    '역 이름 또는 번호 검색': [
      'Search by station name or number',
      '駅名または番号で検索',
      '搜索站名或编号',
      '搜尋站名或編號',
      'Tìm theo tên hoặc số ga',
    ],
    '역 검색': ['Search stations', '駅を検索', '搜索车站', '搜尋車站', 'Tìm ga'],
    '검색어 지우기': [
      'Clear search',
      '検索語を消去',
      '清除搜索内容',
      '清除搜尋內容',
      'Xóa nội dung tìm kiếm',
    ],
    '역 번호를 입력해 주세요. 예: 101': [
      'Enter a station number, for example 101.',
      '駅番号を入力してください。例：101',
      '请输入车站编号，例如101。',
      '請輸入車站編號，例如101。',
      'Nhập số ga, ví dụ: 101.',
    ],
    '일치하는 역이 없어요. 역 번호를 확인해 주세요.': [
      'No matching station. Please check the station number.',
      '一致する駅がありません。駅番号を確認してください。',
      '没有匹配的车站，请检查车站编号。',
      '沒有符合的車站，請確認車站編號。',
      'Không tìm thấy ga phù hợp. Vui lòng kiểm tra số ga.',
    ],
    '가상 노선도 · 역 번호로 검색할 수 있어요': [
      'Fictional route map · Search by station number',
      '架空の路線図 · 駅番号で検索できます',
      '虚拟线路图 · 可按车站编号搜索',
      '虛擬路線圖 · 可依車站編號搜尋',
      'Sơ đồ tuyến giả định · Tìm bằng số ga',
    ],
    '역 {number}': [
      'Station {number}',
      '駅 {number}',
      '车站 {number}',
      '車站 {number}',
      'Ga {number}',
    ],
    '역 번호 {number}': [
      'Station number {number}',
      '駅番号 {number}',
      '车站编号 {number}',
      '車站編號 {number}',
      'Số ga {number}',
    ],
    '환승역': ['Transfer station', '乗換駅', '换乘站', '轉乘站', 'Ga chuyển tuyến'],
    '일반역': ['Regular station', '一般駅', '普通站', '一般車站', 'Ga thường'],
    '프로젝트용 가상 노선도입니다.\n실제 지하철 노선과 다를 수 있습니다.': [
      'This is a fictional route map for the project.\nIt may differ from the real subway network.',
      'このプロジェクト用の架空の路線図です。\n実際の地下鉄路線とは異なる場合があります。',
      '这是项目使用的虚拟线路图。\n可能与实际地铁线路不同。',
      '這是專案使用的虛擬路線圖。\n可能與實際捷運路線不同。',
      'Đây là sơ đồ tuyến giả định dành cho dự án.\nCó thể khác với mạng lưới tàu điện ngầm thực tế.',
    ],
    '확대': ['Zoom in', '拡大', '放大', '放大', 'Phóng to'],
    '축소': ['Zoom out', '縮小', '缩小', '縮小', 'Thu nhỏ'],
    '원래 크기': ['Reset view', '表示をリセット', '重置视图', '重設檢視', 'Đặt lại chế độ xem'],
    '홈': ['Home', 'ホーム', '首页', '首頁', 'Trang chủ'],
    '즐겨찾기': ['Favorites', 'お気に入り', '收藏', '收藏', 'Yêu thích'],
    '노선도': ['Route map', '路線図', '线路图', '路線圖', 'Sơ đồ tuyến'],
    '챗봇': ['Chatbot', 'チャットボット', '聊天助手', '聊天助手', 'Trợ lý trò chuyện'],
    '언어 선택': ['Select language', '言語を選択', '选择语言', '選擇語言', 'Chọn ngôn ngữ'],
    '뒤로가기': ['Back', '戻る', '返回', '返回', 'Quay lại'],
    '닫기': ['Close', '閉じる', '关闭', '關閉', 'Đóng'],
    '다시 시도': ['Try again', '再試行', '重试', '重試', 'Thử lại'],

    // ─────────────────────────────────────
    // 홈 / 경로 검색 입력
    // ─────────────────────────────────────
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

    // ─────────────────────────────────────
    // 최근 검색
    // ─────────────────────────────────────
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

    // ─────────────────────────────────────
    // 즐겨찾기
    // ─────────────────────────────────────
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
    '저장한 경로': ['Saved routes', '保存したルート', '已保存路线', '已儲存路線', 'Lộ trình đã lưu'],
    '저장한 경로 {count}개': [
      'Saved routes: {count}',
      '保存したルート：{count}件',
      '已保存路线：{count}条',
      '已儲存路線：{count}條',
      'Lộ trình đã lưu: {count}',
    ],
    '{count}개': ['{count}', '{count}件', '{count}条', '{count}條', '{count}'],
    '아직 저장한 경로가 없어요': [
      'No saved routes yet',
      '保存したルートはまだありません',
      '暂无已保存路线',
      '尚無已儲存路線',
      'Chưa có lộ trình đã lưu',
    ],
    '최근 검색이나 경로 결과의 별을 눌러 자주 찾는 경로를 추가해 보세요.': [
      'Tap the star in recent searches or route results to save a route.',
      '最近の検索やルート検索結果の星をタップして、よく使うルートを保存しましょう。',
      '点击最近搜索或路线结果中的星标，保存常用路线。',
      '點選最近搜尋或路線結果中的星號，儲存常用路線。',
      'Nhấn vào ngôi sao trong tìm kiếm gần đây hoặc kết quả tìm đường để lưu lộ trình.',
    ],
    '현재 즐겨찾기는 앱 실행 중에만 유지돼요.\n새로고침하거나 재시작하면 초기화됩니다.': [
      'Favorites are currently kept only while the app is running.\nThey reset when you refresh or restart the app.',
      '現在、お気に入りはアプリの実行中のみ保持されます。\n再読み込みや再起動でリセットされます。',
      '收藏目前仅在应用运行期间保留。\n刷新或重启应用后将重置。',
      '收藏目前僅在應用程式執行期間保留。\n重新整理或重新啟動後將重設。',
      'Hiện tại, mục yêu thích chỉ được giữ khi ứng dụng đang chạy.\nDanh sách sẽ được đặt lại khi tải lại hoặc khởi động lại ứng dụng.',
    ],
    '경로 결과 보기': [
      'View route results',
      'ルート検索結果を見る',
      '查看路线结果',
      '查看路線結果',
      'Xem kết quả tìm đường',
    ],

    // ─────────────────────────────────────
    // 모임역 입력
    // ─────────────────────────────────────
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

    // ─────────────────────────────────────
    // 모임역 결과
    // ─────────────────────────────────────
    '추천 결과': ['Recommendation', 'おすすめの結果', '推荐结果', '推薦結果', 'Kết quả đề xuất'],
    '추천 만남역': [
      'Suggested meeting station',
      'おすすめの待ち合わせ駅',
      '推荐集合站',
      '推薦集合站',
      'Ga hẹn gặp được đề xuất',
    ],
    '추천 이유': ['Why this station?', 'おすすめの理由', '推荐理由', '推薦理由', 'Lý do đề xuất'],
    'AI 추천 이유': [
      'AI recommendation explanation',
      'AIによるおすすめの理由',
      'AI推荐理由',
      'AI推薦理由',
      'Giải thích đề xuất từ AI',
    ],
    '추천 이유를 만드는 중입니다…': [
      'Preparing the explanation…',
      'おすすめの理由を作成しています…',
      '正在生成推荐理由…',
      '正在產生推薦理由…',
      'Đang tạo lời giải thích…',
    ],
    '평균 이동시간 {minutes}분 · 최대 환승 {count}회': [
      'Average travel time: {minutes} min · Maximum transfers: {count}',
      '平均移動時間 {minutes}分 · 最大乗換回数 {count}回',
      '平均出行时间 {minutes}分钟 · 最多换乘 {count}次',
      '平均移動時間 {minutes}分鐘 · 最多轉乘 {count}次',
      'Thời gian trung bình: {minutes} phút · Số lần chuyển tuyến tối đa: {count}',
    ],
    '선택한 기준: {criteria} · 참여 인원: {count}명': [
      'Criteria: {criteria} · Participants: {count}',
      '選択した基準：{criteria} · 参加人数：{count}人',
      '所选标准：{criteria} · 参与人数：{count}人',
      '所選標準：{criteria} · 參與人數：{count}人',
      'Tiêu chí: {criteria} · Số người: {count}',
    ],
    '{minutes}분 · 환승 {count}회': [
      '{minutes} min · Transfers: {count}',
      '{minutes}分 · 乗換 {count}回',
      '{minutes}分钟 · 换乘 {count}次',
      '{minutes}分鐘 · 轉乘 {count}次',
      '{minutes} phút · Chuyển tuyến: {count} lần',
    ],
    '주변 인프라': [
      'Nearby facilities',
      '周辺施設',
      '周边设施',
      '周邊設施',
      'Tiện ích xung quanh',
    ],
    // 주변 시설 칸 (GET /stations/{id}/facilities): 불러오는 중 / 실패 / 없음
    '주변 시설을 불러오는 중입니다…': [
      'Loading nearby facilities…',
      '周辺施設を読み込んでいます…',
      '正在加载周边设施…',
      '正在載入周邊設施…',
      'Đang tải các tiện ích xung quanh…',
    ],
    '주변 시설을 불러오지 못했습니다.': [
      'Could not load nearby facilities.',
      '周辺施設を読み込めませんでした。',
      '无法加载周边设施。',
      '無法載入周邊設施。',
      'Không thể tải các tiện ích xung quanh.',
    ],
    '주변 시설 정보가 없습니다.': [
      'No information about nearby facilities.',
      '周辺施設の情報がありません。',
      '暂无周边设施信息。',
      '暫無周邊設施資訊。',
      'Không có thông tin về các tiện ích xung quanh.',
    ],
    '공유하기': ['Share', '共有', '分享', '分享', 'Chia sẻ'],
    '길찾기': ['Directions', 'ルート検索', '路线查询', '路線查詢', 'Tìm đường'],
    '공유하기 기능은 추후 연결할 예정입니다.': [
      'Sharing will be available in a future update.',
      '共有機能は今後のアップデートで追加予定です。',
      '分享功能将在后续更新中提供。',
      '分享功能將於後續更新提供。',
      'Tính năng chia sẻ sẽ có trong bản cập nhật sau.',
    ],
    '나의 출발역이 추천 만남역입니다.': [
      'Your starting station is the suggested meeting station.',
      'あなたの出発駅がおすすめの待ち合わせ駅です。',
      '您的出发站就是推荐集合站。',
      '您的出發站就是推薦集合站。',
      'Ga xuất phát của bạn chính là ga hẹn gặp được đề xuất.',
    ],

    // ─────────────────────────────────────
    // 길찾기 결과 / 시간 / 호선
    // ─────────────────────────────────────
    '경로 결과': ['Route results', 'ルート検索結果', '路线结果', '路線結果', 'Kết quả tìm đường'],
    '상세 경로': ['Route details', 'ルート詳細', '路线详情', '路線詳情', 'Chi tiết lộ trình'],
    '정차역 모두 보기': [
      'View all stops',
      'すべての停車駅を見る',
      '查看所有停靠站',
      '查看所有停靠站',
      'Xem tất cả ga dừng',
    ],
    '정차역 목록': ['All stops', '停車駅一覧', '停靠站列表', '停靠站清單', 'Danh sách ga dừng'],
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
    '예상 소요 {minutes}분 · 환승 {count}회': [
      'Estimated time: {minutes} min · Transfers: {count}',
      '所要時間の目安 {minutes}分 · 乗換 {count}回',
      '预计用时 {minutes}分钟 · 换乘 {count}次',
      '預計時間 {minutes}分鐘 · 轉乘 {count}次',
      'Thời gian dự kiến: {minutes} phút · Chuyển tuyến: {count} lần',
    ],
    '총 소요시간': ['Total time', '合計所要時間', '总用时', '總時間', 'Tổng thời gian'],
    '환승': ['Transfers', '乗換', '换乘', '轉乘', 'Chuyển tuyến'],
    '분': ['min', '分', '分钟', '分鐘', 'phút'],
    // 영어에서는 Transfers라는 제목 아래 숫자만 표시합니다.
    '회': ['', '回', '次', '次', 'lần'],
    '{minutes}분': [
      '{minutes} min',
      '{minutes}分',
      '{minutes}分钟',
      '{minutes}分鐘',
      '{minutes} phút',
    ],
    '환승 {minutes}분': [
      'Transfer: {minutes} min',
      '乗換 {minutes}分',
      '换乘 {minutes}分钟',
      '轉乘 {minutes}分鐘',
      'Chuyển tuyến: {minutes} phút',
    ],
    '{line}호선': [
      'Line {line}',
      '{line}号線',
      '{line}号线',
      '{line}號線',
      'Tuyến {line}',
    ],
    '{station} 승차': [
      'Board at {station}',
      '{station}で乗車',
      '在{station}上车',
      '在{station}上車',
      'Lên tàu tại {station}',
    ],
    '{station} 환승': [
      'Transfer at {station}',
      '{station}で乗換',
      '在{station}换乘',
      '在{station}轉乘',
      'Chuyển tuyến tại {station}',
    ],
    '{station} 하차': [
      'Get off at {station}',
      '{station}で下車',
      '在{station}下车',
      '在{station}下車',
      'Xuống tàu tại {station}',
    ],
    '{station} 방면': [
      'Toward {station}',
      '{station}方面',
      '往{station}方向',
      '往{station}方向',
      'Hướng {station}',
    ],
    '{count}개 역 이동': [
      'Stops: {count}',
      '{count}駅移動',
      '途经{count}站',
      '途經{count}站',
      'Đi qua {count} ga',
    ],
    '출발역부터 도착역까지 {count}개 역': [
      '{count} stations from start to destination',
      '出発駅から到着駅まで{count}駅',
      '从出发站到到达站共{count}站',
      '從出發站到到達站共{count}站',
      '{count} ga từ ga xuất phát đến ga đích',
    ],

    // ─────────────────────────────────────
    // 오류 / 서버 연결 / AI 설명 실패
    // ─────────────────────────────────────
    '서버에 연결할 수 없습니다.': [
      'Unable to connect to the server.',
      'サーバーに接続できません。',
      '无法连接服务器。',
      '無法連線至伺服器。',
      'Không thể kết nối với máy chủ.',
    ],
    '서버에 연결할 수 없습니다.\n서버가 켜져 있는지 확인해 주세요.': [
      'Unable to connect to the server.\nPlease check that the server is running.',
      'サーバーに接続できません。\nサーバーが起動しているか確認してください。',
      '无法连接服务器。\n请确认服务器正在运行。',
      '無法連線至伺服器。\n請確認伺服器正在運作。',
      'Không thể kết nối với máy chủ.\nVui lòng kiểm tra máy chủ đang hoạt động.',
    ],
    '참여 인원은 2~4명이어야 합니다.': [
      'There must be 2 to 4 participants.',
      '参加人数は2〜4人にしてください。',
      '参与人数必须为2至4人。',
      '參與人數必須為2至4人。',
      'Số người tham gia phải từ 2 đến 4.',
    ],
    '모두가 갈 수 있는 모임역이 없습니다.': [
      'No meeting station is reachable by everyone.',
      '全員が到達できる待ち合わせ駅がありません。',
      '没有所有人都能到达的集合站。',
      '沒有所有人都能到達的集合站。',
      'Không có ga hẹn gặp mà tất cả mọi người đều có thể đến.',
    ],
    '{person}의 "{station}" 역을 찾을 수 없습니다.': [
      'Cannot find "{station}" for {person}.',
      '{person}の「{station}」駅が見つかりません。',
      '找不到{person}输入的“{station}”站。',
      '找不到{person}輸入的「{station}」站。',
      'Không tìm thấy ga "{station}" của {person}.',
    ],
    '"{station}" 역을 찾을 수 없습니다.': [
      'Cannot find station "{station}".',
      '「{station}」駅が見つかりません。',
      '找不到“{station}”站。',
      '找不到「{station}」站。',
      'Không tìm thấy ga "{station}".',
    ],
    '입력한 역을 찾을 수 없습니다.': [
      'The entered station could not be found.',
      '入力した駅が見つかりません。',
      '找不到输入的车站。',
      '找不到輸入的車站。',
      'Không tìm thấy ga đã nhập.',
    ],
    '출발역과 도착역이 같습니다.': [
      'The starting and destination stations are the same.',
      '出発駅と到着駅が同じです。',
      '出发站与到达站相同。',
      '出發站與到達站相同。',
      'Ga xuất phát và ga đến giống nhau.',
    ],
    '두 역을 잇는 경로가 없습니다.': [
      'No route connects these two stations.',
      'この2駅を結ぶルートがありません。',
      '这两个车站之间没有可用路线。',
      '這兩個車站之間沒有可用路線。',
      'Không có tuyến đường nối hai ga này.',
    ],
    '추천 결과를 불러올 수 없습니다. 잠시 후 다시 시도해 주세요.': [
      'Unable to load the recommendation. Please try again later.',
      'おすすめの結果を読み込めません。しばらくしてから再試行してください。',
      '无法加载推荐结果，请稍后重试。',
      '無法載入推薦結果，請稍後重試。',
      'Không thể tải kết quả đề xuất. Vui lòng thử lại sau.',
    ],
    '경로를 불러올 수 없습니다. 잠시 후 다시 시도해 주세요.': [
      'Unable to load the route. Please try again later.',
      'ルートを読み込めません。しばらくしてから再試行してください。',
      '无法加载路线，请稍后重试。',
      '無法載入路線，請稍後重試。',
      'Không thể tải lộ trình. Vui lòng thử lại sau.',
    ],
    '알 수 없는 오류가 발생했습니다.': [
      'An unexpected error occurred.',
      '予期しないエラーが発生しました。',
      '发生未知错误。',
      '發生未知錯誤。',
      'Đã xảy ra lỗi không xác định.',
    ],
    '지금은 AI 설명을 만들 수 없습니다. 잠시 후 다시 시도해 주세요.': [
      'The AI explanation is unavailable right now. Please try again later.',
      '現在AIの説明を作成できません。しばらくしてから再試行してください。',
      '暂时无法生成AI说明，请稍后重试。',
      '目前無法產生AI說明，請稍後重試。',
      'Hiện không thể tạo lời giải thích từ AI. Vui lòng thử lại sau.',
    ],
  };

  static String text(String korean, {AppLanguage? language}) {
    final selected = language ?? LanguageSettings.selected.value;

    if (selected == AppLanguage.korean) {
      return korean;
    }

    final translations = _translations[korean];

    // 아직 등록하지 않은 문구는 한국어로 표시합니다.
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
