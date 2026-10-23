import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'assistant_screen.dart';
//import 'vision/yolo_test_screen.dart';
//import 'vision/yolo_live_test_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const AssistantApp());
}

class AssistantApp extends StatelessWidget {
  const AssistantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Assistant Vision',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1A237E),
        scaffoldBackgroundColor: const Color(0xFFFFFBEA),
      ),
      home: const AssistantScreen(),
      //home: const YoloTestScreen(),
      //home: const YoloLiveTestScreen(),
    );
  }
}