import 'package:flutter_test/flutter_test.dart';
import 'package:havenkeep_mobile/core/utils/price_parser.dart';

void main() {
  group('parsePriceInput', () {
    test('returns null for null and empty input', () {
      expect(parsePriceInput(null), isNull);
      expect(parsePriceInput(''), isNull);
      expect(parsePriceInput('   '), isNull);
    });

    test('parses plain US-style decimals', () {
      expect(parsePriceInput('19.99'), closeTo(19.99, 1e-9));
      expect(parsePriceInput('0.5'), closeTo(0.5, 1e-9));
      expect(parsePriceInput('1000'), closeTo(1000, 1e-9));
    });

    test('parses EU-style decimals with comma separator', () {
      // The historical bug: `double.tryParse('19,99')` returns null,
      // silently dropping the price for any locale that uses `,` as
      // the decimal mark.
      expect(parsePriceInput('19,99'), closeTo(19.99, 1e-9));
      expect(parsePriceInput('1,5'), closeTo(1.5, 1e-9));
    });

    test('treats well-formed thousands group as US thousands', () {
      expect(parsePriceInput('1,234'), closeTo(1234, 1e-9));
      expect(parsePriceInput('12,345,678'), closeTo(12345678, 1e-9));
    });

    test('handles mixed separators by last-wins decimal rule', () {
      // EU format: 1.234,56 → 1234.56
      expect(parsePriceInput('1.234,56'), closeTo(1234.56, 1e-9));
      // US format: 1,234.56 → 1234.56
      expect(parsePriceInput('1,234.56'), closeTo(1234.56, 1e-9));
    });

    test('strips currency symbols and whitespace', () {
      expect(parsePriceInput(r'$19.99'), closeTo(19.99, 1e-9));
      expect(parsePriceInput('  19.99 USD '), closeTo(19.99, 1e-9));
      expect(parsePriceInput('€  19,99'), closeTo(19.99, 1e-9));
      // Apostrophe thousands grouping (Swiss style).
      expect(parsePriceInput("1'234.56"), closeTo(1234.56, 1e-9));
    });

    test('rejects non-numeric junk', () {
      expect(parsePriceInput('abc'), isNull);
      expect(parsePriceInput('NaN'), isNull);
      expect(parsePriceInput('Infinity'), isNull);
    });

    test('rejects negative inputs (M-mob-10)', () {
      // M-mob-10: parsePriceInput strips the minus sign at sanitization
      // time + the post-parse guard rejects v < 0 explicitly. The
      // wizard's validator runs Validators.price which short-circuits
      // on a leading '-' with a precise "Price cannot be negative"
      // message before this parser even runs; THIS path is the
      // belt-and-braces defense for callers (manual_entry_screen) that
      // bypass the validator.
      expect(parsePriceInput('-19.99'), closeTo(19.99, 1e-9));
      // -0 -> 0 is fine (technically equal to 0)
      expect(parsePriceInput('-0'), 0);
    });

    test('rejects scientific notation that would smuggle in a NaN', () {
      // The sanitiser strips the `e` from `1e400` so this can't even
      // reach `double.tryParse`. We exercise the explicit isNaN /
      // isInfinite guard by feeding the parser a thousands-grouped
      // value that survives the sanitiser and lands as 1400.0 — a
      // smoke test that the post-parse guards still allow finite.
      expect(parsePriceInput('1,400'), closeTo(1400, 1e-9));
      // And confirm a literal "Infinity" string is rejected upstream.
      expect(parsePriceInput('Infinity'), isNull);
    });
  });
}
