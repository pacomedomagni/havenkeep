import 'package:flutter_test/flutter_test.dart';
import 'package:havenkeep_mobile/core/services/deep_link_service.dart';

void main() {
  group('DeepLinkService.routeFor', () {
    test('maps havenkeep://gift/<code> to /referral/<code>', () {
      final route = DeepLinkService.routeFor(
        Uri.parse('havenkeep://gift/ABC123'),
      );
      expect(route, '/referral/ABC123');
    });

    test('maps havenkeep://referral/<code> to /referral/<code>', () {
      final route = DeepLinkService.routeFor(
        Uri.parse('havenkeep://referral/XYZ789'),
      );
      expect(route, '/referral/XYZ789');
    });

    test('maps Universal Link gift URL to /referral/<code>', () {
      final route = DeepLinkService.routeFor(
        Uri.parse('https://havenkeep.com/gift/PROMO2026'),
      );
      expect(route, '/referral/PROMO2026');
    });

    test('maps Universal Link referral URL to /referral/<code>', () {
      final route = DeepLinkService.routeFor(
        Uri.parse('https://havenkeep.com/referral/FRIEND-50'),
      );
      expect(route, '/referral/FRIEND-50');
    });

    test('returns null for an empty gift code', () {
      final route = DeepLinkService.routeFor(
        Uri.parse('havenkeep://gift/'),
      );
      expect(route, isNull);
    });

    test('returns null for unknown hosts', () {
      final route = DeepLinkService.routeFor(
        Uri.parse('https://example.com/gift/ABC123'),
      );
      expect(route, isNull);
    });

    test('returns null for unknown schemes', () {
      final route = DeepLinkService.routeFor(
        Uri.parse('foo://gift/ABC123'),
      );
      expect(route, isNull);
    });

    test('returns null for unrelated paths on havenkeep.com', () {
      final route = DeepLinkService.routeFor(
        Uri.parse('https://havenkeep.com/about/team'),
      );
      expect(route, isNull);
    });

    test('shareUrlForGift produces the canonical Universal Link', () {
      final url = DeepLinkService.shareUrlForGift('ABC123');
      expect(url.toString(), 'https://havenkeep.com/gift/ABC123');
    });
  });
}
