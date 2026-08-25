import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:flutter/material.dart' hide Paint;
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/catalog_repository.dart';
import '../../services/paint_matcher.dart';
import '../../services/photo_eyedropper.dart';
import '../../state/inventory_provider.dart';
import '../../widgets/hsv_color_picker.dart';
import '../../widgets/paint_detail_sheet.dart';
import '../../widgets/paint_widgets.dart';
import '../recipes/quick_recipe_screen.dart';
import '../recipes/recipe_photo_picker.dart';
import 'paints_screen.dart';

/// compute() needs a top-level target; decoding a camera-sized photo on the
/// UI thread visibly freezes the app everywhere but web (where there is no
/// choice).
img.Image? _decodeInIsolate(Uint8List bytes) => decodeForSampling(bytes);

/// "I need THIS colour — what gets me there?"
///
/// The other half of the colour-matching engine: equivalences answer "the
/// recipe says brand X, I own brand Y", this answers "no recipe, just a
/// colour in my head". Same CIEDE2000 underneath, same honesty rule — when
/// nothing is truly close, it says so instead of dressing up a bad match.
class ColorSearchScreen extends StatefulWidget {
  const ColorSearchScreen({super.key});

  @override
  State<ColorSearchScreen> createState() => _ColorSearchScreenState();
}

class _ColorSearchScreenState extends State<ColorSearchScreen> {
  /// Held as HSV, not RGB: converting back and forth collapses the hue for
  /// low-saturation picks and the hue thumb would snap to red.
  var _color = const HSVColor.fromAHSV(1, 205, 0.55, 0.65);

  PaintScope? _scope;

  /// A photo to sample from, replacing the HSV picker while present. This
  /// is the question behind most colour searches — "what colour is THIS?"
  /// — asked of a mini seen online or a part in a box, not of a colour
  /// wheel in someone's head.
  Uint8List? _photoBytes;
  img.Image? _decodedPhoto;

  /// Colours collected for a recipe draft. The bridge from "what colour is
  /// this" to "how do I paint this": sample the mini's key tones, then one
  /// tap turns them into a quick-recipe draft of matching paints.
  final _palette = <Color>[];

  Future<void> _pickPhoto() async {
    final bytes = await pickPhotoBytes(context);
    if (bytes == null) return;
    final decoded = kIsWeb
        ? _decodeInIsolate(bytes)
        : await compute(_decodeInIsolate, bytes);
    if (decoded == null || !mounted) return;
    setState(() {
      _photoBytes = bytes;
      _decodedPhoto = decoded;
    });
  }

