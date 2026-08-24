import 'package:flutter/material.dart' hide Paint;
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/catalog_repository.dart';
import '../../services/paint_matcher.dart';
import '../../state/inventory_provider.dart';
import '../../widgets/hsv_color_picker.dart';
import '../../widgets/paint_detail_sheet.dart';
import '../../widgets/paint_widgets.dart';
import 'paints_screen.dart';

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
      appBar: AppBar(title: Text(l10n.colorSearchTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: HsvColorPicker(
                color: _color,
                onChanged: (value) => setState(() => _color = value),
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
                  const SizedBox(width: 12),
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
