import 'package:flutter/material.dart';
import 'package:device_preview/device_preview.dart';
import 'package:device_preview/presets.dart';

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
    return MaterialApp(
      title: 'SubFit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6557CC)),
        scaffoldBackgroundColor: const Color(0xFFFCFCFF),
      ),
      home: const HomeScreen(),
    );
  }
}
