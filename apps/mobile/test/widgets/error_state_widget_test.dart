import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:havenkeep_mobile/core/widgets/error_state_widget.dart';

void main() {
  group('ErrorStateWidget', () {
    testWidgets('displays error message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              message: 'Something went wrong',
            ),
          ),
        ),
      );

      expect(find.text('Something went wrong'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('displays custom icon when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              message: 'Custom error',
              icon: Icons.warning,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.warning), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('displays details when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              message: 'Error occurred',
              details: 'Please check your connection',
            ),
          ),
        ),
      );

      expect(find.text('Error occurred'), findsOneWidget);
      expect(find.text('Please check your connection'), findsOneWidget);
    });

    testWidgets('shows retry button when onRetry provided', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              message: 'Error',
              onRetry: () => retryCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retryCalled, isTrue);
    });

    testWidgets('hides retry button when onRetry is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              message: 'Error',
            ),
          ),
        ),
      );

      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows custom action button when provided', (tester) async {
      var actionCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              message: 'Error',
              actionLabel: 'Go Back',
              onAction: () => actionCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Go Back'), findsOneWidget);

      await tester.tap(find.text('Go Back'));
      await tester.pump();

      expect(actionCalled, isTrue);
    });

    testWidgets('renders compact version when compact is true', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              message: 'Compact error',
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('Compact error'), findsOneWidget);
      // Compact version uses smaller icon
      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.size, 24);
    });

    testWidgets('compact version shows retry icon button', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorStateWidget(
              message: 'Compact error',
              compact: true,
              onRetry: () => retryCalled = true,
            ),
          ),
        ),
      );

      final retryButton = find.byType(IconButton);
      expect(retryButton, findsOneWidget);

      await tester.tap(retryButton);
      await tester.pump();

      expect(retryCalled, isTrue);
    });
  });

  group('NetworkErrorWidget', () {
    testWidgets('displays network error message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NetworkErrorWidget(),
          ),
        ),
      );

      expect(find.text('No internet connection'), findsOneWidget);
      expect(
        find.text('Please check your network settings and try again.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    });

    testWidgets('shows retry button when onRetry provided', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkErrorWidget(
              onRetry: () => retryCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retryCalled, isTrue);
    });

    testWidgets('supports compact mode', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NetworkErrorWidget(
              compact: true,
            ),
          ),
        ),
      );

      expect(find.text('No internet connection'), findsOneWidget);
      final icon = tester.widget<Icon>(find.byIcon(Icons.wifi_off));
      expect(icon.size, 24); // Compact size
    });
  });

  group('EmptyStateWidget', () {
    testWidgets('displays empty state message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              message: 'No items found',
            ),
          ),
        ),
      );

      expect(find.text('No items found'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
    });

    testWidgets('displays custom icon when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              message: 'No items',
              icon: Icons.inventory_2_outlined,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    });

    testWidgets('displays details when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              message: 'No items',
              details: 'Add your first item to get started',
            ),
          ),
        ),
      );

      expect(find.text('Add your first item to get started'), findsOneWidget);
    });

    testWidgets('shows action button when provided', (tester) async {
      var actionCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              message: 'No items',
              actionLabel: 'Add Item',
              onAction: () => actionCalled = true,
            ),
          ),
        ),
      );

      expect(find.text('Add Item'), findsOneWidget);

      await tester.tap(find.text('Add Item'));
      await tester.pump();

      expect(actionCalled, isTrue);
    });
  });

  group('AsyncStateBuilder', () {
    testWidgets('shows loading indicator while waiting', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncStateBuilder<String>(
              asyncValue: const AsyncSnapshot.waiting(),
              builder: (data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows custom loading widget when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncStateBuilder<String>(
              asyncValue: const AsyncSnapshot.waiting(),
              builder: (data) => Text(data),
              loadingWidget: const Text('Custom loading'),
            ),
          ),
        ),
      );

      expect(find.text('Custom loading'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows error state when has error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncStateBuilder<String>(
              asyncValue: AsyncSnapshot.withError(
                ConnectionState.done,
                Exception('Test error'),
              ),
              builder: (data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.byType(ErrorStateWidget), findsOneWidget);
    });

    testWidgets('shows custom error message when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncStateBuilder<String>(
              asyncValue: AsyncSnapshot.withError(
                ConnectionState.done,
                Exception('Test error'),
              ),
              builder: (data) => Text(data),
              errorMessage: 'Custom error message',
            ),
          ),
        ),
      );

      expect(find.text('Custom error message'), findsOneWidget);
    });

    testWidgets('shows error state when no data', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncStateBuilder<String>(
              asyncValue: const AsyncSnapshot.nothing(),
              builder: (data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.text('No data available'), findsOneWidget);
    });

    testWidgets('calls builder with data when has data', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncStateBuilder<String>(
              asyncValue: const AsyncSnapshot.withData(
                ConnectionState.done,
                'Test data',
              ),
              builder: (data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.text('Test data'), findsOneWidget);
    });

    testWidgets('retry button calls onRetry callback', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AsyncStateBuilder<String>(
              asyncValue: AsyncSnapshot.withError(
                ConnectionState.done,
                Exception('Test error'),
              ),
              builder: (data) => Text(data),
              onRetry: () => retryCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();

      expect(retryCalled, isTrue);
    });
  });
}
