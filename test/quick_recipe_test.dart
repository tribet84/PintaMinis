import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/l10n/generated/app_localizations.dart';
import 'package:paintforge/src/data/catalog_repository.dart';
import 'package:paintforge/src/data/recipe_photo_repository.dart';
import 'package:paintforge/src/features/recipes/quick_recipe_screen.dart';
import 'package:paintforge/src/features/recipes/recipe_edit_screen.dart';
import 'package:paintforge/src/state/inventory_provider.dart';
import 'package:paintforge/src/state/recipes_provider.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

class _StubPhotoRepository implements RecipePhotoRepository {
  @override
  Future<String> upload(Uint8List bytes) async => 'https://storage.test/p.jpg';

  @override
  Future<String> uploadAvatar(Uint8List bytes) async =>
      'https://storage.test/a.jpg';

  @override
  Future<void> deleteByUrl(String url) async {}

  @override
  Future<void> deleteAll() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CatalogRepository catalog;

  setUpAll(() async {
    catalog = await CatalogRepository.loadFromAssets();
  });

  Future<RecipesProvider> pumpQuick(WidgetTester tester) async {
    final recipes = RecipesProvider(repository: FakeRecipeRepository());
    addTearDown(recipes.dispose);
    final inventory = InventoryProvider(repository: FakeInventoryRepository());
    addTearDown(inventory.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CatalogRepository>.value(value: catalog),
          Provider<RecipePhotoRepository>(create: (_) => _StubPhotoRepository()),
          ChangeNotifierProvider<RecipesProvider>.value(value: recipes),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const QuickRecipeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return recipes;
  }

  testWidgets('name, paints, save — one section, untitled steps, in order',
      (tester) async {
    final recipes = await pumpQuick(tester);

    await tester.enterText(find.byType(TextField), 'Test Marine');
    await tester.tap(find.text('Add paints'));
    await tester.pumpAndSettle();

    // Pick two known pots from the picker, in a deliberate order.
    await tester.enterText(find.byType(TextField).last, 'abaddon');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abaddon Black').first);
    await tester.enterText(find.byType(TextField).last, 'averland');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Averland Sunset').first);
    // The picker pops its selection via the system back.
    await tester.pageBack();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = recipes.recipes.single;
    expect(saved.name, 'Test Marine');
    expect(saved.sections, hasLength(1),
        reason: 'quick mode is ONE section — structure comes later');
    expect(saved.sections.single.name, 'Paints');
    expect(saved.sections.single.steps.map((s) => s.title),
        everyElement(isEmpty));
    expect(saved.sections.single.paintIds,
        ['citadel-abaddon-black', 'citadel-averland-sunset'],
        reason: 'pick order is recipe order');
  });

  testWidgets('an empty name refuses to save', (tester) async {
    final recipes = await pumpQuick(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(recipes.recipes, isEmpty);
    expect(find.text('Required field'), findsOneWidget);
  });

  testWidgets('the full editor stays one tap away', (tester) async {
    await pumpQuick(tester);

    await tester.tap(find.textContaining('Full editor'));
    await tester.pumpAndSettle();

    expect(find.byType(RecipeEditScreen), findsOneWidget);
    expect(find.byType(QuickRecipeScreen), findsNothing,
        reason: 'pushReplacement: back from the editor exits creation');
  });
}
