import 'package:flutter/foundation.dart';

import '../data/barcode_repository.dart';
import '../data/catalog_repository.dart';
import '../models/inventory_entry.dart';
import '../models/paint.dart';
import 'inventory_provider.dart';

/// What one scanned code amounted to — drives the feedback strip.
enum ScanOutcome {
  /// New pot on the shelf (or a wishlist pot now in hand).
  addedNew,

  /// Recognised, and already owned — nothing written, nothing lost.
  alreadyOwned,

  /// Nobody has taught this code yet; parked in [unknown] to identify.
  unknownQueued,

  /// A mapping exists but points at nothing in this catalogue — stale data,
  /// skipped rather than guessed at.
  staleMapping,
}

/// One burst of continuous scanning: the camera keeps running and every
/// code funnels through [handle], so pots go shelf-ward as fast as they can
/// be held up to the lens.
///
/// The session is the unit of feedback, not the single scan: what the user
/// needs while sweeping a shelf is "what have I got so far and what still
/// needs naming", which is exactly [added], [alreadyOwned] and [unknown].
class ScanSession extends ChangeNotifier {
  ScanSession({
    required BarcodeRepository barcodes,
    required CatalogRepository catalog,
    required InventoryProvider inventory,
  })  : _barcodes = barcodes,
        _catalog = catalog,
        _inventory = inventory;

  final BarcodeRepository _barcodes;
  final CatalogRepository _catalog;
  final InventoryProvider _inventory;

  /// Every code this session has already dealt with. The camera fires the
  /// same barcode many times per second while it is in frame; without this
  /// a single pot would "add" dozens of times.
  final _processed = <String>{};

  final added = <Paint>[];
  final alreadyOwned = <Paint>[];

  /// Codes waiting to be taught, oldest first, deduplicated.
  final unknown = <String>[];

  ScanOutcome? lastOutcome;
  Paint? lastPaint;

  /// Feeds one detected code through the session. Returns null for repeats,
  /// which the UI ignores entirely — a pot sitting in frame is one scan,
  /// not a stream of them.
  Future<ScanOutcome?> handle(String ean) async {
    if (!_processed.add(ean)) return null;

    final paintId = await _barcodes.lookup(ean);
    if (paintId == null) {
      unknown.add(ean);
      return _finish(ScanOutcome.unknownQueued, null);
    }

    final paint = _catalog.byId(paintId);
    if (paint == null) {
      // Mapped against a catalogue this build does not carry (removed id,
      // or data from a newer catalogue). Guessing would put the wrong pot
      // on the shelf.
      return _finish(ScanOutcome.staleMapping, null);
    }
    return _addToShelf(paint);
  }

  /// Resolves a queued unknown: stores the mapping for everyone and puts
  /// the pot on this shelf.
  Future<ScanOutcome> teach(String ean, Paint paint) async {
    await _barcodes.teach(ean, paint.id);
    unknown.remove(ean);
    return _addToShelf(paint);
  }

  Future<ScanOutcome> _addToShelf(Paint paint) async {
    final status = _inventory.statusOf(paint.id);
    // Owned pots (in stock or running low) are left exactly as they are —
    // a shelf sweep must never promote "running low" back to full. A
    // wishlist pot being physically scanned IS in hand now, so it upgrades.
    if (status == PaintStatus.inStock || status == PaintStatus.low) {
      alreadyOwned.add(paint);
      return _finish(ScanOutcome.alreadyOwned, paint);
    }
    await _inventory.setStatus(paint.id, PaintStatus.inStock);
    added.add(paint);
    return _finish(ScanOutcome.addedNew, paint);
  }

  ScanOutcome _finish(ScanOutcome outcome, Paint? paint) {
    lastOutcome = outcome;
    lastPaint = paint;
    notifyListeners();
    return outcome;
  }
}
