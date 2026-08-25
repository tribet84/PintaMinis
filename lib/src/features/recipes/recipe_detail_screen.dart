import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/catalog_repository.dart';
import '../../models/recipe.dart';
import '../../services/external_link.dart';
import '../../services/share_links.dart';
import '../../state/inventory_provider.dart';
import '../../state/recipes_provider.dart';
import '../../widgets/paint_list_widgets.dart';
import '../../widgets/paint_widgets.dart';
import '../../widgets/recipe_photo.dart';
import '../../widgets/recipe_section_card.dart';
import 'recipe_actions.dart';
import 'recipe_edit_screen.dart';
import '../../widgets/recipe_photo_viewer.dart';
import '../../services/add_missing_to_shopping.dart';

/// One of the user's own recipes.
class RecipeDetailScreen extends StatelessWidget {
  const RecipeDetailScreen({super.key, required this.recipeId});

  final String recipeId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final recipes = context.watch<RecipesProvider>();
    final inventory = context.watch<InventoryProvider>();
    final catalog = context.read<CatalogRepository>();

    final recipe = recipes.byId(recipeId);
    if (recipe == null) {
      // Deleted from another device while this screen was open.
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: Icons.delete_outline,
          title: l10n.recipeDeleted,
          body: l10n.recipesEmptyBody,
        ),
      );
    }

    final readiness = recipe.readiness(inventory.entries);

    return Scaffold(
      appBar: AppBar(
        title: Text(recipe.name),
        actions: [
          IconButton(
            tooltip: l10n.recipeShare,
            icon: Icon(recipe.isPublished ? Icons.share : Icons.share_outlined),
            onPressed: () => _shareFlow(context, recipe),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'edit' => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecipeEditScreen(recipe: recipe),
                  ),
                ),
              'list' => createListFromRecipe(context, recipe),
              'duplicate' => _duplicate(context, recipe),
              'delete' => _delete(context, recipe),
              _ => null,
            },
            itemBuilder: (context) => [
              PopupMenuItem(value: 'edit', child: Text(l10n.recipeEdit)),
              PopupMenuItem(
                value: 'duplicate',
                child: Text(l10n.recipeDuplicate),
              ),
              PopupMenuItem(
                value: 'list',
                child: Text(l10n.recipeCreateList),
              ),
              PopupMenuItem(value: 'delete', child: Text(l10n.recipeDelete)),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          // The FAB column grows by one extended button when shopping is
          // needed; without matching padding its last rows hide behind it.
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            readiness.needsShopping ? 160 : 96,
          ),
          children: [
            if (recipe.hasPhoto) ...[
                  GestureDetector(
                    onTap: () => showRecipePhoto(context, recipe),
                    child: RecipePhoto(
                      recipe: recipe,
                      height: 200,
                      borderRadius: BorderRadius.circular(12),
                      heroTag: 'recipe-photo-${recipe.id}',
                    ),
                  ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Icon(
                  // A globe when shared, a padlock when it is yours alone.
                  recipe.isPublished ? Icons.public : Icons.lock_outline,
                  size: 16,
                  color: recipe.isPublished
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 6),
                Text(
                  recipe.isPublished
                      ? l10n.recipeSharedBadge
                      : l10n.recipePrivate,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: recipe.isPublished
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.outline,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (recipe.description.isNotEmpty) ...[
              Text(recipe.description),
              const SizedBox(height: 16),
            ],
            if (recipe.allPaintIds.isNotEmpty) ...[
              Row(
                children: [
                  PaintListStatusChip(readiness: readiness),
                  const Spacer(),
                  Text(
                    l10n.listPaintCount(readiness.total),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              PaintListReadinessBar(readiness: readiness),
              const SizedBox(height: 16),
            ],
            if (recipe.links.isNotEmpty) ...[
              Text(
                l10n.recipeLinksTitle,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
              for (final link in recipe.links)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    link.isYouTube ? Icons.ondemand_video : Icons.link,
                  ),
                  title: Text(link.title),
                  subtitle: Text(
                    link.url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => openExternalLink(link.url),
                ),
              const SizedBox(height: 8),
            ],
            Text(
              l10n.recipeSectionsTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            for (final section in recipe.sections)
              RecipeSectionCard(section: section, catalog: catalog),
          ],
        ),
      ),
      floatingActionButton: readiness.needsShopping
          ? FloatingActionButton.extended(
              heroTag: 'recipe-to-shopping',
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
              onPressed: () => addMissingToShopping(context, recipe.allPaintIds),
              icon: const Icon(Icons.add_shopping_cart),
              label: Text(l10n.listAddMissingToShopping),
            )
          : null,
    );
  }

  /// First share asks for confirmation and explains the link semantics;
  /// afterwards a sheet offers copy / share / stop sharing.
  Future<void> _shareFlow(BuildContext context, Recipe recipe) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final recipes = context.read<RecipesProvider>();

    if (!recipe.isPublished) {
      await confirmAndShareRecipe(context, recipe);
      return;
    }

    final url = publicRecipeUrl(recipe.publishedId!);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.copy),
              title: Text(l10n.recipeCopyLink),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await Clipboard.setData(ClipboardData(text: url));
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.recipeLinkCopied)),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.share),
              title: Text(l10n.recipeShareLink),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final text = l10n.recipeShareText(recipe.name, url);
                try {
                  // Throws when there is no native share sheet to hand off
                  // to; only then should this fall back to the clipboard —
                  // with a message distinct from the "Copy link" action above
                  // it, so the two never look like the same button twice.
                  await SharePlus.instance.share(
                    ShareParams(text: text, subject: recipe.name),
                  );
                } catch (_) {
                  await Clipboard.setData(ClipboardData(text: text));
                  messenger.showSnackBar(
                    SnackBar(content: Text(l10n.shareFallbackCopied)),
                  );
                }
              },
            ),
            ListTile(
              leading: Icon(
                Icons.link_off,
                color: Theme.of(sheetContext).colorScheme.error,
              ),
              title: Text(
                l10n.recipeStopSharing,
                style: TextStyle(
                  color: Theme.of(sheetContext).colorScheme.error,
                ),
              ),
              subtitle: Text(l10n.recipeStopSharingBody),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await recipes.unpublish(recipe);
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.recipeUnpublished)),
                );
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _duplicate(BuildContext context, Recipe recipe) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<RecipesProvider>();

    final newId = await provider.duplicate(
      recipe,
      copyName: l10n.recipeCopyName(recipe.name),
    );
    messenger.showSnackBar(SnackBar(content: Text(l10n.recipeDuplicated)));
    // Land ON the copy: the whole point of duplicating is editing it next,
    // and finding yourself still on the original invites editing the wrong
    // one.
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => RecipeDetailScreen(recipeId: newId),
      ),
    );
  }

  Future<void> _delete(BuildContext context, Recipe recipe) async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<RecipesProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.recipeDeleteConfirmTitle),
        content: Text(l10n.recipeDeleteConfirmBody(recipe.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.actionDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await provider.delete(recipe);
    messenger.showSnackBar(SnackBar(content: Text(l10n.recipeDeleted)));
    navigator.pop();
  }
}
