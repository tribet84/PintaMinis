import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/src/services/barcode_validation.dart';

void main() {
  group('check digits', () {
    test('real pot barcodes pass', () {
      // Verified against retailer listings, not derived: these are the codes
      // physically printed on the bottles.
      expect(hasValidCheckDigit('8429551709088'), isTrue); // Vallejo 70.908
      expect(hasValidCheckDigit('8429551777018'), isTrue); // Vallejo 77.701
      expect(hasValidCheckDigit('5713799208308'), isTrue); // TAP WP2083
    });

    test('a single wrong digit is caught', () {
      // The whole point: this is what a misread of a curved label looks like.
      expect(hasValidCheckDigit('8429551709089'), isFalse);
      expect(hasValidCheckDigit('8429551708088'), isFalse);
    });

    test('non-digits are never valid', () {
      expect(hasValidCheckDigit('842955170908X'), isFalse);
    });

    test('something far too short is not a barcode', () {
      expect(hasValidCheckDigit('123'), isFalse);
    });
  });

  group('normalisation', () {
    test('a valid EAN-13 comes back unchanged', () {
      expect(normalizeBarcode('8429551709088'), '8429551709088');
    });

    test('UPC-A is widened to EAN-13 so one pot is one key', () {
      // 12-digit UPC-A padded with a leading zero is the same GTIN; storing
      // both forms would split one product across two rows in the shared map.
      expect(normalizeBarcode('036000291452'), '0036000291452');
    });

    test('surrounding whitespace from a typed entry is tolerated', () {
      expect(normalizeBarcode('  8429551709088 '), '8429551709088');
    });

    test('a bad check digit is rejected, not passed through', () {
      expect(normalizeBarcode('8429551709089'), isNull);
    });

    test('lengths that are not a retail barcode are rejected', () {
      // The old filter accepted anything 8-14 digits long, which let
      // partial reads through as if they were codes.
      expect(normalizeBarcode('123456789'), isNull);
      expect(normalizeBarcode('12345678901234'), isNull);
    });

    test('letters and empty input are rejected', () {
      expect(normalizeBarcode('ABC123'), isNull);
      expect(normalizeBarcode(''), isNull);
      expect(normalizeBarcode('   '), isNull);
    });
  });
}
