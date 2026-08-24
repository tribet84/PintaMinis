import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:paintforge/src/data/catalog_repository.dart';
import 'package:paintforge/src/models/inventory_entry.dart';
import 'package:paintforge/src/models/paint_list.dart';
import 'package:paintforge/src/models/recipe.dart';
import 'package:paintforge/src/services/data_export.dart';
import 'package:paintforge/src/services/paint_matcher.dart';
import 'package:paintforge/src/services/photo_eyedropper.dart';
import 'dart:convert';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CatalogRepository catalog;

  setUpAll(() async {
    catalog = await CatalogRepository.loadFromAssets();
  });

  group('ownedTwins', () {
    test('finds the classic cross-brand twin, nearest pair first', () {
      // Vallejo Game Color Black and Army Painter Matt Black are the
      // matcher's canonical twins — owning both is owning one color twice.
      final vallejoBlack =
          catalog.paints.firstWhere((p) => p.code == '72.051');
      // Two Matt Blacks exist (Warpaints and Fanatic); the classic twin is
      // the Warpaints one.
      final mattBlack = catalog.paints.firstWhere(
          (p) => p.name == 'Matt Black' && p.range == 'Warpaints');
      final twins = ownedTwins(catalog, {vallejoBlack.id, mattBlack.id});

      expect(twins, hasLength(1));
      expect(twins.single.deltaE, lessThan(2));
      for (var i = 1; i < twins.length; i++) {
        expect(twins[i].deltaE, greaterThanOrEqualTo(twins[i - 1].deltaE));
      }
    });

    test('a lone paint has no twin, and distinct colors never pair', () {
      expect(ownedTwins(catalog, {'citadel-mephiston-red'}), isEmpty);
      expect(
        ownedTwins(
            catalog, {'citadel-mephiston-red', 'citadel-averland-sunset'}),
        isEmpty,
      );
    });
  });

  group('sampleColorAt', () {
    // A 2x1 image: red left pixel, blue right pixel, drawn contain-fit in
    // a 200x100 viewport (fills it exactly — no letterboxing ambiguity).
    final image = img.Image(width: 2, height: 1)
      ..setPixelRgb(0, 0, 255, 0, 0)
      ..setPixelRgb(1, 0, 0, 0, 255);

    test('maps taps through the contain-fit geometry to the right pixel', () {
      const viewport = Size(200, 100);
      final left = sampleColorAt(image,
          viewport: viewport, position: const Offset(40, 50));
      final right = sampleColorAt(image,
          viewport: viewport, position: const Offset(160, 50));

      expect(left!.toARGB32(), 0xFFFF0000);
      expect(right!.toARGB32(), 0xFF0000FF);
    });

    test('letterbox bars sample nothing', () {
      // Same image in a tall viewport: bars above and below the strip.
      const viewport = Size(200, 400);
      expect(
        sampleColorAt(image, viewport: viewport, position: const Offset(100, 10)),
        isNull,
      );
    });
  });

  group('buildExportJson', () {
    test('denormalises paint ids so the file outlives the catalogue', () {
      final json = buildExportJson(
        catalog: catalog,
        inventory: {
          'citadel-mephiston-red': const InventoryEntry(
            paintId: 'citadel-mephiston-red',
            status: PaintStatus.low,
          ),
        },
        recipes: [
          Recipe(
            id: 'r1',
            name: 'Test',
            sections: const [
              RecipeSection(name: 'Armour', steps: [
                RecipeStep(title: 'Base', paintId: 'citadel-mephiston-red'),
              ]),
            ],
            updatedAt: DateTime(2026),
          ),
        ],
        lists: [
          PaintList(
            id: 'l1',
            name: 'Project',
            paintIds: const ['citadel-abaddon-black'],
            updatedAt: DateTime(2026),
          ),
        ],
        following: [
          (authorUid: 'x', authorName: 'Borja', seenUpTo: DateTime(2026)),
        ],
        now: DateTime(2026, 8, 24),
      );
      final data = jsonDecode(json) as Map<String, dynamic>;

      final entry = (data['inventory'] as List).single;
      expect(entry['name'], 'Mephiston Red');
      expect(entry['brand'], 'Citadel');
      expect(entry['status'], 'low');

      final step =
          data['recipes'][0]['sections'][0]['steps'][0] as Map<String, dynamic>;
      expect(step['paint']['name'], 'Mephiston Red');

      expect(data['lists'][0]['paints'][0]['name'], 'Abaddon Black');
      expect(data['following'][0]['authorName'], 'Borja');
      // The author UID is deliberately NOT exported: it is an internal key,
      // useless to the user and one more identifier loose in a file.
      expect(json.contains('authorUid'), isFalse);
    });
  });
}
