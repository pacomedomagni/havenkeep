import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:havenkeep_mobile/core/widgets/retry_button.dart';

void main() {
  group('RetryButton', () {
    testWidgets('displays default label "Retry"', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryButton(
              onRetry: () async {},
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('displays custom label when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryButton(
              onRetry: () async {},
              label: 'Try Again',
            ),
          ),
        ),
      );

      expect(find.text('Try Again'), findsOneWidget);
    });

    testWidgets('displays custom icon when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryButton(
              onRetry: () async {},
              icon: Icons.replay,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.replay), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('hides icon when showIcon is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryButton(
              onRetry: () async {},
              showIcon: false,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('calls onRetry when tapped', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryButton(
              onRetry: () async {
                retryCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retryCalled, isTrue);
    });

    testWidgets('shows loading indicator while retrying', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryButton(
              onRetry: () async {
                await Future.delayed(const Duration(milliseconds: 100));
              },
            ),
          ),
        ),
      );

      // Initial state - shows icon
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Tap the button
      await tester.tap(find.text('Retry'));
      await tester.pump();

      // Loading state - shows progress indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);

      // Wait for retry to complete
      await tester.pumpAndSettle();

      // Back to initial state
      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('disabled when disabled is true', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryButton(
              onRetry: () async {
                retryCalled = true;
              },
              disabled: true,
            ),
          ),
        ),
      );

      final button = tester.widget<ElevatedButton>(
        find.byType(ElevatedButton),
      );
      expect(button.onPressed, isNull);

      // Tapping should not call onRetry
      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retryCalled, isFalse);
    });

    testWidgets('disabled while retrying', (tester) async {
      var retryCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryButton(
              onRetry: () async {
                retryCount++;
                await Future.delayed(const Duration(milliseconds: 100));
              },
            ),
          ),
        ),
      );

      // First tap
      await tester.tap(find.text('Retry'));
      await tester.pump();

      // Try to tap again while still retrying
      await tester.tap(find.text('Retry'));
      await tester.pump();

      await tester.pumpAndSettle();

      // Should only have been called once
      expect(retryCount, 1);
    });

    group('RetryButtonStyle', () {
      testWidgets('elevated style renders ElevatedButton', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RetryButton(
                onRetry: () async {},
                style: RetryButtonStyle.elevated,
              ),
            ),
          ),
        );

        expect(find.byType(ElevatedButton), findsOneWidget);
      });

      testWidgets('outlined style renders OutlinedButton', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RetryButton(
                onRetry: () async {},
                style: RetryButtonStyle.outlined,
              ),
            ),
          ),
        );

        expect(find.byType(OutlinedButton), findsOneWidget);
      });

      testWidgets('text style renders TextButton', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RetryButton(
                onRetry: () async {},
                style: RetryButtonStyle.text,
              ),
            ),
          ),
        );

        expect(find.byType(TextButton), findsOneWidget);
      });

      testWidgets('iconOnly style renders IconButton', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RetryButton(
                onRetry: () async {},
                style: RetryButtonStyle.iconOnly,
              ),
            ),
          ),
        );

        expect(find.byType(IconButton), findsOneWidget);
        // Label should not be visible in iconOnly mode
        expect(find.text('Retry'), findsNothing);
      });
    });
  });

  group('RetryBanner', () {
    testWidgets('displays message and retry button when show is true',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryBanner(
              message: 'Failed to load data',
              onRetry: () async {},
              show: true,
            ),
          ),
        ),
      );

      expect(find.text('Failed to load data'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('hides when show is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryBanner(
              message: 'Failed to load data',
              onRetry: () async {},
              show: false,
            ),
          ),
        ),
      );

      expect(find.text('Failed to load data'), findsNothing);
      expect(find.byType(RetryButton), findsNothing);
    });

    testWidgets('calls onRetry when retry button is tapped', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryBanner(
              message: 'Error occurred',
              onRetry: () async {
                retryCalled = true;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retryCalled, isTrue);
    });

    testWidgets('uses custom background color when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryBanner(
              message: 'Error',
              onRetry: () async {},
              backgroundColor: Colors.red[50],
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.byType(Container).first,
      );
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, Colors.red[50]);
    });
  });

  group('RetryRefreshWrapper', () {
    testWidgets('wraps child with RefreshIndicator', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryRefreshWrapper(
              onRefresh: () async {},
              child: const Text('Content'),
            ),
          ),
        ),
      );

      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.text('Content'), findsOneWidget);
    });

    testWidgets('calls onRefresh when pulled down', (tester) async {
      var refreshCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RetryRefreshWrapper(
              onRefresh: () async {
                refreshCalled = true;
              },
              child: ListView(
                children: const [
                  SizedBox(height: 1000, child: Text('Content')),
                ],
              ),
            ),
          ),
        ),
      );

      // Simulate pull-to-refresh gesture
      await tester.fling(
        find.text('Content'),
        const Offset(0, 300),
        1000,
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(refreshCalled, isTrue);
    });
  });
}
