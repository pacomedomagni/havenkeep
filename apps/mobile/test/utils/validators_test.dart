import 'package:flutter_test/flutter_test.dart';
import 'package:havenkeep_mobile/core/utils/validators.dart';

void main() {
  group('Validators', () {
    group('required', () {
      test('returns error for null value', () {
        final error = Validators.required(null);
        expect(error, isNotNull);
        expect(error, contains('required'));
      });

      test('returns error for empty string', () {
        final error = Validators.required('');
        expect(error, isNotNull);
      });

      test('returns error for whitespace-only string', () {
        final error = Validators.required('   ');
        expect(error, isNotNull);
      });

      test('returns null for valid value', () {
        final error = Validators.required('Valid');
        expect(error, isNull);
      });

      test('includes custom field name in error', () {
        final error = Validators.required(null, fieldName: 'Item name');
        expect(error, contains('Item name'));
      });
    });

    group('minLength', () {
      test('returns error when length is too short', () {
        final error = Validators.minLength('ab', 3);
        expect(error, isNotNull);
        expect(error, contains('3 characters'));
      });

      test('returns null when length equals minimum', () {
        final error = Validators.minLength('abc', 3);
        expect(error, isNull);
      });

      test('returns null when length exceeds minimum', () {
        final error = Validators.minLength('abcdef', 3);
        expect(error, isNull);
      });

      test('returns null for null value (not required)', () {
        final error = Validators.minLength(null, 3);
        expect(error, isNull);
      });
    });

    group('maxLength', () {
      test('returns error when length exceeds maximum', () {
        final error = Validators.maxLength('abcdef', 5);
        expect(error, isNotNull);
        expect(error, contains('5 characters'));
      });

      test('returns null when length equals maximum', () {
        final error = Validators.maxLength('abcde', 5);
        expect(error, isNull);
      });

      test('returns null when length is less than maximum', () {
        final error = Validators.maxLength('abc', 5);
        expect(error, isNull);
      });
    });

    group('price', () {
      test('returns null for valid price', () {
        expect(Validators.price('100.00'), isNull);
        expect(Validators.price('0.99'), isNull);
        expect(Validators.price('1000'), isNull);
      });

      test('returns null for empty string (not required)', () {
        expect(Validators.price(''), isNull);
        expect(Validators.price(null), isNull);
      });

      test('returns error for negative price', () {
        final error = Validators.price('-10');
        expect(error, isNotNull);
        expect(error, contains('negative'));
      });

      test('returns error for unreasonably high price', () {
        final error = Validators.price('99999999');
        expect(error, isNotNull);
        expect(error, contains('unreasonably high'));
      });

      test('returns error for non-numeric value', () {
        final error = Validators.price('abc');
        expect(error, isNotNull);
        expect(error, contains('valid price'));
      });

      test('handles currency symbols gracefully', () {
        expect(Validators.price('\$100.00'), isNull);
        expect(Validators.price('100.00 USD'), isNull);
      });
    });

    group('warrantyMonths', () {
      test('returns null for valid months', () {
        expect(Validators.warrantyMonths(12), isNull);
        expect(Validators.warrantyMonths(1), isNull);
        expect(Validators.warrantyMonths(60), isNull);
      });

      test('returns error for null', () {
        final error = Validators.warrantyMonths(null);
        expect(error, isNotNull);
        expect(error, contains('required'));
      });

      test('returns error for negative months', () {
        final error = Validators.warrantyMonths(-5);
        expect(error, isNotNull);
        expect(error, contains('negative'));
      });

      test('returns error for zero months', () {
        final error = Validators.warrantyMonths(0);
        expect(error, isNotNull);
        expect(error, contains('at least 1'));
      });

      test('returns error for unreasonably long warranty (>25 years)', () {
        final error = Validators.warrantyMonths(301);
        expect(error, isNotNull);
        expect(error, contains('too long'));
      });
    });

    group('serialNumber', () {
      test('returns null for valid serial numbers', () {
        expect(Validators.serialNumber('ABC123'), isNull);
        expect(Validators.serialNumber('12345'), isNull);
        expect(Validators.serialNumber('ABC-123-DEF'), isNull);
      });

      test('returns null for empty string (not required)', () {
        expect(Validators.serialNumber(''), isNull);
        expect(Validators.serialNumber(null), isNull);
      });

      test('returns error for too short serial number', () {
        final error = Validators.serialNumber('AB');
        expect(error, isNotNull);
        expect(error, contains('too short'));
      });

      test('returns error for invalid characters', () {
        final error = Validators.serialNumber('ABC@123');
        expect(error, isNotNull);
        expect(error, contains('invalid characters'));
      });
    });

    group('email', () {
      test('returns null for valid email addresses', () {
        expect(Validators.email('user@example.com'), isNull);
        expect(Validators.email('test.user@domain.co.uk'), isNull);
        expect(Validators.email('user+tag@example.com'), isNull);
      });

      test('returns null for empty string (not required)', () {
        expect(Validators.email(''), isNull);
        expect(Validators.email(null), isNull);
      });

      test('returns error for invalid email formats', () {
        expect(Validators.email('notanemail'), isNotNull);
        expect(Validators.email('@example.com'), isNotNull);
        expect(Validators.email('user@'), isNotNull);
        expect(Validators.email('user @example.com'), isNotNull);
      });
    });

    group('phoneNumber', () {
      test('returns null for valid phone numbers', () {
        expect(Validators.phoneNumber('5551234567'), isNull);
        expect(Validators.phoneNumber('555-123-4567'), isNull);
        expect(Validators.phoneNumber('(555) 123-4567'), isNull);
        expect(Validators.phoneNumber('+1 555 123 4567'), isNull);
      });

      test('returns null for empty string (not required)', () {
        expect(Validators.phoneNumber(''), isNull);
      });

      test('returns error for too few digits', () {
        final error = Validators.phoneNumber('123');
        expect(error, isNotNull);
        expect(error, contains('at least 10 digits'));
      });

      test('returns error for too many digits', () {
        final error = Validators.phoneNumber('12345678901234567');
        expect(error, isNotNull);
        expect(error, contains('too long'));
      });
    });

    group('url', () {
      test('returns null for valid URLs', () {
        expect(Validators.url('https://example.com'), isNull);
        expect(Validators.url('http://test.com/path'), isNull);
      });

      test('returns null for empty string (not required)', () {
        expect(Validators.url(''), isNull);
      });

      test('returns error for URLs without scheme', () {
        final error = Validators.url('example.com');
        expect(error, isNotNull);
        expect(error, contains('http://'));
      });

      test('returns error for non-http schemes', () {
        final error = Validators.url('ftp://example.com');
        expect(error, isNotNull);
        expect(error, contains('http://'));
      });
    });

    group('zipCode', () {
      test('returns null for valid 5-digit ZIP', () {
        expect(Validators.zipCode('12345'), isNull);
      });

      test('returns null for valid ZIP+4', () {
        expect(Validators.zipCode('12345-6789'), isNull);
      });

      test('returns null for empty string (not required)', () {
        expect(Validators.zipCode(''), isNull);
      });

      test('returns error for invalid formats', () {
        expect(Validators.zipCode('1234'), isNotNull);
        expect(Validators.zipCode('123456'), isNotNull);
        expect(Validators.zipCode('12345-678'), isNotNull);
        expect(Validators.zipCode('abcde'), isNotNull);
      });
    });

    group('notInFuture', () {
      test('returns null for past dates', () {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        expect(Validators.notInFuture(yesterday), isNull);
      });

      test('returns null for today', () {
        final today = DateTime.now();
        expect(Validators.notInFuture(today), isNull);
      });

      test('returns error for future dates', () {
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final error = Validators.notInFuture(tomorrow);
        expect(error, isNotNull);
        expect(error, contains('future'));
      });

      test('returns null for null value', () {
        expect(Validators.notInFuture(null), isNull);
      });
    });

    group('reasonablePurchaseDate', () {
      test('returns null for recent date', () {
        final lastYear = DateTime.now().subtract(const Duration(days: 365));
        expect(Validators.reasonablePurchaseDate(lastYear), isNull);
      });

      test('returns error for date 51 years ago', () {
        final fiftyOneYearsAgo = DateTime(DateTime.now().year - 51);
        final error = Validators.reasonablePurchaseDate(fiftyOneYearsAgo);
        expect(error, isNotNull);
        expect(error, contains('too far in the past'));
      });

      test('returns error for future date', () {
        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final error = Validators.reasonablePurchaseDate(tomorrow);
        expect(error, isNotNull);
        expect(error, contains('future'));
      });
    });

    group('combine', () {
      test('returns first error when multiple validators fail', () {
        final validator = Validators.combine([
          (v) => Validators.required(v, fieldName: 'Name'),
          (v) => Validators.minLength(v, 3, fieldName: 'Name'),
        ]);

        final error = validator('');
        expect(error, contains('required'));
      });

      test('returns null when all validators pass', () {
        final validator = Validators.combine([
          (v) => Validators.required(v, fieldName: 'Name'),
          (v) => Validators.minLength(v, 3, fieldName: 'Name'),
          (v) => Validators.maxLength(v, 10, fieldName: 'Name'),
        ]);

        final error = validator('Valid');
        expect(error, isNull);
      });

      test('stops at first error', () {
        var minLengthCalled = false;

        final validator = Validators.combine([
          (v) => Validators.required(v),
          (v) {
            minLengthCalled = true;
            return Validators.minLength(v, 3);
          },
        ]);

        validator(''); // Required will fail

        // Second validator shouldn't be called
        expect(minLengthCalled, isFalse);
      });
    });

    group('numericRange', () {
      test('returns null for value within range', () {
        expect(Validators.numericRange(5, 1, 10), isNull);
        expect(Validators.numericRange(1, 1, 10), isNull);
        expect(Validators.numericRange(10, 1, 10), isNull);
      });

      test('returns error for value below minimum', () {
        final error = Validators.numericRange(0, 1, 10);
        expect(error, isNotNull);
        expect(error, contains('between 1 and 10'));
      });

      test('returns error for value above maximum', () {
        final error = Validators.numericRange(11, 1, 10);
        expect(error, isNotNull);
      });

      test('returns null for null value', () {
        expect(Validators.numericRange(null, 1, 10), isNull);
      });
    });
  });
}
