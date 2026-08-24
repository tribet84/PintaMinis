import 'package:flutter/material.dart' hide Paint;
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/catalog_repository.dart';
import '../../services/paint_matcher.dart';
import '../../state/inventory_provider.dart';
import '../../widgets/paint_widgets.dart';

/// Colour duplicates on the user's own shelf.
///
/// Buying advice in reverse: instead of "what should I buy", this answers
/// "what did I buy twice". Each pair is two pots the eye cannot tell apart
/// (deltaE < 2, same finish family) — useful before a shopping trip, and
/// the kind of discovery painters share unprompted.
class TwinsScreen extends StatelessWidget {
  const TwinsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = context.read<CatalogRepository>();
    final owned = context.watch<InventoryProvider>().entries;
    final twins = ownedTwins(catalog, owned.keys.toSet());

    return Scaffold(
      appBar: AppBar(title: Text(l10n.twinsTitle)),
      body: SafeArea(
        child: twins.isEmpty
            ? EmptyState(
                icon: Icons.join_full_outlined,
                title: l10n.twinsEmptyTitle,
                body: l10n.twinsEmptyBody,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: Text(
                      l10n.twinsBody,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  for (final twin in twins)
                    Card(
                      margin: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Column(
                        children: [
                          PaintTile(paint: twin.a, showStatus: false),
                          PaintTile(paint: twin.b, showStatus: false),
                        ],
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
