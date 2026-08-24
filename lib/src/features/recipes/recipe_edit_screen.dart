import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/recipe_photo_repository.dart';
import '../../models/recipe.dart';
import '../../services/image_compressor.dart';
import '../../widgets/recipe_photo.dart';
import '../../state/recipes_provider.dart';
import '../../widgets/technique_widgets.dart';
import 'recipe_photo_picker.dart';
import 'recipe_section_edit_screen.dart';
import 'recipe_actions.dart';

/// Create or edit a recipe: name, description, inspiration links and the
/// per-section breakdown. Everything is edited as an in-memory draft and only
/// persisted when the user saves.
class RecipeEditScreen extends StatefulWidget {
  const RecipeEditScreen({super.key, this.recipe});

  /// Null when creating a new recipe.
  final Recipe? recipe;

  @override
  State<RecipeEditScreen> createState() => _RecipeEditScreenState();
}

class _RecipeEditScreenState extends State<RecipeEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late List<RecipeSection> _sections;
  late List<RecipeLink> _links;

  /// Existing photo URL, if the recipe already had one.
  String? _photoUrl;

  /// Newly picked bytes, held in memory until save so an abandoned edit
  /// leaves nothing behind in Storage.
  Uint8List? _pendingPhoto;

  /// Set when the user explicitly removed the existing photo.
  var _photoCleared = false;

  var _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.recipe?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.recipe?.description ?? '',
    );
    _sections = List.of(widget.recipe?.sections ?? const []);
    _links = List.of(widget.recipe?.links ?? const []);
    _photoUrl = widget.recipe?.photoUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  /// Whether the draft differs from what was opened.
  ///
  /// Sections and links compare by IDENTITY, not by value, and that is
  /// enough: List.of copies the list but not its elements, so an untouched
  /// section is still the exact same object, while any edit path replaces
  /// it — equality operators on the model would buy nothing here.
  bool get _isDirty {
    final original = widget.recipe;
    if (_pendingPhoto != null || _photoCleared) return true;
    if (_nameController.text.trim() != (original?.name ?? '')) return true;
    if (_descriptionController.text.trim() != (original?.description ?? '')) {
      return true;
    }
    if (!listEquals(_sections, original?.sections ?? const [])) return true;
    if (!listEquals(_links, original?.links ?? const [])) return true;
    return false;
  }

  /// Back must never eat typed work silently. canPop stays false so EVERY
  /// back attempt lands here with the dirtiness computed at that moment —
  /// a conditional canPop goes stale, since typing in a controller does not
  /// rebuild this widget. Saving is unaffected: Navigator.pop() bypasses
  /// PopScope by design; only back gestures ask permission.
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

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onPopAttempt,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.recipe == null ? l10n.recipesNew : l10n.recipeEdit,
          ),
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
              _PhotoField(
                pendingPhoto: _pendingPhoto,
                photoUrl: _photoCleared ? null : _photoUrl,
                legacyPhoto: _photoCleared ? null : widget.recipe?.photo,
                onPick: () async {
                  final bytes = await pickAndCompressRecipePhoto(context);
                  if (bytes != null) {
                    setState(() {
                      _pendingPhoto = bytes;
                      _photoCleared = false;
                    });
                  }
                },
                onRemove: () => setState(() {
                  _pendingPhoto = null;
                  _photoCleared = true;
                }),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.recipeNameLabel,
                  hintText: l10n.recipeNameHint,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l10n.recipeDescriptionLabel,
                ),
              ),
              const SizedBox(height: 24),
              _Header(
                title: l10n.recipeLinksTitle,
                onAdd: _addLink,
                addLabel: l10n.recipeAddLink,
              ),
              for (var i = 0; i < _links.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    _links[i].isYouTube ? Icons.ondemand_video : Icons.link,
                  ),
                  title: Text(_links[i].title),
                  subtitle: Text(
                    _links[i].url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() => _links.removeAt(i)),
                  ),
                ),
              const SizedBox(height: 16),
              _Header(
                title: l10n.recipeSectionsTitle,
                onAdd: _addSection,
                addLabel: l10n.recipeAddSection,
              ),
              for (var i = 0; i < _sections.length; i++)
                Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    title: Text(_sections[i].name),
                    subtitle: Text(
                      '${l10n.listPaintCount(_sections[i].paintIds.length)}'
                      '${_sections[i].techniques.isEmpty ? '' : ' · ${_sections[i].techniques.map((t) => techniqueLabel(l10n, t)).join(', ')}'}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: l10n.recipeRemoveSection,
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _sections.removeAt(i)),
                    ),
                    onTap: () => _editSection(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addLink() async {
    final link = await showRecipeLinkDialog(context);
    if (link == null) return;
    setState(() => _links.add(link));
  }

  Future<void> _addSection() async {
    final section = await Navigator.of(context).push<RecipeSection>(
      MaterialPageRoute(builder: (_) => const RecipeSectionEditScreen()),
    );
    if (section == null) return;
    setState(() => _sections.add(section));
  }

  Future<void> _editSection(int index) async {
    final section = await Navigator.of(context).push<RecipeSection>(
      MaterialPageRoute(
        builder: (_) => RecipeSectionEditScreen(section: _sections[index]),
      ),
    );
    if (section == null) return;
    setState(() => _sections[index] = section);
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<RecipesProvider>();

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.fieldRequired)));
      return;
    }

    setState(() => _saving = true);

    // Upload only now, so a draft that was never saved costs nothing.
    final photos = context.read<RecipePhotoRepository>();
    var photoUrl = _photoCleared ? null : _photoUrl;
    if (_pendingPhoto != null) {
      try {
        photoUrl = await photos.upload(_pendingPhoto!);
      } catch (_) {
        setState(() => _saving = false);
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.recipePhotoUploadFailed)),
        );
        return;
      }
    }
    // The replaced or removed photo is only unreachable once the recipe no
    // longer points at it, so clean up after the new URL is decided.
    final previousUrl = widget.recipe?.photoUrl;
    if (previousUrl != null && previousUrl != photoUrl) {
      await photos.deleteByUrl(previousUrl);
    }

    final draft = Recipe(
      id: widget.recipe?.id ?? '',
      name: name,
      description: _descriptionController.text.trim(),
      sections: _sections,
      links: _links,
      // The legacy base64 field is never written again; it is only kept
      // when the recipe still carries one and the user did not replace it.
      photo: (_photoCleared || _pendingPhoto != null)
          ? null
          : widget.recipe?.photo,
      photoUrl: photoUrl,
      // Keep the published link alive so saving pushes the update to
      // everyone who linked the recipe.
      publishedId: widget.recipe?.publishedId,
      updatedAt: widget.recipe?.updatedAt ?? DateTime.now(),
    );
    if (widget.recipe == null) {
      final id = await provider.create(draft);
      // The proud moment: a brand-new recipe with a photo of the finished
      // mini. Offer sharing ONCE, as a snackbar action — dismissable by
      // simply ignoring it. The action still routes through the consent
      // dialog; the nudge shortens the path, never the explanation. Edits
      // never nag: this only fires on first save.
      if (photoUrl != null) {
        final saved = Recipe(
          id: id,
          name: draft.name,
          description: draft.description,
          sections: draft.sections,
          links: draft.links,
          photoUrl: draft.photoUrl,
          updatedAt: draft.updatedAt,
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(l10n.recipeShareNudge),
            action: SnackBarAction(
              label: l10n.recipeShareNudgeAction,
              // The editor is popped by then; the navigator outlives it and
              // its context can still host the consent dialog.
              onPressed: () => confirmAndShareRecipe(navigator.context, saved),
            ),
          ),
        );
        navigator.pop();
        return;
      }
    } else {
      await provider.update(draft);
    }
    messenger.showSnackBar(SnackBar(content: Text(l10n.recipeSaved)));
    navigator.pop();
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.onAdd,
    required this.addLabel,
  });

  final String title;
  final VoidCallback onAdd;
  final String addLabel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: Text(addLabel),
        ),
      ],
    );
  }
}

