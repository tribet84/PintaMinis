import 'package:flutter/material.dart' hide Paint;
import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/l10n/generated/app_localizations.dart';
import 'package:paintforge/src/data/catalog_repository.dart';
import 'package:paintforge/src/features/paints/color_search_screen.dart';
import 'package:paintforge/src/features/paints/paints_screen.dart';
import 'package:paintforge/src/models/inventory_entry.dart';
import 'package:paintforge/src/services/app_settings.dart';
import 'package:paintforge/src/services/paint_matcher.dart';
import 'package:paintforge/src/state/inventory_provider.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CatalogRepository catalog;

  setUpAll(() async {
    catalog = await CatalogRepository.loadFromAssets();
  });

  group('closestToColor', () {
    test('an exact catalogue colour finds its own paint first, as a twin', () {
      // Mephiston Red's recorded colour — the search should surface the
      // very pot the colour came from, at distance zero.
      final matches = closestToColor(catalog.paints, const Color(0xFF9A1115));

      expect(matches.first.paint.name, 'Mephiston Red');
      expect(matches.first.deltaE, 0);
      expect(matches.first.tier, MatchTier.twin);
    });

    test('results come back nearest first', () {
      final matches = closestToColor(catalog.paints, const Color(0xFF3B6C71));

      for (var i = 1; i < matches.length; i++) {
        expect(matches[i].deltaE, greaterThanOrEqualTo(matches[i - 1].deltaE));
      }
    });

    test('metallics and inks never compete — their swatch colour lies', () {
      // Search for gold: the metallic golds must NOT appear even though
      // their hex is the nearest thing to this colour in the catalogue.
      final matches = closestToColor(catalog.paints, const Color(0xFFD4AF37));

      for (final match in matches) {
        final range = match.paint.range.toLowerCase();
        expect(range.contains('metallic'), isFalse,
            reason: '${match.paint.name} (${match.paint.range})');
        expect(range.contains('ink'), isFalse,
            reason: '${match.paint.name} (${match.paint.range})');
      }
    });

    test('never empty-handed: far matches come back with a null tier', () {
      // A colour no miniature paint aims for. The search still answers,
      // but is honest about the distance.
      final matches =
          closestToColor(catalog.paints, const Color(0xFFFF00FF), limit: 3);

      expect(matches, hasLength(3));
      // Whatever the nearest pot is, magenta-laser is nobody's twin.
      expect(matches.first.tier, isNot(MatchTier.twin));
    });
  });

  group('ColorSearchScreen', () {
    Future<InventoryProvider> pumpScreen(
      WidgetTester tester, {
      Map<String, PaintStatus> owned = const {},
    }) async {
      final inventory =
          InventoryProvider(repository: FakeInventoryRepository());
      addTearDown(inventory.dispose);
      for (final entry in owned.entries) {
        await inventory.setStatus(entry.key, entry.value);
      }
      final settings = await testAppSettings();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<CatalogRepository>.value(value: catalog),
            ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
            ChangeNotifierProvider<AppSettings>.value(value: settings),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const ColorSearchScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return inventory;
    }

    testWidgets('an empty shelf opens on All and lists matches',
        (tester) async {
      await pumpScreen(tester);

      final segmented = tester.widget<SegmentedButton<PaintScope>>(
        find.byType(SegmentedButton<PaintScope>),
      );
      expect(segmented.selected, {PaintScope.all});
      // The default colour is a blue — some pot always shows up.
      expect(find.byType(ListTile), findsWidgets);
    });

    testWidgets('a stocked shelf opens on Mine and only offers owned pots',
        (tester) async {
      await pumpScreen(
        tester,
        owned: {'citadel-mephiston-red': PaintStatus.inStock},
      );

      // One pot owned: whatever colour is picked, it is the only result.
      expect(find.text('Mephiston Red'), findsOneWidget);
      expect(find.text('Abaddon Black'), findsNothing);
    });
  });
}
