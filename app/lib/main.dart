import 'package:flutter/material.dart';
import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';

import 'l10n/strings.dart';
import 'screens/home_screen.dart';

void main() async {
  DevicePreview.enable();

  await DevicePreview.maybeController?.applyPreset(DevicePresets.pixel9);

  runApp(const SubFitApp());
}

class SubFitApp extends StatelessWidget {
  const SubFitApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 앱 언어가 바뀌면 화면 글자(한국어·영어)가 바로 바뀌게 감싼다 (l10n/strings.dart)
    return LanguageScope(
      child: MaterialApp(
        title: 'SubFit',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6557CC)),
          scaffoldBackgroundColor: const Color(0xFFFCFCFF),
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
