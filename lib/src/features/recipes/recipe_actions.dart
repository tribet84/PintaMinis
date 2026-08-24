import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../models/recipe.dart';
import '../../services/recipe_to_list.dart';
import '../../services/share_links.dart';
import '../../state/paint_lists_provider.dart';
import '../../state/recipes_provider.dart';

/// Asks whether unsaved edits should really be thrown away. True = leave.
///
/// Every draft screen (recipe editor, quick create, section editor) guards
/// its back gesture with this: losing typed work to a stray back press is
/// the most expensive friction an editor can have, and it costs nothing to
/// ask — the dialog only appears when something was actually changed.
Future<bool> confirmDiscardChanges(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final discard = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.recipeDiscardTitle),
      content: Text(l10n.recipeDiscardBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.recipeKeepEditing),
        ),
        // Filled and destructive-flavoured on purpose: this is the button
        // that eats work, it must not look like the safe default.
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.recipeDiscardAction),
        ),
      ],
    ),
  );
  return discard ?? false;
}

/// Asks whether to turn [recipe] into a paint list, and does it.
///
/// The list is a snapshot of the paints the recipe uses: it does not stay in
/// sync with the recipe afterwards, which is deliberate — a list tracks what
/// you need on the shelf for a project, and editing one should never
/// silently rewrite the other.
Future<void> createListFromRecipe(BuildContext context, Recipe recipe) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final lists = context.read<PaintListsProvider>();

  final paintIds = paintIdsForListFrom(recipe);
  if (paintIds.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.recipeEmptySection)),
    );
    return;
  }

  final name = listNameForRecipe(recipe);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.recipeCreateList),
      content: Text(l10n.recipeCreateListBody(paintIds.length, name)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.actionConfirm),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  await lists.createWithPaints(name, paintIds);
  messenger
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text(l10n.recipeListCreated(name))));
}

/// First-share flow: explains what publishing means, publishes, and leaves
/// the link on the clipboard.
///
/// Shared between the detail screen's share button and the save-time nudge,
/// so the consent dialog — publishing exposes the recipe AND an author name
/// — can never be skipped by taking the shorter path.
Future<void> confirmAndShareRecipe(BuildContext context, Recipe recipe) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final recipes = context.read<RecipesProvider>();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.recipeShareTitle),
      content: Text(l10n.recipeShareBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(l10n.recipeShare),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final publishedId = await recipes.publish(recipe);
  if (publishedId == null) return;
  await Clipboard.setData(ClipboardData(text: publicRecipeUrl(publishedId)));
  messenger.showSnackBar(SnackBar(content: Text(l10n.recipeLinkCopied)));
}
