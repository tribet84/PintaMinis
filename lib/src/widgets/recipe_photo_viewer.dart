import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../models/recipe.dart';
import 'recipe_photo.dart';

/// Opens a recipe's cover photo full screen. No-op when there is no photo.
Future<void> showRecipePhoto(BuildContext context, Recipe recipe) {
  if (!recipe.hasPhoto) return Future.value();
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      // Opaque false lets the Hero fly over the recipe still visible behind
      // it, so the photo reads as growing rather than as a new screen.
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) => _RecipePhotoViewer(recipe: recipe),
    ),
  );
}

/// Full-screen photo with pinch-to-zoom.
///
/// Zoom is the point rather than a flourish: the photo is someone's paint
/// job, and the detail a painter wants — how a highlight was feathered, how
/// thin a glaze went on — is invisible in a 200px thumbnail.
class _RecipePhotoViewer extends StatelessWidget {
  const _RecipePhotoViewer({required this.recipe});

  final Recipe recipe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final url = recipe.photoUrl;
    final provider = recipePhotoProvider(recipe);
    if (provider == null) return const SizedBox.shrink();

    final brokenIcon = Icon(
      Icons.broken_image_outlined,
      size: 64,
      color: Colors.white.withValues(alpha: 0.7),
    );
    // Storage photos get the CDN fallback; legacy base64 keeps the plain
    // provider — memory never fails over a network block.
    final photo = url != null && url.isNotEmpty
        ? StoragePhoto(url: url, fit: BoxFit.contain, errorWidget: brokenIcon)
        : Image(
            image: provider,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => brokenIcon,
          );

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tapping anywhere off the photo closes it, which is where a
          // thumb naturally lands after looking.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Center(
                child: Hero(
                  tag: 'recipe-photo-${recipe.id}',
                  child: InteractiveViewer(
                    minScale: 1,
                    maxScale: 5,
                    child: photo,
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: SafeArea(
              child: IconButton(
                tooltip: l10n.actionClose,
                icon: const Icon(Icons.close),
                color: Colors.white,
                style: IconButton.styleFrom(backgroundColor: Colors.black45),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
