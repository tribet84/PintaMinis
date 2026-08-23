import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/src/data/catalog_repository.dart';
import 'package:paintforge/src/models/paint.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CatalogRepository repository;

  setUpAll(() async {
    repository = await CatalogRepository.loadFromAssets();
  });

  test('loads all four brands from assets', () {
    final brands = repository.paints.map((p) => p.brand).toSet();
    expect(brands, PaintBrand.values.toSet());
    expect(repository.paints.length, greaterThan(200));
  });

  test('paint ids are unique', () {
    final ids = repository.paints.map((p) => p.id).toSet();
    expect(ids.length, repository.paints.length);
  });

  test('search finds paints by name regardless of case', () {
    final results = repository.search('abaddon');
    // Base and Air both carry an Abaddon Black — the point here is the
    // case-insensitive match, not the exact count.
    expect(results, isNotEmpty);
    expect(results.every((p) => p.name == 'Abaddon Black'), isTrue);
    expect(results.every((p) => p.brand == PaintBrand.citadel), isTrue);
  });

  test('search finds Vallejo paints by code', () {
    final results = repository.search('70.950');
    expect(results, hasLength(1));
    expect(results.single.name, 'Black');
    expect(results.single.brand, PaintBrand.vallejo);
  });

  test('range filter narrows a brand to one of its ranges', () {
    final all = repository.search('', brand: PaintBrand.vallejo);
    final washes = repository.search(
      '',
      brand: PaintBrand.vallejo,
      range: 'Game Color Wash',
    );
    // The catalogue grows over time, so assert the filtering behaviour
    // rather than a paint count that changes with every addition.
    expect(washes, isNotEmpty);
    expect(washes.every((p) => p.range == 'Game Color Wash'), isTrue);
    expect(washes.length, lessThan(all.length));
  });

  test('brand filter restricts results', () {
    final results = repository.search('black', brand: PaintBrand.armyPainter);
    expect(results, isNotEmpty);
    expect(results.every((p) => p.brand == PaintBrand.armyPainter), isTrue);
  });

  test('empty query returns the whole brand catalog', () {
    final citadel = repository.search('', brand: PaintBrand.citadel);
    expect(citadel.length, greaterThan(50));
  });

  test('ranges come out in curated order, workhorse ranges first', () {
    // Alphabetical range order opened the catalogue on Citadel "Air" — a
    // newcomer's first screen was forty-six airbrush paints. The JSON's
    // rangeOrder is the display contract; first seen must be Base.
    final citadel = repository.search('', brand: PaintBrand.citadel);
    expect(citadel.first.range, 'Base');

    final seen = <String>[];
    for (final paint in citadel) {
      if (seen.isEmpty || seen.last != paint.range) seen.add(paint.range);
    }
    expect(seen, ['Base', 'Layer', 'Shade', 'Contrast', 'Dry', 'Technical', 'Air'],
        reason: 'each range appears once, in curated order — no interleaving');

    final vallejo = repository.search('', brand: PaintBrand.vallejo);
    expect(vallejo.first.range, 'Model Color');
  });

  test('AK Interactive loads with its mini-first curated order', () {
    final ak = repository.search('', brand: PaintBrand.ak);
    expect(ak.length, 480);
    // Miniature ranges lead; the scale-model camo ranges (Air, AFV) close.
    expect(ak.first.range, '3Gen Standard');
    expect(ak.last.range, '3Gen AFV');

    final white = repository.byId('ak-ak11001-white');
    expect(white, isNotNull);
    expect(white!.name, 'White');
    expect(white.code, 'AK11001');
    expect(white.color, isNotNull);
  });

  test('byId resolves a known paint with parsed color', () {
    final paint = repository.byId('citadel-mephiston-red');
    expect(paint, isNotNull);
    expect(paint!.name, 'Mephiston Red');
    expect(paint.color?.toARGB32(), 0xFF9A1115);
  });

  test('a paint whose colour nobody has recorded parses with a null colour',
      () {
    // The catalogue lists names we can verify from the manufacturer long
    // before anyone measures the pot. Those must load, and must not be given
    // an invented colour on the way in.
    final paint = Paint.fromJson(
      const {'id': 'x-1', 'name': 'Unknown', 'range': 'Test'},
      brand: PaintBrand.citadel,
      brandName: 'Citadel',
    );

    expect(paint.color, isNull);
  });
}
