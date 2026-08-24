import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/src/services/photo_cdn.dart';
import 'package:paintforge/src/widgets/recipe_photo.dart';

/// These run WITHOUT the PHOTO_CDN_HOST define, which is the default for
/// `flutter test`. That is deliberate: the contract worth pinning is that a
/// build with no CDN configured leaves every URL exactly as Storage handed
/// it out, so the feature can be switched off without breaking photos.
void main() {
  group('with no CDN host configured', () {
    test('kPhotoCdnHost defaults to empty', () {
      expect(kPhotoCdnHost, isEmpty);
    });

    test('a Storage download URL is returned untouched', () {
      const url =
          'https://firebasestorage.googleapis.com/v0/b/paintforge-d8cf2.firebasestorage.app'
          '/o/users%2Fabc%2FrecipePhotos%2F123.jpg?alt=media&token=deadbeef';

      expect(cdnPhotoUrl(url), url);
    });

    test('a URL from any other host is left alone', () {
      const url = 'https://example.com/photo.jpg';

      expect(cdnPhotoUrl(url), url);
    });

    test('an unparseable value does not throw', () {
      expect(cdnPhotoUrl('not a url at all'), 'not a url at all');
      expect(cdnPhotoUrl(''), '');
    });
  });

  group('CDN circuit breaker', () {
    tearDown(resetPhotoCdnForTesting);

    test('starts closed and trips permanently for the session', () {
      expect(photoCdnDown, isFalse);
      markPhotoCdnDown();
      expect(photoCdnDown, isTrue);
      // No un-trip API on purpose: a LaLiga block window outlives any
      // realistic app session. Only the test seam resets it.
    });

    test('a tripped breaker forces every URL to its direct form', () {
      const url =
          'https://firebasestorage.googleapis.com/v0/b/paintforge-d8cf2.firebasestorage.app'
          '/o/users%2Fabc%2FrecipePhotos%2F123.jpg?alt=media&token=deadbeef';
      markPhotoCdnDown();
      // With no CDN host configured this is also passthrough, so the pin
      // here is stability: tripping the breaker must never change a URL
      // into something new.
      expect(cdnPhotoUrl(url), url);
    });
  });

  group('StoragePhoto', () {
    tearDown(resetPhotoCdnForTesting);

    testWidgets('a direct-URL failure shows the error widget, no retry loop',
        (tester) async {
      // In widget tests every HTTP fetch fails, which IS the scenario: the
      // photo is unreachable on its direct URL. That must land on the error
      // widget without tripping the breaker — a direct failure says nothing
      // about the CDN.
      await tester.pumpWidget(
        const MaterialApp(
          home: StoragePhoto(
            url: 'https://firebasestorage.googleapis.com/v0/b/x/o/y.jpg',
            fit: BoxFit.cover,
            height: 100,
            errorWidget: Icon(Icons.broken_image_outlined),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
      expect(photoCdnDown, isFalse);
    });
  });
}