  void _createRecipeFromPalette() {
    final l10n = AppLocalizations.of(context);
    final catalog = context.read<CatalogRepository>();
    final owned = context.read<InventoryProvider>().entries;
    final candidates = _scope == PaintScope.mine
        ? catalog.paints.where((p) => owned.containsKey(p.id))
        : catalog.paints;

    final paints = paintsForPalette(candidates, _palette);
    if (paints.isEmpty) {
      // Every sampled colour was too far from anything in scope — an empty
      // draft would just look broken.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.colorSearchPaletteNoMatch)),
      );
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QuickRecipeScreen(
          initialPaintIds: [for (final paint in paints) paint.id],
        ),
      ),
    );
  }

  void _sample(Offset position, Size viewport) {
    final sampled = sampleColorAt(
      _decodedPhoto!,
      viewport: viewport,
      position: position,
    );
    if (sampled == null) return;
    setState(() => _color = HSVColor.fromColor(sampled));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = context.read<CatalogRepository>();
    final inventory = context.watch<InventoryProvider>();
    final owned = inventory.entries;

    // Same latching rule as the catalogue: default to the shelf when there
    // is one — "what do I already own in this colour" is the money
    // question — and to the full catalogue when the shelf is empty.
    _scope ??= owned.isEmpty ? PaintScope.all : PaintScope.mine;
    final scope = _scope!;

    final candidates = scope == PaintScope.mine
        ? catalog.paints.where((p) => owned.containsKey(p.id))
        : catalog.paints;
    final matches = closestToColor(candidates, _color.toColor());
    final anyClose = matches.any((m) => m.tier != null);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.colorSearchTitle),
        actions: [
          IconButton(
            tooltip: l10n.colorSearchFromPhoto,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _pickPhoto,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _decodedPhoto == null
                  ? HsvColorPicker(
                      color: _color,
                      onChanged: (value) => setState(() => _color = value),
                    )
                  : _PhotoSampler(
                      bytes: _photoBytes!,
                      sampledColor: _color.toColor(),
                      onSample: _sample,
                      onClose: () => setState(() {
                        _photoBytes = null;
                        _decodedPhoto = null;
                      }),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _color.toColor(),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        width: 2,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.colorSearchAddColor,
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: () =>
                        setState(() => _palette.add(_color.toColor())),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: SegmentedButton<PaintScope>(
                      segments: [
                        ButtonSegment(
                          value: PaintScope.mine,
                          label: Text(l10n.paintsScopeMine),
                        ),
                        ButtonSegment(
                          value: PaintScope.all,
                          label: Text(l10n.paintsScopeAll),
                        ),
                      ],
                      selected: {scope},
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onSelectionChanged: (s) =>
                          setState(() => _scope = s.first),
                    ),
                  ),
                ],
              ),
            ),
            // The collected palette: sampled tones on their way to becoming
            // a recipe draft. Tapping a dot removes it — no dialog for an
            // action this cheap to redo.
            if (_palette.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (var i = 0; i < _palette.length; i++)
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _palette.removeAt(i)),
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: _palette[i],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _createRecipeFromPalette,
                      icon: const Icon(Icons.auto_stories_outlined, size: 18),
                      label: Text(
                        l10n.colorSearchCreateRecipe(_palette.length),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.colorSearchEmpty,
                        textAlign: TextAlign.center,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: [
                        // When nothing lands inside the honest tiers, say
                        // so up front — the list below is "least far", not
                        // "close".
                        if (!anyClose)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                            child: Text(
                              l10n.colorSearchNothingClose,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        for (final match in matches)
                          _MatchRow(match: match),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The picked photo as a tap-to-sample surface.
///
/// Tap or drag reads the pixel under the finger and feeds it to the colour
/// search — "what colour is THIS bit of the mini". While the finger is
/// down, a circular loupe magnifies the pixels around it, floating above
/// the fingertip so the hand never hides what it is picking — a finger
/// covers dozens of pixels, and without magnification sampling a specific
/// highlight is a lottery. Letterbox bars around the photo stay dead:
/// sampling the background would answer with a colour the photo does not
/// contain.
class _PhotoSampler extends StatefulWidget {
  const _PhotoSampler({
    required this.bytes,
    required this.sampledColor,
    required this.onSample,
    required this.onClose,
  });

  final Uint8List bytes;

  /// The colour currently under the finger; painted as the loupe's ring so
  /// the answer is visible in the same glance as the question.
  final Color sampledColor;

  final void Function(Offset position, Size viewport) onSample;
  final VoidCallback onClose;

  @override
  State<_PhotoSampler> createState() => _PhotoSamplerState();
}

class _PhotoSamplerState extends State<_PhotoSampler> {
  static const _height = 220.0;
  static const _loupeSize = 88.0;

  /// How far the loupe floats above the fingertip.
  static const _loupeLift = 24.0;

  Offset? _touch;

  void _move(Offset position, Size viewport) {
    setState(() => _touch = position);
    widget.onSample(position, viewport);
  }

  void _end() => setState(() => _touch = null);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, _height);
        return Stack(
          // The loupe rides ABOVE the finger, which near the top edge means
          // above the photo itself — clipping it there would blind the
          // picker exactly where precision matters.
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onPanDown: (d) => _move(d.localPosition, viewport),
              onPanUpdate: (d) => _move(d.localPosition, viewport),
              onPanEnd: (_) => _end(),
              onPanCancel: _end,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: viewport.width,
                  height: viewport.height,
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: Image.memory(widget.bytes, fit: BoxFit.contain),
                ),
              ),
            ),
            if (_touch != null)
              Positioned(
                left: _touch!.dx - _loupeSize / 2,
                top: _touch!.dy - _loupeSize - _loupeLift,
                child: IgnorePointer(
                  child: RawMagnifier(
                    size: const Size(_loupeSize, _loupeSize),
                    magnificationScale: 6,
                    // The magnifier sits above the finger, so the focal
                    // point shifts back DOWN by the same distance to keep
                    // magnifying what is actually being touched.
                    focalPointOffset:
                        const Offset(0, _loupeSize / 2 + _loupeLift),
                    decoration: MagnifierDecoration(
                      shape: CircleBorder(
                        side: BorderSide(color: widget.sampledColor, width: 4),
                      ),
                      shadows: const [
                        BoxShadow(blurRadius: 8, color: Colors.black38),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filledTonal(
                tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onClose,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MatchRow extends StatelessWidget {
  const _MatchRow({required this.match});

  final ColorMatch match;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (label, background) = switch (match.tier) {
      MatchTier.twin => (l10n.equivalentsTierTwin, scheme.primaryContainer),
      MatchTier.close =>
        (l10n.equivalentsTierClose, scheme.secondaryContainer),
      MatchTier.approximate =>
        (l10n.equivalentsTierApprox, scheme.surfaceContainerHighest),
      null => (null, null),
    };

    return PaintTile(
      paint: match.paint,
      onTap: () => showPaintDetail(context, match.paint),
      trailing: label == null
          ? null
          : Chip(
              label: Text(label),
              backgroundColor: background,
              visualDensity: VisualDensity.compact,
              labelStyle: Theme.of(context).textTheme.labelSmall,
            ),
    );
  }
}
