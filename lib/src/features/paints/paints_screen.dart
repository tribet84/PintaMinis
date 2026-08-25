import 'package:flutter/material.dart' hide Paint;
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/catalog_repository.dart';
import '../../models/inventory_entry.dart';
import '../../models/paint.dart';
import '../../services/app_settings.dart';
import '../../services/paint_matcher.dart';
import '../../state/inventory_provider.dart';
import '../../widgets/paint_widgets.dart';
import '../../widgets/brand_loader.dart';
import '../../widgets/shelf_starter.dart';
import '../../widgets/paint_detail_sheet.dart';
import 'barcode_scan_screen.dart';
import 'color_search_screen.dart';
import 'twins_screen.dart';

/// Which slice of the catalogue is on screen.
enum PaintScope { mine, all }

/// The single place paints live.
///
/// "Catalogue" and "My paints" used to be separate tabs, which forced the
/// user to decide WHERE to go for one task — find a paint. They were never
/// two things: one is the other with a filter applied, and the duplication
/// showed (both had grown the same brand filter). Merging them also frees a
/// navigation slot.
///
/// The scope defaults to Mine once the user owns anything, because that is
/// the smaller, more relevant list; an empty shelf opens on All, since Mine
/// would be a blank screen.
class PaintsScreen extends StatefulWidget {
  const PaintsScreen({super.key});

  @override
  State<PaintsScreen> createState() => _PaintsScreenState();
}

class _PaintsScreenState extends State<PaintsScreen> {
  var _starterDismissed = false;
  final _searchController = TextEditingController();
  PaintBrand? _brandFilter;
  String? _rangeFilter;
  PaintScope? _scope;
  var _selecting = false;
  final _selection = <String>{};

  /// Twin count memo — O(owned²) colour distances is cheap once, not on
  /// every rebuild a status toggle triggers.
  Set<String>? _twinsForOwned;
  var _twinCount = 0;

