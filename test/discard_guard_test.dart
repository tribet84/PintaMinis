import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/l10n/generated/app_localizations.dart';
import 'package:paintforge/src/data/catalog_repository.dart';
import 'package:paintforge/src/features/recipes/quick_recipe_screen.dart';
import 'package:paintforge/src/features/recipes/recipe_edit_screen.dart';
import 'package:paintforge/src/state/inventory_provider.dart';
import 'package:paintforge/src/state/recipes_provider.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

/// A stray back press must never silently eat typed work — and an untouched
/// editor must never nag. Both halves matter: a dialog that always appears
/// trains people to click through it, which is the same as no dialog.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CatalogRepository catalog;

  setUpAll(() async {
    catalog = await CatalogRepository.loadFromAssets();
  });

  Future<void> pumpEditorRoute(WidgetTester tester, Widget editor) async {
    final recipes = RecipesProvider(repository: FakeRecipeRepository());
    addTearDown(recipes.dispose);
    final inventory = InventoryProvider(repository: FakeInventoryRepository());
    addTearDown(inventory.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<CatalogRepository>.value(value: catalog),
          ChangeNotifierProvider<RecipesProvider>.value(value: recipes),
          ChangeNotifierProvider<InventoryProvider>.value(value: inventory),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => editor),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('an untouched editor pops without asking', (tester) async {
    await pumpEditorRoute(tester, const RecipeEditScreen());

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(RecipeEditScreen), findsNothing);
    expect(find.text('Leave without saving?'), findsNothing);
  });

  testWidgets('a dirty editor asks, and "keep editing" stays', (tester) async {
    await pumpEditorRoute(tester, const RecipeEditScreen());
    await tester.enterText(find.byType(TextField).first, 'Half-typed name');

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Leave without saving?'), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.byType(RecipeEditScreen), findsOneWidget);
    expect(find.text('Half-typed name'), findsOneWidget,
        reason: 'the draft survives the dialog');
  });

  testWidgets('a dirty editor discards only on explicit confirmation',
      (tester) async {
    await pumpEditorRoute(tester, const RecipeEditScreen());
    await tester.enterText(find.byType(TextField).first, 'Doomed draft');

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();

    expect(find.byType(RecipeEditScreen), findsNothing);
  });

  testWidgets('the quick screen guards its draft the same way',
      (tester) async {
    await pumpEditorRoute(tester, const QuickRecipeScreen());
    await tester.enterText(find.byType(TextField).first, 'Quick draft');

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Leave without saving?'), findsOneWidget);
  });
}
