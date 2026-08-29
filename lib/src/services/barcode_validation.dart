/// Check-digit validation for retail barcodes.
///
/// A decoder handed a blurred or curved label does not simply fail — it can
/// return digits that are confidently wrong. Every retail symbology carries a
/// check digit for exactly this reason, and verifying it here costs nothing
/// and rejects the great majority of misreads before they reach the shelf.
///
/// Putting the wrong pot in someone's inventory is worse than reading
/// nothing: a failed scan is visible and gets retried, a wrong one is silent.
library;

/// Verifies the trailing check digit of an EAN-13, EAN-8 or UPC-A code.
///
/// All three use the same scheme: weight the data digits 3, 1, 3, 1 … working
/// leftwards from the check digit, and the check digit is whatever brings the
/// total to a multiple of ten.
bool hasValidCheckDigit(String digits) {
  if (digits.length < 8) return false;

  var sum = 0;
  var weight = 3;
  for (var i = digits.length - 2; i >= 0; i--) {
    final value = digits.codeUnitAt(i) - 0x30;
    if (value < 0 || value > 9) return false;
    sum += value * weight;
    weight = weight == 3 ? 1 : 3;
  }

  final expected = (10 - sum % 10) % 10;
  return expected == digits.codeUnitAt(digits.length - 1) - 0x30;
}

/// Returns the canonical form of a scanned code, or null if it cannot be one.
///
/// UPC-A is EAN-13 with a leading zero, and the same product scanned on two
/// devices can come back in either form. Normalising here means one product
/// is one key in the shared barcode map, rather than two rows nobody can
/// reconcile later.
String? normalizeBarcode(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  for (var i = 0; i < trimmed.length; i++) {
    final value = trimmed.codeUnitAt(i) - 0x30;
    if (value < 0 || value > 9) return null;
  }

  final code = trimmed.length == 12 ? '0$trimmed' : trimmed;
  if (code.length != 13 && code.length != 8) return null;
  if (!hasValidCheckDigit(code)) return null;

  return code;
}