/// Prompts for a link title and URL; returns null if cancelled.
Future<RecipeLink?> showRecipeLinkDialog(BuildContext context) {
  final l10n = AppLocalizations.of(context);
  final titleController = TextEditingController();
  final urlController = TextEditingController();

  return showDialog<RecipeLink>(
    context: context,
    builder: (dialogContext) {
      var urlError = false;
      return StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.recipeAddLink),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(labelText: l10n.linkTitleLabel),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: l10n.linkUrlLabel,
                  errorText: urlError ? l10n.linkInvalidUrl : null,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.actionCancel),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                final url = urlController.text.trim();
                final uri = Uri.tryParse(url);
                final valid =
                    uri != null &&
                    (uri.scheme == 'http' || uri.scheme == 'https') &&
                    uri.host.isNotEmpty;
                if (title.isEmpty || !valid) {
                  setState(() => urlError = !valid);
                  return;
                }
                Navigator.of(
                  dialogContext,
                ).pop(RecipeLink(title: title, url: url));
              },
              child: Text(l10n.actionSave),
            ),
          ],
        ),
      );
    },
  );
}

/// Cover photo field: a preview with replace/remove, or a prompt to add one.
///
/// Shows, in order of preference, the freshly picked bytes, the uploaded
/// photo, or a legacy base64 one from before Storage existed.
class _PhotoField extends StatelessWidget {
  const _PhotoField({
    required this.pendingPhoto,
    required this.photoUrl,
    required this.legacyPhoto,
    required this.onPick,
    required this.onRemove,
  });

  final Uint8List? pendingPhoto;
  final String? photoUrl;
  final String? legacyPhoto;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final legacyBytes = decodePhoto(legacyPhoto);
    final hasPhoto =
        pendingPhoto != null || photoUrl != null || legacyBytes != null;

    if (!hasPhoto) {
      return OutlinedButton.icon(
        onPressed: onPick,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: Text(l10n.recipeAddPhoto),
      );
    }

    final Widget preview;
    if (pendingPhoto != null) {
      preview = Image.memory(
        pendingPhoto!,
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    } else if (photoUrl != null) {
      preview = StoragePhoto(
        url: photoUrl!,
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    } else {
      preview = Image.memory(
        legacyBytes!,
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(borderRadius: BorderRadius.circular(12), child: preview),
        const SizedBox(height: 4),
        Row(
          children: [
            TextButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.swap_horiz, size: 18),
              label: Text(l10n.recipeReplacePhoto),
            ),
            TextButton.icon(
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(l10n.recipeRemovePhoto),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
