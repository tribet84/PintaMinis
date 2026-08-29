import 'dart:async';

import 'package:flutter/material.dart' hide Paint;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../../../l10n/generated/app_localizations.dart';
import '../../data/barcode_repository.dart';
import '../../data/catalog_repository.dart';
import '../../services/barcode_validation.dart';
import '../../services/camera_control.dart';
import '../../state/inventory_provider.dart';
import '../../state/scan_gate.dart';
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

  /// `autoZoom` and `tapToFocus` are deliberately NOT set here.
  ///
  /// On web this package's `setZoomScale` throws `UnsupportedError` and its
  /// `setFocusPoint` throws `UnimplementedError`, so both flags are inert —
  /// setting them only reads as if the camera were being driven when it is
  /// not. The zoom that actually reaches the hardware is applied through
  /// [camera_control], straight onto the underlying media track.
  late final _controller = MobileScannerController(
    // Narrowed to the two formats a paint pot actually carries. Beyond
    // saving the decoder from scanning every frame for QR, DataMatrix and
    // PDF417, this removes a real source of wrong readings: EAN-8 and UPC-E
    // are short symbologies, and a partly-visible EAN-13 can satisfy one of
    // them, yielding a confident code that was never on the label. No pot
    // from any brand in this catalogue uses them, so the risk buys nothing.
    formats: const [BarcodeFormat.ean13, BarcodeFormat.upcA],
  );

  /// Nothing reaches the shelf on a single frame's say-so — see [ScanGate].
  final _gate = ScanGate();


  /// What the live camera turned out to support, once it had started.
  CameraCapabilities? _camera;
  double _zoom = 1;
  Timer? _cameraProbe;

  @override
  void initState() {
    super.initState();
    _probeCamera();
  }

  /// The preview needs a moment to negotiate a stream before there is any
  /// track to interrogate, and how long varies by device. Polling briefly
  /// beats a fixed delay picked to look right on one phone.
  void _probeCamera() {
    const interval = Duration(milliseconds: 300);
    var attemptsLeft = 20;

    _cameraProbe = Timer.periodic(interval, (timer) async {
      final capabilities = readCameraCapabilities();
      if (capabilities == null) {
        if (--attemptsLeft <= 0) timer.cancel();
        return;
      }
      timer.cancel();

      // Open already zoomed in. A dropper-bottle barcode is ~25mm wide, so
      // at the closest distance the lens can still focus it lands on too few
      // pixels per bar to decode — and moving closer only defocuses it.
      // Zoom is what breaks that deadlock, and it should not depend on the
      // user finding a slider first.
      final start = capabilities.suggestedZoom;
      if (capabilities.hasZoom) {
        await applyCameraZoom(start);
      }
      if (!mounted) return;
      setState(() {
        _camera = capabilities;
        _zoom = start;
      });
    });
  }

  @override
  void dispose() {
    _cameraProbe?.cancel();
    _session.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Three gates stand between a frame and the shelf, because a wrong pot
  /// added silently is worse than a scan that visibly did not take.
  ///
  ///  1. the code must be a well-formed EAN-13/UPC-A whose check digit
  ///     agrees — this alone rejects most misreads of a curved label;
  ///  2. it must then be seen repeatedly, since roughly one misread in ten
  ///     satisfies a check digit by luck and the camera offers dozens of
  ///     frames per pot;
  ///  3. only then does the session decide what it means.
  void _onDetect(BarcodeCapture capture) {
    final now = DateTime.now();
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      final code = normalizeBarcode(raw);
      if (code == null) continue;

      final confirmed = _gate.offer(code, now);
      if (confirmed != null) _session.handle(confirmed);
    }
  }

  /// Types a code in by hand.
  ///
  /// Some labels will not scan however good the camera handling gets: a bent
  /// dropper bottle, a torn or overprinted barcode. The digits are printed
  /// under every barcode, so there is always a way through — and it goes
  /// through exactly the same validation, so a typo cannot enter either.
  Future<void> _enterManually() async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    var error = false;

    final code = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          void submit() {
            final normalized = normalizeBarcode(controller.text);
            if (normalized == null) {
              setDialogState(() => error = true);
              return;
            }
            Navigator.of(context).pop(normalized);
          }

          return AlertDialog(
            title: Text(l10n.scanManualTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              onChanged: (_) {
                if (error) setDialogState(() => error = false);
              },
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(
                labelText: l10n.scanManualLabel,
                helperText: l10n.scanManualHelp,
                errorText: error ? l10n.scanManualInvalid : null,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.actionCancel),
              ),
              FilledButton(onPressed: submit, child: Text(l10n.scanManualAdd)),
            ],
          );
        },
      ),
    );

    controller.dispose();
    if (code != null) await _session.handle(code);
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
      appBar: AppBar(
        title: Text(l10n.scanTitle),
        actions: [
          // Always available, not a last resort buried behind a failure:
          // some labels never scan, and the digits are printed right there.
          IconButton(
            tooltip: l10n.scanManualEntry,
            icon: const Icon(Icons.keyboard),
            onPressed: _enterManually,
          ),
          // Low light forces a longer exposure, which reads as motion blur
          // on a hand-held pot — the torch is the direct fix for that,
          // distinct from the focus problem tapToFocus solves.
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, child) {
              if (state.torchState == TorchState.unavailable) {
                return const SizedBox.shrink();
              }
              return IconButton(
                tooltip: l10n.scanTorchTooltip,
                icon: Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off,
                ),
                onPressed: _controller.toggleTorch,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: _session,
          builder: (context, _) => Column(
            children: [
              SizedBox(
                height: 320,
                child: MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  tapToFocus: true,
                ),
              ),
              // Most phone cameras have a minimum focus distance a pot held
              // right up to the lens sits well inside — no autofocus
              // setting fixes that, only backing off does. Said once,
              // plainly, instead of a scanner that just seems to not work.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: Text(
                  l10n.scanFocusHint,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ),
              _CameraControls(
                camera: _camera,
                zoom: _zoom,
                onZoomChanged: (value) {
                  setState(() => _zoom = value);
                  applyCameraZoom(value);
                },
                onRefocus: retriggerAutofocus,
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

/// Zoom, refocus, and an honest read-out of what the camera is delivering.
///
/// Renders nothing until the camera has answered, and only shows each control
/// the device actually supports — an inert slider on a laptop webcam would
/// be one more thing that looks like it should help and does not.
class _CameraControls extends StatelessWidget {
  const _CameraControls({
    required this.camera,
    required this.zoom,
    required this.onZoomChanged,
    required this.onRefocus,
  });

  final CameraCapabilities? camera;
  final double zoom;
  final ValueChanged<double> onZoomChanged;
  final Future<bool> Function() onRefocus;

  @override
  Widget build(BuildContext context) {
    final camera = this.camera;
    if (camera == null) return const SizedBox.shrink();

    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (camera.hasZoom)
            Row(
              children: [
                const Icon(Icons.zoom_out, size: 20),
                Expanded(
                  child: Slider(
                    value: zoom.clamp(camera.minZoom, camera.maxZoom),
                    min: camera.minZoom,
                    max: camera.maxZoom,
                    label: '${zoom.toStringAsFixed(1)}x',
                    onChanged: onZoomChanged,
                  ),
                ),
                const Icon(Icons.zoom_in, size: 20),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  child: Text(
                    '${zoom.toStringAsFixed(1)}x',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Continuous autofocus can lock onto the background behind a
              // small pot and never let go. This is the way back.
              TextButton.icon(
                onPressed: () => onRefocus(),
                icon: const Icon(Icons.center_focus_strong, size: 18),
                label: Text(l10n.scanRefocus),
              ),
              // The delivered resolution is the number that decides whether a
              // barcode CAN decode, and it is invisible everywhere else. When
              // a pot still will not read, this is the first thing worth
              // knowing — so it is on screen rather than in a console.
              Text(
                l10n.scanCameraInfo(camera.width, camera.height),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
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
