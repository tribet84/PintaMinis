import 'package:flutter/foundation.dart' show visibleForTesting;

/// Where the project's public site lives.
const kSiteUrl = 'https://pintaminis.com';

/// Where the web app lives; shared recipe links point here.
///
/// Its own subdomain, separate from the site at the apex: a visitor arriving
/// at the bare domain wants to read what this is, while someone opening a
/// shared recipe wants the app itself, and one address cannot be both.
///
/// Links shared before the split pointed at the apex. The site carries a
/// redirect for those, so they still land in the right place.
const kAppUrl = 'https://app.pintaminis.com';

/// Where the legal documents live, on the public site rather than inside the
/// app: they have to stay readable to someone who has not signed in, and to
/// someone deciding whether to.
const kLegalUrl = '$kSiteUrl/legal';

/// Where feedback lands. Routed by the domain's email service to the
/// operator's inbox, so the address survives any future mailbox change.
const kFeedbackEmail = 'feedback@pintaminis.com';

/// Shareable URL for a published recipe.
///
/// A REAL path, not the hash form the app itself navigates with: a hash
/// fragment never reaches the server, so a crawler fetching a hash link
/// can only ever see the generic front page. The path form hits the
/// sharePreview function (hosting rewrite on /r/**), which serves the
/// recipe's Open Graph tags to crawlers and bounces browsers straight to
/// the hash form below — the format this app has parsed since the first
/// shared recipe, so links from before the switch keep working untouched.
String publicRecipeUrl(String publishedId) => '$kAppUrl/r/$publishedId';

/// Extracts the published-recipe id from a URL the app was opened with,
/// accepting both `/#/r/{id}` and `/r/{id}` forms.
String? publicRecipeIdFromUri(Uri uri) {
  final source = uri.fragment.isNotEmpty ? uri.fragment : uri.path;
  return RegExp(r'/r/([A-Za-z0-9_-]+)').firstMatch(source)?.group(1);
}

/// The share link the app was launched with, if any.
///
/// [capture] MUST run at the very top of `main()`, before the Flutter engine
/// is initialised: on web the engine takes over the URL as part of its
/// routing setup, so reading `Uri.base` later can find the fragment already
/// normalised away and the link silently lost.
///
/// [consume] then hands it over exactly once, so signing into a different
/// account does not re-open the same screen.
class PendingShareLink {
  PendingShareLink._();

  static String? _publishedId;
  static bool _consumed = false;

  static void capture() {
    _publishedId = publicRecipeIdFromUri(Uri.base);
  }

  /// Test seam: pretend the app was launched with [uri].
  @visibleForTesting
  static void captureFrom(Uri uri) {
    _publishedId = publicRecipeIdFromUri(uri);
    _consumed = false;
  }

  @visibleForTesting
  static void reset() {
    _publishedId = null;
    _consumed = false;
  }

  static String? consume() {
    if (_consumed) return null;
    _consumed = true;
    return _publishedId;
  }
}
