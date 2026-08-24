import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/published_recipe_repository.dart';
import '../../state/inventory_provider.dart';
import '../../state/recipes_provider.dart';
import '../../widgets/paint_widgets.dart';
import '../../widgets/recipe_card.dart';
import 'public_recipe_screen.dart';
import 'recipe_detail_screen.dart';
import 'quick_recipe_screen.dart';
import '../../widgets/brand_loader.dart';

/// Every recipe available to the user — the ones they wrote and the ones they
/// linked — rendered by the SAME card, since they read the same way. Only the
/// badge distinguishes them.
class RecipesScreen extends StatelessWidget {
  const RecipesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recipes = context.watch<RecipesProvider>();
    final inventory = context.watch<InventoryProvider>();

    return SafeArea(
      child: Stack(
        children: [
          // "Still loading" and "genuinely empty" both look like an empty
          // list, so without this check a painter with a shelf full of
          // recipes is told they have none until Firestore answers.
          if (!recipes.loaded)
            const Center(child: BrandLoader())
          else if (recipes.recipes.isEmpty && recipes.linkedIds.isEmpty)
            EmptyState(
              icon: Icons.auto_stories_outlined,
              title: l10n.recipesEmptyTitle,
              body: l10n.recipesEmptyBody,
              action: FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const QuickRecipeScreen(),
                  ),
                ),
                icon: const Icon(Icons.add),
                label: Text(l10n.recipesNew),
              ),
            )
          else
            ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 96),
              children: [
                for (final recipe in recipes.recipes)
                  RecipeCard(
                    recipe: recipe,
                    origin: recipe.isPublished
                        ? RecipeOrigin.ownShared
                        : RecipeOrigin.ownPrivate,
                    // No verdict against an empty shelf: grading every card
                    // "Missing paints" before the user owns a single pot is
                    // noise, and it made the sample recipe greet brand-new
                    // accounts with a red warning.
                    readiness: inventory.entries.isEmpty
                        ? null
                        : recipe.readiness(inventory.entries),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RecipeDetailScreen(recipeId: recipe.id),
                      ),
                    ),
                  ),
                for (final publishedId in recipes.linkedIds)
                  _LinkedRecipeCard(publishedId: publishedId),
              ],
            ),
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.extended(
              heroTag: 'recipes-new',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const QuickRecipeScreen(),
                ),
              ),
              icon: const Icon(Icons.add),
              label: Text(l10n.recipesNew),
            ),
          ),
        ],
      ),
    );
  }
}

/// A linked recipe, streamed live from the public collection so it always
/// shows the author's latest version — then handed to the very same card.
class _LinkedRecipeCard extends StatelessWidget {
  const _LinkedRecipeCard({required this.publishedId});

  final String publishedId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final repository = context.read<PublishedRecipeRepository>();
    final inventory = context.watch<InventoryProvider>();

    return StreamBuilder<PublishedRecipe?>(
      stream: repository.watchPublished(publishedId),
      builder: (context, snapshot) {
        final published = snapshot.data;
        if (published == null) {
          final stillLoading =
              snapshot.connectionState == ConnectionState.waiting;
          // Either still loading, or the author stopped sharing it — in
          // which case there is nothing left to open, only to clear.
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.bookmark_remove_outlined),
              title: Text(stillLoading ? l10n.loading : l10n.recipeNotShared),
              trailing: stillLoading
                  ? null
                  : IconButton(
                      tooltip: l10n.recipeUnlinkAction,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _removeDeadLink(context),
                    ),
              onTap: stillLoading
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PublicRecipeScreen(publishedId: publishedId),
                        ),
                      ),
            ),
          );
        }

        return RecipeCard(
          recipe: published.recipe,
          origin: RecipeOrigin.linked,
          authorName: published.authorName,
          // Same rule as the owner's cards above: an empty shelf gets no
          // verdict, not a wall of red.
          readiness: inventory.entries.isEmpty
              ? null
              : published.recipe.readiness(inventory.entries),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PublicRecipeScreen(publishedId: publishedId),
            ),
          ),
        );
      },
    );
  }

  Future<void> _removeDeadLink(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await context.read<RecipesProvider>().unlink(publishedId);
    messenger.showSnackBar(SnackBar(content: Text(l10n.recipeUnlinked)));
  }
}
