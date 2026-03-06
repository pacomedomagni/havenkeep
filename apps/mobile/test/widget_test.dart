// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:havenkeep_mobile/main.dart';

void main() {
  testWidgets('App smoke test - widget builds without error',
      (WidgetTester tester) async {
    // Build the app inside a ProviderScope and trigger a frame.
    await tester.pumpWidget(
      const ProviderScope(child: HavenKeepApp()),
    );

    // Verify the app renders (MaterialApp.router shows a title).
    expect(find.byType(HavenKeepApp), findsOneWidget);
  });
}
