import 'package:flutter/foundation.dart' show listEquals, setEquals;
import 'package:flutter/material.dart' hide Paint;
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/catalog_repository.dart';
import '../../models/recipe.dart';
import '../../widgets/paint_widgets.dart';
import '../../widgets/technique_widgets.dart';
import 'recipe_actions.dart';
import 'recipe_paint_picker_screen.dart';

/// Edits one recipe section as a local draft and returns it via `pop`.
class RecipeSectionEditScreen extends StatefulWidget {
  const RecipeSectionEditScreen({super.key, this.section});

  /// Null when adding a new section.
  final RecipeSection? section;

  @override
  State<RecipeSectionEditScreen> createState() =>
      _RecipeSectionEditScreenState();
}

class _RecipeSectionEditScreenState extends State<RecipeSectionEditScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _notesController;
  late List<RecipeStep> _steps;
  late Set<PaintTechnique> _techniques;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.section?.name ?? '');
    _notesController = TextEditingController(text: widget.section?.notes ?? '');
    _steps = List.of(widget.section?.steps ?? const []);
    _techniques = Set.of(widget.section?.techniques ?? const {});
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Steps compare by identity, same trick as the recipe editor: List.of
  /// copies the list, not the elements, so any edit replaces an element and
  /// an untouched draft still holds the original instances.
  bool get _isDirty {
    final original = widget.section;
    if (_nameController.text.trim() != (original?.name ?? '')) return true;
    if (_notesController.text.trim() != (original?.notes ?? '')) return true;
    if (!setEquals(_techniques, original?.techniques ?? const {})) return true;
    if (!listEquals(_steps, original?.steps ?? const [])) return true;
    return false;
  }

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
          title: Text(
            widget.section == null
                ? l10n.recipeAddSection
                : l10n.recipeEditSection,
          ),
          actions: [TextButton(onPressed: _save, child: Text(l10n.actionSave))],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextField(
                controller: _nameController,
                autofocus: widget.section == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.sectionNameLabel,
                  hintText: l10n.sectionNameHint,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                l10n.sectionTechniquesLabel,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final technique in PaintTechnique.values)
                    FilterChip(
                      label: Text(techniqueLabel(l10n, technique)),
                      selected: _techniques.contains(technique),
                      onSelected: (selected) => setState(() {
                        if (selected) {
                          _techniques.add(technique);
                        } else {
                          _techniques.remove(technique);
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.sectionStepsLabel,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addStep,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(l10n.recipeAddStep),
                  ),
                ],
              ),
              Text(
                l10n.sectionStepsHelp,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              // The order IS the recipe, so steps are drag-reorderable.
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: true,
                itemCount: _steps.length,
                // Unlike the deprecated onReorder, newIndex arrives already
                // adjusted for the removed item.
                onReorderItem: (oldIndex, newIndex) => setState(() {
                  final step = _steps.removeAt(oldIndex);
                  _steps.insert(newIndex, step);
                }),
                itemBuilder: (context, index) {
                  final step = _steps[index];
                  final paint = step.paintId == null
                      ? null
                      : catalog.byId(step.paintId!);
                  return ListTile(
                    key: ValueKey('step-$index-${step.title}-${step.paintId}'),
                    leading: paint == null
                        ? const SizedBox(width: 24)
                        : PaintSwatch(paint: paint, size: 24),
                    title: Text(
                      [
                        if (step.title.isNotEmpty) step.title,
                        if (paint != null) paint.name,
                      ].join(': '),
                    ),
                    subtitle: step.note.isEmpty ? null : Text(step.note),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() => _steps.removeAt(index)),
                    ),
                    onTap: () => _editStep(index),
                  );
                },
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _notesController,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l10n.sectionNotesLabel,
                  hintText: l10n.sectionNotesHint,
                  alignLabelWithHint: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addStep() async {
    final step = await _showStepEditor();
    if (step == null) return;
    setState(() => _steps.add(step));
  }

  Future<void> _editStep(int index) async {
    final step = await _showStepEditor(initial: _steps[index]);
    if (step == null) return;
    setState(() => _steps[index] = step);
  }

  Future<RecipeStep?> _showStepEditor({RecipeStep? initial}) {
    return showDialog<RecipeStep>(
      context: context,
      builder: (_) => _StepEditorDialog(initial: initial),
    );
  }

  void _save() {
    final l10n = AppLocalizations.of(context);
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.fieldRequired)));
      return;
    }
    Navigator.of(context).pop(
      RecipeSection(
        name: name,
        steps: _steps,
        techniques: _techniques,
        notes: _notesController.text.trim(),
      ),
    );
  }
}

/// Edits one step: role, optional paint and optional note.
class _StepEditorDialog extends StatefulWidget {
  const _StepEditorDialog({this.initial});

  final RecipeStep? initial;

  @override
  State<_StepEditorDialog> createState() => _StepEditorDialogState();
}

class _StepEditorDialogState extends State<_StepEditorDialog> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  String? _paintId;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.initial?.title ?? '');
    _noteController = TextEditingController(text: widget.initial?.note ?? '');
    _paintId = widget.initial?.paintId;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = context.read<CatalogRepository>();
    final paint = _paintId == null ? null : catalog.byId(_paintId!);

    return AlertDialog(
      title: Text(
        widget.initial == null ? l10n.recipeAddStep : l10n.recipeEditStep,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            autofocus: widget.initial == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.stepTitleLabel,
              hintText: l10n.stepTitleHint,
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: paint == null
                ? const Icon(Icons.palette_outlined)
                : PaintSwatch(paint: paint, size: 32),
            title: Text(paint?.name ?? l10n.stepChoosePaint),
            trailing: paint == null
                ? const Icon(Icons.chevron_right)
                : IconButton(
                    tooltip: l10n.stepClearPaint,
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(() => _paintId = null),
                  ),
            onTap: () async {
              final selection = await Navigator.of(context).push<Set<String>>(
                MaterialPageRoute(
                  builder: (_) => RecipePaintPickerScreen(
                    initialSelection: _paintId == null ? const {} : {_paintId!},
                    single: true,
                  ),
                ),
              );
              if (selection == null) return;
              setState(
                () => _paintId = selection.isEmpty ? null : selection.first,
              );
            },
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _noteController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.stepNoteLabel,
              hintText: l10n.stepNoteHint,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.actionCancel),
        ),
        FilledButton(
          onPressed: () {
            final title = _titleController.text.trim();
            if (title.isEmpty && _paintId == null) {
              // A step must at least say what happens or with which paint.
              return;
            }
            Navigator.of(context).pop(
              RecipeStep(
                title: title,
                paintId: _paintId,
                note: _noteController.text.trim(),
              ),
            );
          },
          child: Text(l10n.actionSave),
        ),
      ],
    );
  }
}
