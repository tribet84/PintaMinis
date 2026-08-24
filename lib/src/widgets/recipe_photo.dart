import 'package:flutter/material.dart';

import '../models/recipe.dart';
import '../services/image_compressor.dart';
import '../services/photo_cdn.dart';

/// The image behind a recipe's cover photo, whichever source it has.
///
/// New photos live in Cloud Storage and are referenced by URL; recipes saved
/// before Storage was available carry base64 in the document instead. Both
/// have to keep working, so the choice lives here rather than in every screen
/// that shows a picture — and sharing one provider means the thumbnail and
/// the full-screen view hit the same cache entry instead of downloading the
/// photo twice.
ImageProvider? recipePhotoProvider(Recipe recipe) {
  final url = recipe.photoUrl;
  if (url != null && url.isNotEmpty) return NetworkImage(cdnPhotoUrl(url));
  final legacy = decodePhoto(recipe.photo);
  if (legacy != null) return MemoryImage(legacy);
  return null;
}

/// A Storage photo that survives the CDN being unreachable.
///
/// Loads through the CDN when it is up; when that load errors it trips the
/// session breaker in photo_cdn.dart and rebuilds against the direct
/// Storage URL, which never passes through Cloudflare and so never falls to
/// a LaLiga block window. A photo that is genuinely gone fails on both
/// hosts and lands on [errorWidget], same as before the fallback existed.
class StoragePhoto extends StatefulWidget {
  const StoragePhoto({
    super.key,
    required this.url,
    required this.fit,
    this.height,
    this.width,
    this.showLoader = false,
    this.errorWidget = const SizedBox.shrink(),
  });

  /// The direct Storage URL — the stored source of truth, never the CDN
  /// form. This widget decides per build which host actually serves it.
  final String url;

  final BoxFit fit;
  final double? height;
  final double? width;

  /// Show a centred spinner while loading (used by card thumbnails, where
  /// a silent gap reads as a missing photo).
  final bool showLoader;

  /// Shown when the photo cannot be loaded from ANY host.
  final Widget errorWidget;

  @override
  State<StoragePhoto> createState() => _StoragePhotoState();
}

class _StoragePhotoState extends State<StoragePhoto> {
  @override
  Widget build(BuildContext context) {
    final resolved = cdnPhotoUrl(widget.url);
    return Image.network(
      resolved,
      height: widget.height,
      width: widget.width,
      fit: widget.fit,
      loadingBuilder: !widget.showLoader
          ? null
          : (context, child, progress) => progress == null
              ? child
              : SizedBox(
                  height: widget.height,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
      errorBuilder: (context, error, stackTrace) {
        // Only fall back when the CDN was the host that failed; a direct
        // Storage failure means the photo itself is the problem.
        if (resolved != widget.url) {
          markPhotoCdnDown();
          // errorBuilder runs during build, so the rebuild that swaps to
          // the direct URL has to wait for the frame to finish.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() {});
          });
          return SizedBox(
            height: widget.height,
            child: widget.showLoader
                ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                : null,
          );
        }
        return widget.errorWidget;
      },
    );
  }
}

/// A recipe's cover photo, cropped to fill [height].
class RecipePhoto extends StatelessWidget {
  const RecipePhoto({
    super.key,
    required this.recipe,
    required this.height,
    this.borderRadius,
    this.heroTag,
  });

  final Recipe recipe;
  final double height;
  final BorderRadius? borderRadius;

  /// Ties this thumbnail to the full-screen view it opens, so the photo
  /// grows out of the card instead of cutting to a new screen.
  final Object? heroTag;

  @override
  Widget build(BuildContext context) {
    final url = recipe.photoUrl;
    final legacy = url == null || url.isEmpty ? decodePhoto(recipe.photo) : null;
    if ((url == null || url.isEmpty) && legacy == null) {
      return const SizedBox.shrink();
    }

    Widget image = url != null && url.isNotEmpty
        // Storage photos go through the CDN-with-fallback widget so a
        // Cloudflare block window costs cache hits, not visible photos.
        ? StoragePhoto(
            url: url,
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            showLoader: true,
            // A photo that fails to load must not take the card with it.
            errorWidget: const SizedBox.shrink(),
          )
        : Image(
            image: MemoryImage(legacy!),
            height: height,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );

    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius!, child: image);
    }
    if (heroTag != null) {
      image = Hero(tag: heroTag!, child: image);
    }
    return image;
  }
}
