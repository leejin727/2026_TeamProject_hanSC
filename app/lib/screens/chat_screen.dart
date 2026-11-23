// 챗봇 화면: 글로 묻고 답한다. 서버의 POST /chat을 부른다 (docs/api-spec.md 4-2장).
//
// 대화는 이 화면 안에만 있다. 화면을 닫거나 '새 대화'를 누르면 사라지고,
// 휴대폰에도 서버에도 저장하지 않는다 (data/extra/ASSUMPTIONS.md "챗봇").
import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../data/subway_map_data.dart';
import '../widgets/language_selector.dart';
import 'route_result_screen.dart';

const _navy = Color(0xFF152952);
const _textColor = Color(0xFF293F64);
const _muted = Color(0xFF8392AA);
const _lightBackground = Color(0xFFF0F5F8);
const _border = Color(0xFFD2DAE6);

/// 서버가 받는 가장 긴 메시지 (api-spec.md 4-2장)
const _maxMessageLength = 300;

/// 챗봇 답과 카드는 오른쪽을, 내가 쓴 말은 왼쪽을 이만큼 비워서 누가 한 말인지 구분한다.
const _botGap = EdgeInsets.only(right: 36);
const _userGap = EdgeInsets.only(left: 56);

/// 화면에 쓰는 글자. 챗봇이 한국어·영어로만 답해서 화면 글자도 두 언어만 둔다.
class _Labels {
  const _Labels({
    required this.title,
    required this.back,
    required this.newChat,
    required this.welcome,
    required this.examples,
    required this.hint,
    required this.send,
    required this.details,
    required this.retry,
    required this.waiting,
    required this.networkError,
    required this.unavailable,
    required this.unknownError,
  });

  /// 언어 코드가 'ko'면 한국어, 아니면 영어 (경로 결과 화면이 역 이름 언어를 고르는 규칙과 같다).
  static _Labels of(String lang) => lang == 'ko' ? _korean : _english;

  final String title;
  final String back;
  final String newChat;
  final String welcome;

  /// 처음에 보여 주는 예시 질문. 실제 서버가 알아듣는 것을 확인한 문장이다 (2026-11-23).
  final List<String> examples;
  final String hint;
  final String send;
  final String details;
  final String retry;
  final String waiting;
  final String networkError;
  final String unavailable;
  final String unknownError;

  static const _korean = _Labels(
    title: '챗봇',
    back: '뒤로가기',
    newChat: '새 대화',
    // 좁은 화면에서도 낱말 중간에서 줄이 바뀌지 않게 줄을 짧게 나눴다
    welcome: '안녕하세요!\n길찾기와 지하철 이용을 도와드려요.\n한국어나 영어로 물어보세요.',
    examples: ['신도림에서 강남까지 어떻게 가?', '교통카드는 어디서 사요?', '역무원에게 보여 줄 문장 알려줘'],
    hint: '메시지를 입력하세요',
    send: '보내기',
    details: '자세히 보기',
    retry: '다시 시도',
    waiting: '답을 기다리는 중',
    networkError: '서버에 연결할 수 없습니다.\n서버가 켜져 있는지 확인해 주세요.',
    unavailable: '지금은 챗봇을 쓸 수 없습니다.\n잠시 후 다시 시도해 주세요.',
    unknownError: '답을 받지 못했습니다.\n잠시 후 다시 시도해 주세요.',
  );

  static const _english = _Labels(
    title: 'Chatbot',
    back: 'Back',
    newChat: 'New chat',
    welcome:
        'Hi! I can help you find a route and use the subway.\n'
        'Ask me in Korean or English.',
    examples: [
      'How do I get from Sindorim to Gangnam?',
      'Where can I buy a ticket?',
      'Show me useful Korean phrases',
    ],
    hint: 'Type a message',
    send: 'Send',
    details: 'View details',
    retry: 'Try again',
    waiting: 'Waiting for a reply',
    networkError:
        "Can't connect to the server.\n"
        'Please check that the server is running.',
    unavailable:
        'The chatbot is not available right now.\nPlease try again later.',
    unknownError: "Couldn't get an answer.\nPlease try again later.",
  );
}

/// 대화의 한 줄: 내가 쓴 말, 챗봇의 답, 또는 답을 받지 못했다는 오류.
class _Message {
  _Message.user(this.text) : reply = null, error = null;
  _Message.reply(ChatReply this.reply) : text = reply.text, error = null;
  _Message.error(Object this.error) : text = '', reply = null;

  final String text;
  final ChatReply? reply;
  final Object? error;

  bool get fromUser => reply == null && error == null;
}

