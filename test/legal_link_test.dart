import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/src/services/share_links.dart';

/// The platform is split across three hostnames — the site at the apex, the
/// app on its own subdomain, the photos on a third. Getting one of these
/// constants wrong ships a dead link that nothing else would catch.
void main() {
  test('the site and the app live at different addresses', () {
    expect(kSiteUrl, 'https://pintaminis.com');
    expect(kAppUrl, 'https://app.pintaminis.com');
    expect(
      kAppUrl,
      isNot(kSiteUrl),
      reason: 'a visitor reading about the project and a visitor opening a '
          'shared recipe want different pages',
    );
  });

  test('the legal link points at the public site, not into the app', () {
    expect(kLegalUrl, 'https://pintaminis.com/legal');
    expect(
      kLegalUrl,
      isNot(contains('app.')),
      reason: 'the policies have to be readable by someone who has not '
          'signed in, and by someone deciding whether to',
    );
  });

  test('every public URL is absolute and fully formed', () {
    for (final url in [kSiteUrl, kAppUrl, kLegalUrl]) {
      final uri = Uri.tryParse(url);
      expect(uri?.scheme, 'https', reason: '$url must be absolute https');
      expect(uri?.host, isNotEmpty);
      expect(url, isNot(contains(r'$')),
          reason: 'an uninterpolated placeholder would ship a dead link');
    }
  });

  test('share links are built on the app host, as a real path', () {
    final url = publicRecipeUrl('abc123');

    // Path form, not the hash form: the id must reach the server so the
    // sharePreview function can serve the recipe's Open Graph tags to
    // crawlers. A hash fragment never leaves the browser.
    expect(url, 'https://app.pintaminis.com/r/abc123');
    // Recovering the id from the link it produced is the round trip that
    // actually matters: the share flow is worthless if either half drifts.
    expect(publicRecipeIdFromUri(Uri.parse(url)), 'abc123');
  });

  test('a link shared before the split still resolves to its recipe', () {
    // The site redirects these to the app; the id must survive the trip.
    final legacy = Uri.parse('https://pintaminis.com/#/r/abc123');

    expect(publicRecipeIdFromUri(legacy), 'abc123');
  });
}
