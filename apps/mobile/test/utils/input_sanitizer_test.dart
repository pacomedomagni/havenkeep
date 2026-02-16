import 'package:flutter_test/flutter_test.dart';
import 'package:havenkeep_mobile/core/utils/input_sanitizer.dart';

void main() {
  group('InputSanitizer', () {
    group('sanitizeText', () {
      test('trims leading and trailing whitespace', () {
        expect(InputSanitizer.sanitizeText('  hello  '), 'hello');
        expect(InputSanitizer.sanitizeText('\thello\n'), 'hello');
      });

      test('removes null bytes', () {
        expect(InputSanitizer.sanitizeText('hello\u0000world'), 'helloworld');
      });

      test('removes control characters except newline and tab', () {
        // \x00-\x08, \x0B-\x0C, \x0E-\x1F, \x7F should be removed
        expect(InputSanitizer.sanitizeText('hello\x01world'), 'helloworld');
        expect(InputSanitizer.sanitizeText('hello\x1Fworld'), 'helloworld');
        expect(InputSanitizer.sanitizeText('hello\x7Fworld'), 'helloworld');
      });

      test('preserves newlines and tabs', () {
        expect(InputSanitizer.sanitizeText('hello\nworld'), 'hello\nworld');
        expect(InputSanitizer.sanitizeText('hello\tworld'), 'hello\tworld');
      });

      test('truncates to maxLength if specified', () {
        expect(
          InputSanitizer.sanitizeText('hello world', maxLength: 5),
          'hello',
        );
        expect(
          InputSanitizer.sanitizeText('hello', maxLength: 10),
          'hello',
        );
      });

      test('handles empty string', () {
        expect(InputSanitizer.sanitizeText(''), '');
      });
    });

    group('sanitizePrice', () {
      test('extracts valid price from formatted string', () {
        expect(InputSanitizer.sanitizePrice('100.00'), 100.00);
        expect(InputSanitizer.sanitizePrice('\$100.00'), 100.00);
        expect(InputSanitizer.sanitizePrice('100.50'), 100.50);
      });

      test('removes non-numeric characters', () {
        expect(InputSanitizer.sanitizePrice('USD 100.00'), 100.00);
        expect(InputSanitizer.sanitizePrice('100 dollars'), 100.00);
      });

      test('returns null for empty string', () {
        expect(InputSanitizer.sanitizePrice(''), isNull);
      });

      test('returns null for invalid input', () {
        expect(InputSanitizer.sanitizePrice('abc'), isNull);
      });

      test('returns null for negative prices', () {
        expect(InputSanitizer.sanitizePrice('-100'), isNull);
      });

      test('returns null for unreasonably high prices', () {
        expect(InputSanitizer.sanitizePrice('99999999'), isNull);
      });
    });

    group('sanitizeInteger', () {
      test('extracts valid integer', () {
        expect(InputSanitizer.sanitizeInteger('123'), 123);
        expect(InputSanitizer.sanitizeInteger('0'), 0);
      });

      test('removes non-numeric characters', () {
        expect(InputSanitizer.sanitizeInteger('12 months'), 12);
        expect(InputSanitizer.sanitizeInteger('\$123'), 123);
      });

      test('returns null for empty string', () {
        expect(InputSanitizer.sanitizeInteger(''), isNull);
      });

      test('returns null for invalid input', () {
        expect(InputSanitizer.sanitizeInteger('abc'), isNull);
      });
    });

    group('sanitizeUrl', () {
      test('returns valid URL unchanged', () {
        expect(
          InputSanitizer.sanitizeUrl('https://example.com'),
          'https://example.com',
        );
        expect(
          InputSanitizer.sanitizeUrl('http://test.com/path'),
          'http://test.com/path',
        );
      });

      test('trims whitespace', () {
        expect(
          InputSanitizer.sanitizeUrl('  https://example.com  '),
          'https://example.com',
        );
      });

      test('returns null for URLs without scheme', () {
        expect(InputSanitizer.sanitizeUrl('example.com'), isNull);
      });

      test('returns null for non-http schemes', () {
        expect(InputSanitizer.sanitizeUrl('ftp://example.com'), isNull);
        expect(InputSanitizer.sanitizeUrl('file:///path'), isNull);
      });

      test('returns null for empty string', () {
        expect(InputSanitizer.sanitizeUrl(''), isNull);
      });
    });

    group('sanitizeEmail', () {
      test('trims whitespace and converts to lowercase', () {
        expect(
          InputSanitizer.sanitizeEmail('  Test@Example.COM  '),
          'test@example.com',
        );
      });

      test('handles already lowercase emails', () {
        expect(
          InputSanitizer.sanitizeEmail('user@example.com'),
          'user@example.com',
        );
      });
    });

    group('sanitizePhoneNumber', () {
      test('preserves digits and common phone formatting', () {
        expect(
          InputSanitizer.sanitizePhoneNumber('(555) 123-4567'),
          '(555) 123-4567',
        );
        expect(
          InputSanitizer.sanitizePhoneNumber('+1 555-123-4567'),
          '+1 555-123-4567',
        );
      });

      test('removes invalid characters', () {
        expect(
          InputSanitizer.sanitizePhoneNumber('555*123*4567'),
          '5551234567',
        );
        expect(
          InputSanitizer.sanitizePhoneNumber('Call 555-1234'),
          '555-1234',
        );
      });

      test('trims result', () {
        expect(
          InputSanitizer.sanitizePhoneNumber('  555-1234  '),
          '555-1234',
        );
      });
    });

    group('sanitizeSerialNumber', () {
      test('converts to uppercase and removes special characters', () {
        expect(
          InputSanitizer.sanitizeSerialNumber('abc-123-def'),
          'ABC-123-DEF',
        );
        expect(
          InputSanitizer.sanitizeSerialNumber('serial#123'),
          'SERIAL123',
        );
      });

      test('preserves hyphens', () {
        expect(
          InputSanitizer.sanitizeSerialNumber('ABC-123-DEF'),
          'ABC-123-DEF',
        );
      });

      test('trims result', () {
        expect(
          InputSanitizer.sanitizeSerialNumber('  abc123  '),
          'ABC123',
        );
      });
    });

    group('sanitizeModelNumber', () {
      test('removes special characters but preserves case', () {
        expect(
          InputSanitizer.sanitizeModelNumber('Model#ABC-123'),
          'ModelABC-123',
        );
      });

      test('preserves hyphens and original case', () {
        expect(
          InputSanitizer.sanitizeModelNumber('RF28R7351SR'),
          'RF28R7351SR',
        );
      });
    });

    group('sanitizeSingleLine', () {
      test('removes newlines and collapses whitespace', () {
        expect(
          InputSanitizer.sanitizeSingleLine('hello\nworld'),
          'hello world',
        );
        expect(
          InputSanitizer.sanitizeSingleLine('hello  \n  world'),
          'hello world',
        );
      });

      test('collapses multiple spaces', () {
        expect(
          InputSanitizer.sanitizeSingleLine('hello    world'),
          'hello world',
        );
      });

      test('trims result', () {
        expect(
          InputSanitizer.sanitizeSingleLine('  hello world  '),
          'hello world',
        );
      });

      test('respects maxLength', () {
        expect(
          InputSanitizer.sanitizeSingleLine('hello world', maxLength: 5),
          'hello',
        );
      });
    });

    group('sanitizeMultiLine', () {
      test('preserves newlines', () {
        expect(
          InputSanitizer.sanitizeMultiLine('hello\nworld'),
          'hello\nworld',
        );
      });

      test('respects maxLength', () {
        expect(
          InputSanitizer.sanitizeMultiLine('hello\nworld', maxLength: 7),
          'hello\nw',
        );
      });
    });

    group('escapeHtml', () {
      test('escapes HTML special characters', () {
        expect(InputSanitizer.escapeHtml('<script>'), '&lt;script&gt;');
        expect(InputSanitizer.escapeHtml('a & b'), 'a &amp; b');
        expect(InputSanitizer.escapeHtml('"quote"'), '&quot;quote&quot;');
        expect(InputSanitizer.escapeHtml("'quote'"), '&#x27;quote&#x27;');
      });

      test('escapes multiple characters', () {
        expect(
          InputSanitizer.escapeHtml('<div class="test">A & B</div>'),
          '&lt;div class=&quot;test&quot;&gt;A &amp; B&lt;/div&gt;',
        );
      });

      test('handles already safe text', () {
        expect(InputSanitizer.escapeHtml('hello world'), 'hello world');
      });
    });

    group('stripHtmlTags', () {
      test('removes HTML tags', () {
        expect(
          InputSanitizer.stripHtmlTags('<p>Hello</p>'),
          'Hello',
        );
        expect(
          InputSanitizer.stripHtmlTags('<div class="test">Content</div>'),
          'Content',
        );
      });

      test('removes multiple tags', () {
        expect(
          InputSanitizer.stripHtmlTags('<h1>Title</h1><p>Paragraph</p>'),
          'TitleParagraph',
        );
      });

      test('handles self-closing tags', () {
        expect(
          InputSanitizer.stripHtmlTags('Line 1<br/>Line 2'),
          'Line 1Line 2',
        );
      });

      test('handles text without tags', () {
        expect(
          InputSanitizer.stripHtmlTags('Plain text'),
          'Plain text',
        );
      });
    });
  });
}
