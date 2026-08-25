import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/src/models/recipe.dart';
import 'package:paintforge/src/state/recipes_provider.dart';

import 'fakes.dart';

/// Regression coverage for a real report: sharing a recipe, having someone
/// link it, unsharing it and sharing it again left it permanently
/// unreachable for that follower — republishing handed out a brand new
/// public id instead of reusing the one the follower's bookmark pointed at.
void main() {
  late FakeRecipeRepository repository;
  late FakePublishedRecipeRepository published;
  late RecipesProvider recipes;

  setUp(() {
    repository = FakeRecipeRepository();
    published = FakePublishedRecipeRepository();
    recipes = RecipesProvider(
      repository: repository,
      publishedRepository: published,
      authorName: () => 'Author',
    );
    addTearDown(recipes.dispose);
  });

  // FakeRecipeRepository streams the new state back through
  // RecipesProvider's subscription rather than updating it synchronously —
  // one microtask turn is enough for it to arrive.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<Recipe> createRecipe() async {
    final id = await repository.create(
      Recipe(id: '', name: 'Necron Lord', updatedAt: DateTime(2026, 1, 1)),
    );
    await settle();
    return recipes.byId(id)!;
  }

  test('publishing for the first time assigns a fresh id', () async {
    final recipe = await createRecipe();
    final publishedId = await recipes.publish(recipe);
    await settle();

    expect(publishedId, isNotNull);
    expect(recipes.byId(recipe.id)!.publishedId, publishedId);
    expect(recipes.byId(recipe.id)!.isPublished, isTrue);
  });

  test('reshare after unshare reuses the exact same id', () async {
    final recipe = await createRecipe();
    final firstId = await recipes.publish(recipe);
    await settle();

    await recipes.unpublish(recipes.byId(recipe.id)!);
    await settle();
    expect(recipes.byId(recipe.id)!.isPublished, isFalse);
    expect(
      recipes.byId(recipe.id)!.publishedId,
      firstId,
      reason: 'unsharing must not forget the id — reuse depends on it',
    );

    final secondId = await recipes.publish(recipes.byId(recipe.id)!);

    expect(
      secondId,
      firstId,
      reason: 'a follower who linked the first id must find the recipe '
          'live again, not orphaned under a new one',
    );
  });

  test('a reshared recipe is live again for someone who linked the old id',
      () async {
    final recipe = await createRecipe();
    final publishedId = await recipes.publish(recipe);
    await settle();

    // Someone links the recipe while it is live.
    await published.link(publishedId!);

    await recipes.unpublish(recipes.byId(recipe.id)!);
    await settle();
    final published1 = await published.watchPublished(publishedId).first;
    expect(published1, isNull, reason: 'unshared: gone for the follower too');

    await recipes.publish(recipes.byId(recipe.id)!);
    final published2 = await published.watchPublished(publishedId).first;

    expect(
      published2,
      isNotNull,
      reason:
          'the follower never unlinked, so the same id becoming live again '
          'must be enough — no re-linking should be required',
    );
    expect(recipes.isLinked(publishedId), isTrue);
  });

  test('duplicating copies content but never sharing state or the photo',
      () async {
    final recipe = await createRecipe();
    await recipes.publish(recipe);
    await settle();
    final original = recipes.byId(recipe.id)!;

    final copyId = await recipes.duplicate(original, copyName: 'Copy');
    await settle();
    final copy = recipes.byId(copyId)!;

    expect(copy.name, 'Copy');
    expect(copy.sections, original.sections);
    // A copy nobody asked to publish must never be born public — and it
    // must not share the original's publishedId, or unsharing one would
    // silently affect the other.
    expect(copy.isPublished, isFalse);
    expect(copy.publishedId, isNull);
    // The photo is one Storage object; deleting either recipe deletes it
    // by URL, so sharing the pointer would break the surviving recipe.
    expect(copy.photoUrl, isNull);
  });

  test('publishing carries the author photo alongside the name', () async {
    final withPhoto = RecipesProvider(
      repository: repository,
      publishedRepository: published,
      authorName: () => 'Author',
      authorPhotoUrl: () => 'https://storage.test/avatar.jpg',
    );
    addTearDown(withPhoto.dispose);
    await settle();

    final recipe = await createRecipe();
    final publishedId = await withPhoto.publish(recipe);
    final doc = await published.watchPublished(publishedId!).first;

    expect(doc!.authorPhotoUrl, 'https://storage.test/avatar.jpg');
  });

  test('refreshAuthorProfile renames old publishes without ringing bells',
      () async {
    final recipe = await createRecipe();
    final publishedId = await recipes.publish(recipe);
    final before = await published.watchPublished(publishedId!).first;

    // The user changes name and picture in Settings, long after publishing.
    final renamed = RecipesProvider(
      repository: repository,
      publishedRepository: published,
      authorName: () => 'New Name',
      authorPhotoUrl: () => 'https://storage.test/new-face.jpg',
    );
    addTearDown(renamed.dispose);
    await renamed.refreshAuthorProfile();

    final after = await published.watchPublished(publishedId).first;
    expect(after!.authorName, 'New Name');
    expect(after.authorPhotoUrl, 'https://storage.test/new-face.jpg');
    // Identity is not news: the content timestamp the bell filters on must
    // survive the rewrite untouched.
    expect(after.recipe.updatedAt, before!.recipe.updatedAt);
  });
}