  int _countTwins(CatalogRepository catalog, Set<String> ownedIds) {
    if (_twinsForOwned == null ||
        !_twinsForOwned!.containsAll(ownedIds) ||
        _twinsForOwned!.length != ownedIds.length) {
      _twinsForOwned = Set.of(ownedIds);
      _twinCount = ownedTwins(catalog, ownedIds).length;
    }
    return _twinCount;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _exitSelection() {
    setState(() {
      _selecting = false;
      _selection.clear();
    });
  }

  Future<void> _applyToSelection(PaintStatus? status) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final inventory = context.read<InventoryProvider>();
    final ids = List.of(_selection);
    if (ids.isEmpty) return;

    // One batched write, not one per paint: a 40-paint selection was 40
    // round trips and 40 billed operations.
    if (status == null) {
      await inventory.removeAll(ids);
    } else {
      await inventory.setStatusForAll(ids, status);
    }
    _exitSelection();
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(l10n.paintsBulkApplied(ids.length))),
      );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = context.read<CatalogRepository>();
    final inventory = context.watch<InventoryProvider>();

    final owned = inventory.entries;
    // The default scope is derived from the shelf, so it cannot be chosen
    // until the shelf is known: guessing from an unloaded inventory lands
    // everyone on "All" and then visibly snaps to "Mine" a moment later.
    if (!inventory.loaded) {
      return const Center(child: BrandLoader());
    }
    // A brand-new shelf gets the guided starter instead of a 640-paint
    // catalogue: of the first eight sign-ups, five left without marking a
    // single pot. Skipping it is remembered on the device: re-offering on
    // every visit turned "I'd rather browse on my own" into a question the
    // user had to answer again and again. Completing it only hides it for
    // the session — if the shelf is ever emptied, the same problem deserves
    // the same offer.
    if (owned.isEmpty &&
        !_starterDismissed &&
        !context.watch<AppSettings>().shelfStarterDismissed) {
      return ShelfStarter(
        onDone: () => setState(() => _starterDismissed = true),
        onSkip: () => context.read<AppSettings>().dismissShelfStarter(),
      );
    }
    // The first loaded build LATCHES the default; after that only the user
    // changes it. The previous `??` recomputed the default on every build,
    // so marking your first paint flipped the toggle from All to Mine under
    // your fingers mid-browse. Latching after the starter's early return
    // also means completing the starter lands you on Mine — your new shelf —
    // while skipping it lands you on All.
    _scope ??= owned.isEmpty ? PaintScope.all : PaintScope.mine;
    final scope = _scope!;


    // Everything the current search + scope allows within the brand, BEFORE
    // the range narrows it. The range chips are built from this same list, so
    // a chip can never offer a subcategory the current search has emptied.
    var brandResults =
        catalog.search(_searchController.text, brand: _brandFilter);
    if (scope == PaintScope.mine) {
      brandResults =
          brandResults.where((p) => owned.containsKey(p.id)).toList();
    }

    // Count what the user can actually SEE. Raw inventory entries can include
    // ids that are no longer in the bundled catalogue, and counting those
    // made the toggle claim more paints than the list ever showed.
    final mineCount =
        catalog.paints.where((p) => owned.containsKey(p.id)).length;

    // Brand chips offer every brand in scope — filtering to a brand you own
    // nothing from would be a dead end.
    final brandNames = <PaintBrand, String>{
      for (final paint in scope == PaintScope.mine
          ? catalog.paints.where((p) => owned.containsKey(p.id))
          : catalog.paints)
        paint.brand: paint.brandName,
    };
    if (_brandFilter != null && !brandNames.containsKey(_brandFilter)) {
      _brandFilter = null;
      _rangeFilter = null;
    }

    // Range chips only exist once a brand is picked: range names collide
    // across brands (several have a wash range), and a flat list of every
    // range in the catalogue would be longer than the brand row it refines.
    // Built from brandResults — search and scope already applied — so every
    // chip is guaranteed to have something behind it. When the query empties
    // the selected range, its chip vanishes and the guard below resets the
    // filter instead of stranding the user on an inexplicably empty list.
    final ranges = <String>{
      if (_brandFilter != null)
        for (final paint in brandResults) paint.range,
    };
    if (_rangeFilter != null && !ranges.contains(_rangeFilter)) {
      _rangeFilter = null;
    }

    final results = _rangeFilter == null
        ? brandResults
        : brandResults.where((p) => p.range == _rangeFilter).toList();

    return SafeArea(
      child: Column(
        children: [
          if (_selecting)
            _SelectionToolbar(
              count: _selection.length,
              onCancel: _exitSelection,
              onSelectAllVisible: () => setState(
                () => _selection.addAll(results.map((p) => p.id)),
              ),
              onApply: _applyToSelection,
            )
          else
            _FilterHeader(
              searchController: _searchController,
              scope: scope,
              mineCount: mineCount,
              twinCount: _countTwins(catalog, owned.keys.toSet()),
              brandNames: brandNames,
              brandFilter: _brandFilter,
              ranges: ranges,
              rangeFilter: _rangeFilter,
              resultCount: results.length,
              onSearchChanged: () => setState(() {}),
              onScopeChanged: (value) => setState(() => _scope = value),
              onBrandChanged: (value) => setState(() {
                // A range belongs to its brand; keeping it across a brand
                // switch would silently show an empty list.
                if (value != _brandFilter) _rangeFilter = null;
                _brandFilter = value;
              }),
              onRangeChanged: (value) => setState(() => _rangeFilter = value),
              onStartSelecting: () => setState(() => _selecting = true),
            ),
          // The row's tap target is invisible: the toggles soak up all the
          // visual attention, and nothing suggests the row itself opens the
          // paint card with its cross-brand matches. Said once, then gone
          // for good on this device.
          if (!_selecting &&
              !context.watch<AppSettings>().paintCardHintDismissed)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    const Icon(Icons.touch_app_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        l10n.paintsTapHint,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.actionClose,
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () =>
                          context.read<AppSettings>().dismissPaintCardHint(),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _PaintResults(
              results: results,
              ownedStatus: owned,
              scope: scope,
              selecting: _selecting,
              selection: _selection,
              onToggle: (id) => setState(
                () => _selection.contains(id)
                    ? _selection.remove(id)
                    : _selection.add(id),
              ),
              emptyMessage: scope == PaintScope.mine
                  ? (owned.isEmpty
                      ? l10n.inventoryEmptyBody
                      : l10n.paintsMineEmptyFiltered)
                  : l10n.paintsAllEmptyFiltered,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterHeader extends StatelessWidget {
  const _FilterHeader({
    required this.searchController,
    required this.scope,
    required this.mineCount,
    required this.twinCount,
    required this.brandNames,
    required this.brandFilter,
    required this.ranges,
    required this.rangeFilter,
    required this.resultCount,
    required this.onSearchChanged,
    required this.onScopeChanged,
    required this.onBrandChanged,
    required this.onRangeChanged,
    required this.onStartSelecting,
  });

  final TextEditingController searchController;
  final PaintScope scope;
  final int mineCount;

  /// Colour duplicates on the shelf; the entry hides at zero.
  final int twinCount;
  final Map<PaintBrand, String> brandNames;
  final PaintBrand? brandFilter;

  /// Ranges of the selected brand (empty when no brand is selected).
  final Set<String> ranges;
  final String? rangeFilter;

  final int resultCount;
  final VoidCallback onSearchChanged;
  final ValueChanged<PaintScope> onScopeChanged;
  final ValueChanged<PaintBrand?> onBrandChanged;
  final ValueChanged<String?> onRangeChanged;
  final VoidCallback onStartSelecting;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: l10n.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: searchController.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              searchController.clear();
                              onSearchChanged();
                            },
                          ),
                  ),
                  onChanged: (_) => onSearchChanged(),
                ),
              ),
              // Text finds a paint you can name; the eyedropper finds one
              // you can only picture. Side by side because they are the
              // same question asked two ways.
              IconButton(
                tooltip: l10n.colorSearchTooltip,
                icon: const Icon(Icons.colorize),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ColorSearchScreen(),
                  ),
                ),
              ),
              // And the scanner finds the pot in your HAND — the third way
              // of asking, with the least typing of all.
              IconButton(
                tooltip: l10n.scanTooltip,
                icon: const Icon(Icons.qr_code_scanner),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const BarcodeScanScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Scope and brand share one row: both narrow the same list, so they
        // belong at the same level. The scope stays pinned while the brands
        // scroll — it is the primary control and must never scroll away.
        SizedBox(
          height: 48,
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12, right: 4),
                child: SegmentedButton<PaintScope>(
                  segments: [
                    ButtonSegment(
                      value: PaintScope.mine,
                      label: Text('${l10n.paintsScopeMine} $mineCount'),
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
                  onSelectionChanged: (s) => onScopeChanged(s.first),
                ),
              ),
              if (brandNames.length > 1)
                Expanded(
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
                    children: [
                      FilterChip(
                        label: Text(l10n.filterAllBrands),
                        selected: brandFilter == null,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => onBrandChanged(null),
                      ),
                      for (final entry in brandNames.entries) ...[
                        const SizedBox(width: 6),
                        FilterChip(
                          label: Text(entry.value),
                          selected: brandFilter == entry.key,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => onBrandChanged(
                            brandFilter == entry.key ? null : entry.key,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        // The selected brand's ranges, one level below the brand row. A
        // single-range brand gets no row — the chip could never narrow
        // anything.
        if (ranges.length > 1)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              children: [
                FilterChip(
                  label: Text(l10n.filterAllRanges),
                  selected: rangeFilter == null,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => onRangeChanged(null),
                ),
                for (final range in ranges) ...[
                  const SizedBox(width: 6),
                  FilterChip(
                    label: Text(range),
                    selected: rangeFilter == range,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onRangeChanged(
                      rangeFilter == range ? null : range,
                    ),
                  ),
                ],
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.resultsCount(resultCount),
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              // Only exists when there IS something to show: an entry that
              // usually says "0 duplicates" would train eyes to skip it.
              if (twinCount > 0 && scope == PaintScope.mine)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TwinsScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.join_full_outlined, size: 18),
                  label: Text(l10n.twinsFound(twinCount)),
                ),
              TextButton.icon(
                onPressed: resultCount == 0 ? null : onStartSelecting,
                icon: const Icon(Icons.checklist, size: 18),
                label: Text(l10n.paintsSelect),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Replaces the filters while selecting, so the actions sit where the user is
/// already looking instead of behind a menu.
class _SelectionToolbar extends StatelessWidget {
  const _SelectionToolbar({
    required this.count,
    required this.onCancel,
    required this.onSelectAllVisible,
    required this.onApply,
  });

  final int count;
  final VoidCallback onCancel;
  final VoidCallback onSelectAllVisible;
  final ValueChanged<PaintStatus?> onApply;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final enabled = count > 0;

    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: l10n.paintsSelectionCancel,
                icon: const Icon(Icons.close),
                onPressed: onCancel,
              ),
              Expanded(
                child: Text(
                  l10n.paintsSelectionCount(count),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TextButton(
                onPressed: onSelectAllVisible,
                child: Text(l10n.paintsSelectAllVisible),
              ),
            ],
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              children: [
                // Short status words, not the full sentences used in the
                // single-paint sheet: four long labels do not fit a phone,
                // and the toolbar has already established that these apply
                // to the selection.
                ActionChip(
                  avatar: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(l10n.statusInStock),
                  onPressed: enabled ? () => onApply(PaintStatus.inStock) : null,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.hourglass_bottom, size: 18),
                  label: Text(l10n.statusLow),
                  onPressed: enabled ? () => onApply(PaintStatus.low) : null,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.add_shopping_cart, size: 18),
                  label: Text(l10n.statusWishlist),
                  onPressed:
                      enabled ? () => onApply(PaintStatus.wishlist) : null,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.delete_outline, size: 18),
                  label: Text(l10n.actionDelete),
                  onPressed: enabled ? () => onApply(null) : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaintResults extends StatelessWidget {
  const _PaintResults({
    required this.results,
    required this.ownedStatus,
    required this.scope,
    required this.selecting,
    required this.selection,
    required this.onToggle,
    required this.emptyMessage,
  });

  final List<Paint> results;

  /// Current status per paint, so the Mine scope can hide the status that is
  /// implied and surface only the exceptions.
  final Map<String, InventoryEntry> ownedStatus;

  final PaintScope scope;
  final bool selecting;
  final Set<String> selection;
  final ValueChanged<String> onToggle;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          emptyMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    // Mine is short enough to group by brand, which makes a shelf easy to
    // audit. All is 400+ rows, where headers would just add scrolling.
    if (scope == PaintScope.mine && !selecting) {
      final byBrand = <String, List<Paint>>{};
      for (final paint in results) {
        byBrand.putIfAbsent(paint.brandName, () => []).add(paint);
      }
      final brands = byBrand.keys.toList()..sort();
      return ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          for (final brand in brands) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
              child: Text(
                brand,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            for (final paint in byBrand[brand]!)
              _row(context, paint, showBrand: false),
          ],
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: results.length,
      itemBuilder: (context, index) => _row(context, results[index]),
    );
  }

  Widget _row(BuildContext context, Paint paint, {bool showBrand = true}) {
    if (!selecting) {
      return PaintTile(
        paint: paint,
        showBrand: showBrand,
        onTap: () => showPaintDetail(context, paint),
      );
    }
    final checked = selection.contains(paint.id);
    return CheckboxListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      value: checked,
      secondary: PaintSwatch(paint: paint, size: 36),
      title: Text(paint.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (showBrand) paint.brandName,
          paint.range,
          if (paint.code != null) paint.code!,
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      ),
      onChanged: (_) => onToggle(paint.id),
    );
  }
}
