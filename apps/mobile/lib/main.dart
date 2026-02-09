import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  runApp(
    const ProviderScope(
      child: HavenKeepApp(),
    ),
  );
}

class HavenKeepApp extends StatelessWidget {
  const HavenKeepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HavenKeep',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(), // TODO: Replace with HavenKeep theme from shared_ui
      home: const Scaffold(
        body: Center(
          child: Text(
            'HavenKeep\nYour Warranties. Protected.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24),
          ),
        ),
      ),
    );
  }
}
