import 'dart:typed_data';

import 'package:flutter/material.dart' hide Paint;
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/catalog_repository.dart';
import '../../data/recipe_photo_repository.dart';
import '../../models/recipe.dart';
import '../../state/recipes_provider.dart';
import '../../widgets/paint_widgets.dart';
import 'recipe_actions.dart';
import 'recipe_edit_screen.dart';
import 'recipe_paint_picker_screen.dart';
import 'recipe_photo_picker.dart';

/// The fast lane for a first recipe: photo, name, paints, save.
///
/// The full editor asks for structure before value — three levels deep
/// (recipe → section → step) is the right shape for a recipe worth
/// repeating, and the wrong first contact for someone the WhatsApp message
/// just asked to "publish your first recipe". This screen collapses that
/// to the three things a painter can answer without thinking, and stores
/// them as a single section so the full editor can split it into proper
/// sections later — same model, no migration, no second recipe type.
class QuickRecipeScreen extends StatefulWidget {
  const QuickRecipeScreen({super.key, this.initialPaintIds = const []});

  /// Paints the draft starts with — the colour search hands its resolved
  /// palette in here, so "sample the mini, get a recipe" is one flow.
  final List<String> initialPaintIds;

  @override
  State<QuickRecipeScreen> createState() => _QuickRecipeScreenState();
}

class _QuickRecipeScreenState extends State<QuickRecipeScreen> {
  final _nameController = TextEditingController();
  late final List<String> _paintIds = List.of(widget.initialPaintIds);
  Uint8List? _pendingPhoto;
  var _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickPaints() async {
    final selection = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) =>
            RecipePaintPickerScreen(initialSelection: _paintIds.toSet()),
      ),
    );
    if (selection == null) return;
    setState(() {
      // Keep the order paints were first added in; a Set would forget it
      // and the recipe's paint list would reshuffle on every edit.
      _paintIds
        ..removeWhere((id) => !selection.contains(id))
        ..addAll(selection.where((id) => !_paintIds.contains(id)));
    });
  }

  Future<void> _pickPhoto() async {
    final bytes = await pickAndCompressRecipePhoto(context);
    if (bytes != null) setState(() => _pendingPhoto = bytes);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final recipes = context.read<RecipesProvider>();
    final photos = context.read<RecipePhotoRepository>();

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.fieldRequired)));
      return;
    }

    setState(() => _saving = true);
    String? photoUrl;
    if (_pendingPhoto != null) {
      try {
        photoUrl = await photos.upload(_pendingPhoto!);
      } catch (_) {
        // The photo is a nicety; losing it must not lose the recipe. The
        // editor can re-add it later.
        photoUrl = null;
      }
    }

    await recipes.create(
      Recipe(
        id: '',
        name: name,
        photoUrl: photoUrl,
        sections: [
          RecipeSection(
            name: l10n.recipeQuickSection,
            steps: [
              // Untitled steps on purpose: the section card renders a bare
              // paint chip for these, which is exactly what a quick recipe
              // has to say. Titles arrive when the full editor gives the
              // steps something to be titled about.
              for (final id in _paintIds) RecipeStep(title: '', paintId: id),
            ],
          ),
        ],
        updatedAt: DateTime.now(),
      ),
    );
    navigator.pop();
  }

  bool get _isDirty =>
      _nameController.text.trim().isNotEmpty ||
      _paintIds.isNotEmpty ||
      _pendingPhoto != null;

  /// Same contract as the full editor: back never eats typed work silently.
  Future<void> _onPopAttempt(bool didPop, Object? result) async {
    if (didPop) return;
    final navigator = Navigator.of(context);
    if (!_isDirty || await confirmDiscardChanges(context)) {
      if (mounted) navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = context.read<CatalogRepository>();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopAttempt,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.recipesNew),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.actionSave),
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_pendingPhoto == null)
                OutlinedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  label: Text(l10n.recipeAddPhoto),
                )
              else
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _pendingPhoto!,
                        height: 180,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton.filledTonal(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() => _pendingPhoto = null),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.recipeNameLabel,
                  hintText: l10n.recipeNameHint,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickPaints,
                icon: const Icon(Icons.palette_outlined),
                label: Text(l10n.recipeQuickAddPaints),
              ),
              for (final id in _paintIds)
                if (catalog.byId(id) case final paint?)
                  PaintTile(
                    paint: paint,
                    showStatus: false,
                    trailing: IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(() => _paintIds.remove(id)),
                    ),
                  ),
              const SizedBox(height: 24),
              // The escape hatch for painters who think in sections from the
              // start. A plain push, not a hand-off: the quick draft is three
              // fields, cheaper to retype than a two-screen state transfer is
              // to maintain.
              TextButton.icon(
                onPressed: _saving
                    ? null
                    : () => Navigator.of(context).pushReplacement(
                        MaterialPageRoute<void>(
                          builder: (_) => const RecipeEditScreen(),
                        ),
                      ),
                icon: const Icon(Icons.tune),
                label: Text(l10n.recipeQuickFullEditor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
