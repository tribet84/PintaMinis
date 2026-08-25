import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/src/data/barcode_repository.dart';
import 'package:paintforge/src/data/catalog_repository.dart';
import 'package:paintforge/src/models/inventory_entry.dart';
import 'package:paintforge/src/state/inventory_provider.dart';
import 'package:paintforge/src/state/scan_session.dart';

import 'fakes.dart';

class FakeBarcodeRepository implements BarcodeRepository {
  final map = <String, String>{};
  final taught = <String, String>{};

  @override
  Future<String?> lookup(String ean) async => map[ean];

  @override
  Future<void> teach(String ean, String paintId) async {
    // Mirrors the create-only rules: first write wins.
    map.putIfAbsent(ean, () => paintId);
    taught[ean] = paintId;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CatalogRepository catalog;

  setUpAll(() async {
    catalog = await CatalogRepository.loadFromAssets();
  });

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  late FakeBarcodeRepository barcodes;
  late InventoryProvider inventory;
  late ScanSession session;

  setUp(() {
    barcodes = FakeBarcodeRepository();
    inventory = InventoryProvider(repository: FakeInventoryRepository());
    session = ScanSession(
      barcodes: barcodes,
      catalog: catalog,
      inventory: inventory,
    );
    addTearDown(session.dispose);
    addTearDown(inventory.dispose);
  });

  test('a known code puts the pot on the shelf, once', () async {
    barcodes.map['5011921000001'] = 'citadel-mephiston-red';

    final first = await session.handle('5011921000001');
    // The camera fires the same code many times a second while the pot is
    // in frame — every repeat after the first must be a silent no-op.
    final repeat = await session.handle('5011921000001');

    expect(first, ScanOutcome.addedNew);
    expect(repeat, isNull);
    expect(session.added.map((p) => p.id), ['citadel-mephiston-red']);
    await settle();
    expect(
      inventory.statusOf('citadel-mephiston-red'),
      PaintStatus.inStock,
    );
  });

  test('an owned pot is reported, and "running low" is never promoted',
      () async {
    await inventory.setStatus('citadel-mephiston-red', PaintStatus.low);
    await settle();
    barcodes.map['5011921000001'] = 'citadel-mephiston-red';

    final outcome = await session.handle('5011921000001');

    await settle();
    expect(outcome, ScanOutcome.alreadyOwned);
    expect(inventory.statusOf('citadel-mephiston-red'), PaintStatus.low,
        reason: 'a shelf sweep must not refill a pot that is running out');
  });

  test('a wishlist pot being scanned is in hand now — it upgrades',
      () async {
    await inventory.setStatus('citadel-mephiston-red', PaintStatus.wishlist);
    await settle();
    barcodes.map['5011921000001'] = 'citadel-mephiston-red';

    final outcome = await session.handle('5011921000001');

    await settle();
    expect(outcome, ScanOutcome.addedNew);
    expect(inventory.statusOf('citadel-mephiston-red'), PaintStatus.inStock);
  });

  test('an unknown code queues once and teaching resolves it for everyone',
      () async {
    final outcome = await session.handle('8429551000002');
    await session.handle('8429551000002');

    expect(outcome, ScanOutcome.unknownQueued);
    expect(session.unknown, ['8429551000002']);

    final paint = catalog.byId('citadel-abaddon-black')!;
    final taught = await session.teach('8429551000002', paint);

    await settle();
    expect(taught, ScanOutcome.addedNew);
    expect(session.unknown, isEmpty);
    expect(barcodes.taught['8429551000002'], 'citadel-abaddon-black',
        reason: 'the mapping is stored for every future user');
    expect(inventory.statusOf('citadel-abaddon-black'), PaintStatus.inStock);
  });

  test('a mapping to a paint this catalogue lacks is skipped, not guessed',
      () async {
    barcodes.map['4000000000009'] = 'citadel-paint-that-never-existed';

    final outcome = await session.handle('4000000000009');

    expect(outcome, ScanOutcome.staleMapping);
    expect(session.added, isEmpty);
    expect(inventory.entries, isEmpty);
  });
}
