import 'package:flutter/material.dart' hide Paint;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/barcode_repository.dart';
import '../../data/catalog_repository.dart';
import '../../state/inventory_provider.dart';
import '../../state/scan_session.dart';
import '../../widgets/paint_widgets.dart';
import '../recipes/recipe_paint_picker_screen.dart';

/// Continuous barcode scanning: hold pots up to the camera one after
/// another and they land on the shelf as fast as they are recognised.
///
/// The screen never blocks on an unknown code — interrupting a shelf sweep
/// with a picker would turn "scan everything" back into "stop for every
/// pot", which is the friction this exists to remove. Unknowns queue below
/// the camera and get identified whenever the user chooses; each one taught
/// stores the mapping for every future user (see BarcodeRepository).
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  late final ScanSession _session = ScanSession(
    barcodes: context.read<BarcodeRepository>(),
    catalog: context.read<CatalogRepository>(),
    inventory: context.read<InventoryProvider>(),
  );

  /// Only true EAN shapes reach the session: the camera also reads QR codes
  /// and whatever else crosses the frame, and none of that is a pot.
  static final _eanShape = RegExp(r'^[0-9]{8,14}$');

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && _eanShape.hasMatch(value)) {
        _session.handle(value);
      }
    }
  }

  Future<void> _identify(String ean) async {
    final catalog = context.read<CatalogRepository>();
    final selection = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) => const RecipePaintPickerScreen(
          initialSelection: {},
          single: true,
        ),
      ),
    );
    final paintId = selection?.singleOrNull;
    final paint = paintId == null ? null : catalog.byId(paintId);
    if (paint == null) return;
    await _session.teach(ean, paint);
  }

  String _statusLine(AppLocalizations l10n) {
    final name = _session.lastPaint?.name ?? '';
    return switch (_session.lastOutcome) {
      null => l10n.scanHint,
      ScanOutcome.addedNew => l10n.scanStatusAdded(name),
      ScanOutcome.alreadyOwned => l10n.scanStatusOwned(name),
      ScanOutcome.unknownQueued => l10n.scanStatusUnknown,
      ScanOutcome.staleMapping => l10n.scanStatusStale,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalog = context.read<CatalogRepository>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.scanTitle)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _session,
          builder: (context, _) => Column(
            children: [
              SizedBox(
                height: 280,
                child: MobileScanner(onDetect: _onDetect),
              ),
              // One line of live feedback, not a snackbar per pot: at one
              // scan a second, stacked snackbars would bury the camera.
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Text(
                  _statusLine(l10n),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (_session.unknown.isNotEmpty) ...[
                      _SectionHeader(
                        title:
                            l10n.scanUnknownSection(_session.unknown.length),
                      ),
                      for (final ean in _session.unknown)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.help_outline),
                          title: Text(ean),
                          trailing: FilledButton.tonal(
                            onPressed: () => _identify(ean),
                            child: Text(l10n.scanIdentify),
                          ),
                        ),
                    ],
                    if (_session.added.isNotEmpty) ...[
                      _SectionHeader(
                        title: l10n.scanAddedSection(_session.added.length),
                      ),
                      for (final paint in _session.added.reversed)
                        PaintTile(paint: paint, showStatus: false),
                    ],
                    if (_session.alreadyOwned.isNotEmpty) ...[
                      _SectionHeader(title: l10n.scanOwnedSection),
                      for (final paint in _session.alreadyOwned.reversed)
                        PaintTile(paint: paint, showStatus: false),
                    ],
                    // The mapping grows one taught pot at a time, so early
                    // sessions will be mostly unknowns. Saying so up front
                    // reframes "it doesn't know my pots" as "I am building
                    // this" — which is the truth.
                    if (_session.lastOutcome == null)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          l10n.scanEmptyBody(catalog.paints.length),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