/// 노선 색. 노선도 화면과 같은 색을 쓴다.
Color _lineColor(int line) {
  try {
    return SubwayMapData.colorForLine(line);
  } on ArgumentError {
    return _muted;
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, this.client});

  /// 테스트에서 가짜 서버를 넣을 때만 쓴다. 비우면 앱 전체가 함께 쓰는 [apiClient].
  final ApiClient? client;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <_Message>[];

  /// 직전 답의 context. 이어 묻기("그럼 반대로는?")를 위해 다음 요청에 그대로 넣는다.
  Map<String, dynamic>? _context;

  /// 직전 답의 언어. 역 이름만 보낼 때(역 선택 버튼 등) 답하는 언어가 바뀌지 않게 다음 요청의 lang으로 쓴다.
  String? _replyLang;

  bool _waiting = false;

  /// 답을 받지 못한 말. '다시 시도'를 누르면 이 말을 다시 보낸다.
  String? _failedMessage;

  /// '새 대화'를 누를 때마다 1씩 는다. 그 전에 보낸 말의 답이 뒤늦게 오면 버리려고 쓴다.
  int _session = 0;

  ApiClient get _client => widget.client ?? apiClient;

  String get _appLang => LanguageSettings.selected.value.code;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    var message = raw.trim();
    if (message.isEmpty || _waiting) return;

    // 서버는 글자(코드 포인트) 300개까지 받는다. 입력창의 글자 수 제한은 이모지 같은 글자를
    // 1개로 세어서 더 길어질 수 있으므로, 서버와 같은 방법으로 한 번 더 자른다.
    if (message.runes.length > _maxMessageLength) {
      message = String.fromCharCodes(message.runes.take(_maxMessageLength));
    }

    _input.clear();
    setState(() => _messages.add(_Message.user(message)));
    _request(message);
  }

  void _retry() {
    final message = _failedMessage;
    if (message == null || _waiting) return;

    setState(_messages.removeLast); // 오류 말풍선을 지우고 같은 말을 다시 보낸다
    _request(message);
  }

  Future<void> _request(String message) async {
    final session = _session;
    setState(() {
      _waiting = true;
      _failedMessage = null;
    });
    _showLatest();

    try {
      final reply = await _client.chat(
        message: message,
        lang: _replyLang ?? _appLang,
        context: _context,
      );
      if (!mounted || session != _session) return;
      setState(() {
        _context = reply.context;
        _replyLang = reply.lang;
        _messages.add(_Message.reply(reply));
        _waiting = false;
      });
    } catch (error) {
      // 서버 오류·연결 실패(ApiException)뿐 아니라 응답을 읽다가 난 오류도 여기서 받는다.
      // 그래야 화면이 '기다리는 중'에서 멈추지 않는다. context는 바꾸지 않는다.
      if (!mounted || session != _session) return;
      setState(() {
        _failedMessage = message;
        _messages.add(_Message.error(error));
        _waiting = false;
      });
    }
    _showLatest();
  }

  void _startOver() {
    setState(() {
      _session++;
      _messages.clear();
      _context = null;
      _replyLang = null;
      _failedMessage = null;
      _waiting = false;
    });
  }

  /// 가장 최근 말이 보이게 맨 아래로 내린다. 대화 목록이 거꾸로(reverse)라서 0이 맨 아래다.
  void _showLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  void _openRoute(RouteResult route) {
    FocusScope.of(context).unfocus();

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => RouteResultScreen(
          departure: route.start.name,
          arrival: route.end.name,
          criteria: route.criteria,
        ),
      ),
    );
  }

  String _errorText(Object? error, _Labels labels) {
    if (error is ApiException) {
      switch (error.code) {
        case 'NETWORK':
          return labels.networkError;
        case 'CHAT_UNAVAILABLE':
          return labels.unavailable;
      }
    }
    return labels.unknownError;
  }

  @override
  Widget build(BuildContext context) {
    final labels = _Labels.of(_appLang);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              children: [
                _buildHeader(labels),
                Expanded(child: _buildConversation(labels)),
                _buildInput(labels),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(_Labels labels) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            tooltip: labels.back,
            icon: const Icon(Icons.chevron_left, color: _navy),
          ),
          Expanded(
            child: Text(
              labels.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _textColor,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            onPressed: _messages.isEmpty ? null : _startOver,
            tooltip: labels.newChat,
            color: _navy,
            icon: const Icon(Icons.add_comment_outlined, size: 22),
          ),
        ],
      ),
    );
  }

  Widget _buildConversation(_Labels labels) {
    // 대화가 짧을 때는 위에서부터 보이고, 길어지면 맨 아래(가장 최근 말)에 붙어 있게 한다.
    // reverse라서 새 말이 붙거나 키보드가 올라와도 맨 아래가 가려지지 않는다.
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        controller: _scroll,
        reverse: true,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBubble(text: labels.welcome),
            const SizedBox(height: 10),
            _buildChoices(labels.examples, enabled: !_waiting),
            for (final message in _messages) ...[
              const SizedBox(height: 14),
              _buildMessage(message, labels),
            ],
            if (_waiting) ...[
              const SizedBox(height: 14),
              _buildWaiting(labels),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(_Message message, _Labels labels) {
    if (message.fromUser) {
      return _buildBubble(text: message.text, mine: true);
    }

    final isLast = identical(message, _messages.last);
    final reply = message.reply;

    if (reply == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildBubble(
            text: _errorText(message.error, labels),
            icon: Icons.error_outline,
          ),
          if (isLast && _failedMessage != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _retry,
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: const BorderSide(color: _border),
              ),
              child: Text(labels.retry),
            ),
          ],
        ],
      );
    }

    // 답에 딸린 버튼 글자는 답과 같은 언어로 보여 준다
    final replyLabels = _Labels.of(reply.lang);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBubble(text: reply.text),
        if (reply.route case final route?) ...[
          const SizedBox(height: 8),
          _buildRouteCard(route, replyLabels),
        ],
        for (final phrase in reply.phrases) ...[
          const SizedBox(height: 8),
          _buildPhraseCard(phrase),
        ],
        if (reply.options.isNotEmpty) ...[
          const SizedBox(height: 8),
          // 지나간 질문의 버튼은 누를 수 없게 한다 (지금 묻는 것과 섞이지 않게)
          _buildChoices([
            for (final station in reply.options) station.name,
          ], enabled: isLast && !_waiting),
        ],
      ],
    );
  }

  /// 말풍선. [mine]이면 내가 쓴 말(오른쪽, 남색), 아니면 챗봇의 말(왼쪽, 옅은 색).
  Widget _buildBubble({
    required String text,
    bool mine = false,
    IconData? icon,
  }) {
    final label = Text(
      text,
      style: TextStyle(
        color: mine ? Colors.white : _textColor,
        fontSize: 14,
        height: 1.5,
      ),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: mine ? _userGap : _botGap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? _navy : _lightBackground,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: icon == null
            ? label
            : Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Icon(icon, color: _muted, size: 18),
                  ),
                  Flexible(child: label),
                ],
              ),
      ),
    );
  }

  Widget _buildWaiting(_Labels labels) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        label: labels.waiting,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: _lightBackground,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(4),
              bottomRight: Radius.circular(16),
            ),
          ),
          child: const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _muted),
          ),
        ),
      ),
    );
  }

  /// 누르면 그 글자를 그대로 보내는 버튼들: 예시 질문, 역 선택.
  Widget _buildChoices(List<String> choices, {required bool enabled}) {
    return Padding(
      padding: _botGap,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final choice in choices)
            OutlinedButton(
              onPressed: enabled ? () => _submit(choice) : null,
              style: OutlinedButton.styleFrom(
                foregroundColor: _navy,
                side: const BorderSide(color: _border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Text(
                choice,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 경로 카드: 타는 노선 순서대로 (노선 번호, 타는 역 → 내리는 역).
  /// 걸리는 시간과 환승 횟수는 위 말풍선(서버가 보낸 글)에 있다.
  Widget _buildRouteCard(RouteResult route, _Labels labels) {
    return _buildCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final segment in route.segments)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  _LineBadge(line: segment.line),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${segment.board.name} → ${segment.alight.name}',
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          OutlinedButton(
            onPressed: () => _openRoute(route),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: const BorderSide(color: _border),
              minimumSize: const Size(double.infinity, 42),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              labels.details,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// 문장 카드: 역무원에게 보여 줄 한국어 문장을 크게, 뜻(영어로 답할 때만)을 작게.
  Widget _buildPhraseCard(ChatPhrase phrase) {
    return _buildCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phrase.korean,
            style: const TextStyle(
              color: _textColor,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.4,
            ),
          ),
          if (phrase.meaning case final meaning?) ...[
            const SizedBox(height: 4),
            Text(
              meaning,
              style: const TextStyle(color: _muted, fontSize: 12, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard({required EdgeInsets padding, required Widget child}) {
    return Container(
      margin: _botGap,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }

  Widget _buildInput(_Labels labels) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF2F4F7))),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller: _input,
                // 글이 길면 세 줄까지 늘어나지만, 줄바꿈 대신 '보내기'가 되게 한다
                keyboardType: TextInputType.text,
                textInputAction: TextInputAction.send,
                minLines: 1,
                maxLines: 3,
                maxLength: _maxMessageLength,
                onSubmitted: _submit,
                // 보낸 뒤에도 키보드를 내리지 않는다 (이어서 쓸 수 있게)
                onEditingComplete: () {},
                cursorColor: _navy,
                style: const TextStyle(color: _textColor, fontSize: 15),
                decoration: InputDecoration(
                  hintText: labels.hint,
                  hintStyle: const TextStyle(
                    color: _muted,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                  counterText: '', // 글자 수(0/300)는 보여 주지 않는다
                  isDense: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 입력창이 비어 있거나 답을 기다리는 동안에는 보낼 수 없다
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _input,
            builder: (context, value, child) {
              final canSend = !_waiting && value.text.trim().isNotEmpty;

              return IconButton(
                onPressed: canSend ? () => _submit(_input.text) : null,
                tooltip: labels.send,
                style: IconButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _lightBackground,
                  disabledForegroundColor: _muted,
                  minimumSize: const Size(46, 46),
                  shape: const CircleBorder(),
                ),
                icon: const Icon(Icons.arrow_upward_rounded, size: 22),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 노선 번호를 노선 색 동그라미 안에 보여 준다.
class _LineBadge extends StatelessWidget {
  const _LineBadge({required this.line});

  final int line;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _lineColor(line),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$line',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );
  }
}
