import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/providers/demo_mode_provider.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer();
  });

  tearDown(() {
    container.dispose();
  });

  group('demoModeProvider', () {
    test('is initially disabled with empty items and no home', () {
      final state = container.read(demoModeProvider);

      expect(state.isEnabled, isFalse);
      expect(state.demoItems, isEmpty);
      expect(state.demoHome, isNull);
    });

    test('enterDemoMode sets isEnabled to true with 6 demo items', () {
      container.read(demoModeProvider.notifier).enterDemoMode();

      final state = container.read(demoModeProvider);

      expect(state.isEnabled, isTrue);
      expect(state.demoItems, hasLength(6));
      expect(state.demoHome, isNotNull);
    });

    test('enterDemoMode populates a demo home with correct id', () {
      container.read(demoModeProvider.notifier).enterDemoMode();

      final state = container.read(demoModeProvider);

      expect(state.demoHome!.id, 'demo-home');
      expect(state.demoHome!.name, 'My Home');
      expect(state.demoHome!.userId, 'demo-user');
    });

    test('exitDemoMode resets to initial state', () {
      container.read(demoModeProvider.notifier).enterDemoMode();
      expect(container.read(demoModeProvider).isEnabled, isTrue);

      container.read(demoModeProvider.notifier).exitDemoMode();

      final state = container.read(demoModeProvider);
      expect(state.isEnabled, isFalse);
      expect(state.demoItems, isEmpty);
      expect(state.demoHome, isNull);
    });

    test('can enter and exit demo mode multiple times', () {
      // First cycle
      container.read(demoModeProvider.notifier).enterDemoMode();
      expect(container.read(demoModeProvider).isEnabled, isTrue);

      container.read(demoModeProvider.notifier).exitDemoMode();
      expect(container.read(demoModeProvider).isEnabled, isFalse);

      // Second cycle
      container.read(demoModeProvider.notifier).enterDemoMode();
      expect(container.read(demoModeProvider).isEnabled, isTrue);
      expect(container.read(demoModeProvider).demoItems, hasLength(6));

      container.read(demoModeProvider.notifier).exitDemoMode();
      expect(container.read(demoModeProvider).isEnabled, isFalse);
      expect(container.read(demoModeProvider).demoItems, isEmpty);
    });
  });

  group('DemoModeNotifier.getStats', () {
    test('returns zero stats when demo mode is disabled', () {
      final stats = container.read(demoModeProvider.notifier).getStats();

      expect(stats.totalItems, 0);
      expect(stats.totalValue, 0);
      expect(stats.activeWarranties, 0);
      expect(stats.expiringWarranties, 0);
      expect(stats.warrantyHealth, 0);
    });

    test('returns correct item count when demo mode is active', () {
      container.read(demoModeProvider.notifier).enterDemoMode();

      final stats = container.read(demoModeProvider.notifier).getStats();

      expect(stats.totalItems, 6);
    });

    test('returns non-zero total value from demo items', () {
      container.read(demoModeProvider.notifier).enterDemoMode();

      final stats = container.read(demoModeProvider.notifier).getStats();

      // Demo items have known prices: 2899.99 + 2499.00 + 1899.99 + 379.99 + 599.99 + 1799.00
      expect(stats.totalValue, greaterThan(0));
    });

    test('warrantyHealth is between 0 and 100 when items exist', () {
      container.read(demoModeProvider.notifier).enterDemoMode();

      final stats = container.read(demoModeProvider.notifier).getStats();

      expect(stats.warrantyHealth, greaterThanOrEqualTo(0));
      expect(stats.warrantyHealth, lessThanOrEqualTo(100));
    });
  });
}
