import 'package:flutter/foundation.dart' show visibleForTesting;

/// Host that serves recipe photos through the CDN, empty when disabled.
///
/// Injected at build time (`--dart-define=PHOTO_CDN_HOST=img.pintaminis.com`)
/// rather than hardcoded, so the CDN can be turned off for a build without a
/// code change if it ever misbehaves.
const kPhotoCdnHost = String.fromEnvironment('PHOTO_CDN_HOST');

/// Session circuit breaker for the CDN host.
///
/// The CDN sits behind Cloudflare's proxy, whose shared IPs Spanish ISPs
/// block during LaLiga match windows. A blocked connection dies by TIMEOUT,
/// not by refusal — so without this flag every photo on screen would hang
/// for its own long timeout before falling back. The first failure trips
/// the breaker and every later photo skips straight to the direct Storage
/// URL. Deliberately never reset within the session: a block window
/// outlives any realistic app session, and one slow probe per session is
/// the acceptable cost of discovering it.
var _cdnDown = false;

/// True once a photo has failed to load through the CDN this session.
bool get photoCdnDown => _cdnDown;

/// Trips the breaker. Called by photo widgets when a CDN load errors.
void markPhotoCdnDown() => _cdnDown = true;

/// The breaker is process-global state; tests must not leak it into each
/// other.
@visibleForTesting
void resetPhotoCdnForTesting() => _cdnDown = false;

/// The host Firebase Storage hands out download URLs on.
const _storageHost = 'firebasestorage.googleapis.com';

/// Rewrites a Firebase Storage download URL to go through the CDN.
///
/// Applied when the photo is DISPLAYED, never when it is stored: the
/// Storage URL stays the single source of truth in Firestore. Turning the
/// CDN off is then a build flag rather than a data migration, and a recipe
/// saved today keeps rendering if the CDN host ever disappears.
///
/// The path and query string — including the access token that authorizes
/// the download — are preserved untouched, so the CDN cannot widen access
/// to anything the original URL did not already grant.
String cdnPhotoUrl(String url) {
  if (kPhotoCdnHost.isEmpty || _cdnDown) return url;

  final uri = Uri.tryParse(url);
  // Anything that is not a Storage download URL is left alone: legacy
  // values, and any future photo source, must not be silently rerouted.
  if (uri == null || uri.host != _storageHost) return url;

  return uri.replace(host: kPhotoCdnHost).toString();
}
