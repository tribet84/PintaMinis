import 'dart:convert';

import '../data/catalog_repository.dart';
import '../data/published_recipe_repository.dart';
import '../models/inventory_entry.dart';
import '../models/paint_list.dart';
import '../models/recipe.dart';

export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';

/// Builds the user's data as one readable JSON document.
///
/// Exists because the Terms promise it: "keep your own copy of anything you
/// cannot afford to lose" is an empty sentence if the app offers no way to
/// make that copy. Everything is denormalised — paint ids come WITH their
/// name and brand — so the file stays meaningful even opened years later,
/// far from any catalogue that could resolve an id.
String buildExportJson({
  required CatalogRepository catalog,
  required Map<String, InventoryEntry> inventory,
  required List<Recipe> recipes,
  required List<PaintList> lists,
  required List<Follow> following,
  required DateTime now,
}) {
  Map<String, dynamic> paintRef(String id) {
    final paint = catalog.byId(id);
    return {
      'id': id,
      if (paint != null) 'name': paint.name,
      if (paint != null) 'brand': paint.brandName,
      if (paint?.code != null) 'code': paint!.code,
    };
  }

  final data = {
    'app': 'PintaMinis',
    'exportedAt': now.toIso8601String(),
    'inventory': [
      for (final entry in inventory.entries)
        {...paintRef(entry.key), 'status': entry.value.status.name},
    ],
    'recipes': [
      for (final recipe in recipes)
        {
          'name': recipe.name,
          'description': recipe.description,
          'published': recipe.isPublished,
          if (recipe.photoUrl != null) 'photoUrl': recipe.photoUrl,
          'links': [
            for (final link in recipe.links)
              {'title': link.title, 'url': link.url},
          ],
          'sections': [
            for (final section in recipe.sections)
              {
                'name': section.name,
                'techniques': [
                  for (final t in section.techniques) t.name,
                ],
                'notes': section.notes,
                'steps': [
                  for (final step in section.steps)
                    {
                      'title': step.title,
                      if (step.paintId != null) 'paint': paintRef(step.paintId!),
                      'note': step.note,
                    },
                ],
              },
          ],
        },
    ],
    'lists': [
      for (final list in lists)
        {
          'name': list.name,
          'paints': [for (final id in list.paintIds) paintRef(id)],
        },
    ],
    'following': [
      for (final follow in following)
        {'authorName': follow.authorName},
    ],
  };
  return const JsonEncoder.withIndent('  ').convert(data);
}
