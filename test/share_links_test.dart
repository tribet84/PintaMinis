import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/src/services/share_links.dart';

void main() {
  group('publicRecipeIdFromUri', () {
    test('reads the id from the link the app itself generates', () {
      final url = publicRecipeUrl('abc123');
      // The share link is the PATH form, so crawlers can see the id (a
      // hash fragment never reaches the server, so a hash link can never
      // grow an Open Graph preview).
      expect(url, 'https://app.pintaminis.com/r/abc123');
      expect(publicRecipeIdFromUri(Uri.parse(url)), 'abc123');
    });

    test('reads the id from a plain path form', () {
      expect(
        publicRecipeIdFromUri(Uri.parse('https://example.test/r/abc123')),
        'abc123',
      );
    });

    test('accepts Firestore ids containing dashes and underscores', () {
      expect(
        publicRecipeIdFromUri(Uri.parse('https://e.test/#/r/a-B_9zZ')),
        'a-B_9zZ',
      );
    });

    test('a trailing slash does not swallow the id', () {
      expect(
        publicRecipeIdFromUri(Uri.parse('https://e.test/#/r/abc123/')),
        'abc123',
      );
    });

    test('a bare app URL yields no id', () {
      expect(publicRecipeIdFromUri(Uri.parse('https://e.test/')), isNull);
      expect(publicRecipeIdFromUri(Uri.parse('https://e.test/#/')), isNull);
    });

    test('an unrelated path yields no id', () {
      expect(
        publicRecipeIdFromUri(Uri.parse('https://e.test/recipes/abc')),
        isNull,
      );
    });
  });

  group('publicRecipeUrl', () {
    test('round-trips through the parser', () {
      const id = 'XyZ_123-abc';
      expect(publicRecipeIdFromUri(Uri.parse(publicRecipeUrl(id))), id);
    });
  });

  group('PendingShareLink', () {
    setUp(PendingShareLink.reset);
    tearDown(PendingShareLink.reset);

    test('hands over the captured id exactly once', () {
      PendingShareLink.captureFrom(Uri.parse('https://e.test/#/r/abc123'));

      expect(PendingShareLink.consume(), 'abc123');
      expect(
        PendingShareLink.consume(),
        isNull,
        reason: 'signing into another account must not re-open the screen',
      );
    });

    test('a launch without a share link yields nothing', () {
      PendingShareLink.captureFrom(Uri.parse('https://e.test/'));
      expect(PendingShareLink.consume(), isNull);
    });

    test('the id survives the URL changing after capture', () {
      // This is the actual bug: the value must be read at capture time, not
      // looked up later from a URL the engine may already have rewritten.
      PendingShareLink.captureFrom(Uri.parse('https://e.test/#/r/abc123'));
      PendingShareLink.captureFrom(Uri.parse('https://e.test/#/r/abc123'));

      expect(PendingShareLink.consume(), 'abc123');
    });
  });
}
