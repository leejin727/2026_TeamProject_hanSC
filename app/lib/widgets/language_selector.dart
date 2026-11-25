import 'package:flutter/material.dart';

import '../localization/app_strings.dart';

enum AppLanguage {
  korean('ko', '한국어'),
  english('en', 'English'),
  japanese('ja', '日本語'),
  chineseSimplified('zh-Hans', '中文(简体)'),
  chineseTraditional('zh-Hant', '中文(繁體)'),
  vietnamese('vi', 'Tiếng Việt');

  const AppLanguage(this.code, this.label);

  final String code;
  final String label;
}

// 앱 실행 중 홈과 모임 입력 화면이 같은 선택값을 사용합니다.
// 번역 기능과 영구 저장은 아직 연결하지 않습니다.
class LanguageSettings {
  LanguageSettings._();

  static final ValueNotifier<AppLanguage> selected = ValueNotifier<AppLanguage>(
    AppLanguage.korean,
  );
}

class LanguageSelector extends StatelessWidget {
  const LanguageSelector({super.key});

  static const _navy = Color(0xFF152952);
  static const _border = Color(0xFFD2DAE6);
  static const _lightBackground = Color(0xFFF0F5F8);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppLanguage>(
      valueListenable: LanguageSettings.selected,
      builder: (context, selectedLanguage, child) {
        return PopupMenuButton<AppLanguage>(
          tooltip: AppStrings.text('언어 선택', language: selectedLanguage),
          position: PopupMenuPosition.under,
          offset: const Offset(0, 4),
          color: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 2,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 132, maxWidth: 160),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: _border),
          ),
          onSelected: (language) {
            LanguageSettings.selected.value = language;
          },
          itemBuilder: (context) {
            // 선택한 언어는 상단 버튼에 표시하고,
            // 메뉴에는 나머지 언어를 표시합니다.
            return AppLanguage.values
                .where((language) => language != selectedLanguage)
                .map(
                  (language) => PopupMenuItem<AppLanguage>(
                    value: language,
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: _LanguageMenuLabel(label: language.label),
                  ),
                )
                .toList();
          },
          child: Container(
            constraints: const BoxConstraints(minHeight: 40),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: _border),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.language, color: _navy, size: 16),
                const SizedBox(width: 6),
                Text(
                  selectedLanguage.label,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, color: _navy, size: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LanguageMenuLabel extends StatefulWidget {
  const _LanguageMenuLabel({required this.label});

  final String label;

  @override
  State<_LanguageMenuLabel> createState() => _LanguageMenuLabelState();
}

class _LanguageMenuLabelState extends State<_LanguageMenuLabel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        setState(() {
          _hovered = true;
        });
      },
      onExit: (_) {
        setState(() {
          _hovered = false;
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: _hovered
              ? LanguageSelector._lightBackground
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          widget.label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: LanguageSelector._navy,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
