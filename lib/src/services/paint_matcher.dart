import 'package:flutter/material.dart' hide Paint;

import '../data/catalog_repository.dart';
import '../models/paint.dart';
import 'color_distance.dart';

/// A cross-brand equivalence, graded the way a painter would grade it.
enum MatchTier {
  /// Below deltaE 2: the eye cannot tell them apart.
  twin,

  /// Up to 5: an honest substitute.
  close,

  /// Up to 10: same neighbourhood, check before relying on it.
  approximate,
}

typedef PaintMatch = ({Paint paint, double deltaE, MatchTier tier});

/// How a paint behaves on the model, as far as the range name can tell.
///
/// Matching across these families is where numeric colour distance lies to
/// people: a gold and a brown can share a hex and share nothing on a mini,
/// and a wash's swatch is its dried-on-white tone, not a coat of paint.
/// paintRack matches across them anyway — it is their users' complaint
/// about metallic matches that taught us not to.
enum _Finish { opaque, metallic, translucent }

_Finish _finishOf(Paint paint) {
  final range = paint.range.toLowerCase();
  if (range.contains('metallic')) return _Finish.metallic;
  const translucent = [
    'contrast', 'shade', 'speedpaint', 'xpress', 'wash',
    'dipping ink', 'intensity ink', 'quickshade', '3gen ink',
  ];
  if (translucent.any(range.contains)) return _Finish.translucent;
  return _Finish.opaque;
}

/// The closest paints to [paint] from OTHER brands, best first.
///
/// Same-brand neighbours are excluded on purpose: the question this answers
/// is "I follow a recipe written in Citadel and I own Vallejo", never "what
/// else does my own brand sell".
List<PaintMatch> crossBrandMatches(
  CatalogRepository catalog,
  Paint paint, {
  int limit = 3,
}) {
  return _closest(
    catalog.paints.where((c) => c.brand != paint.brand),
    paint,
    limit: limit,
  );
}

/// The closest substitutes for [paint] among the pots the user already OWNS.
///
/// This is the money question: the recipe names a paint that is not on the
/// shelf — which of MY bottles gets me there without buying anything?
/// Unlike [crossBrandMatches], the same brand is welcome here: a substitute
/// you own beats a purchase from any brand.
List<PaintMatch> shelfSubstitutes(
  CatalogRepository catalog,
  Set<String> ownedIds,
  Paint paint, {
  int limit = 3,
}) {
  return _closest(
    catalog.paints
        .where((c) => c.id != paint.id && ownedIds.contains(c.id)),
    paint,
    limit: limit,
  );
}

/// A colour-search hit. Unlike [PaintMatch], the tier is nullable: search
/// always answers with the nearest pots, and null tier is the honest label
/// for "nothing is truly close — these are merely the least far".
typedef ColorMatch = ({Paint paint, double deltaE, MatchTier? tier});

/// The closest paints to an arbitrary [color], best first — the answer to
/// "I need THIS colour: what gets me there?".
///
/// Only opaque paints compete. There is no source paint here to take a
/// finish family from, and a picked colour is a colour, not a behaviour:
/// a metallic's swatch hex and an ink's dried-on-white tone both lie about
/// what lands on the model — the same lesson that keeps the equivalence
/// matcher from crossing families.
///
/// Unlike the matcher, this never returns empty for want of a good match:
/// past deltaE 10 the tier goes null and the UI is expected to say so.
List<ColorMatch> closestToColor(
  Iterable<Paint> candidates,
  Color color, {
  int limit = 12,
}) {
  final target = labFromColor(color);

  final scored = <({Paint paint, double deltaE})>[];
  for (final candidate in candidates) {
    if (_finishOf(candidate) != _Finish.opaque) continue;
    final candidateColor = candidate.color;
    if (candidateColor == null) continue;
    scored.add((
      paint: candidate,
      deltaE: deltaE2000(target, labFromColor(candidateColor)),
    ));
  }
  scored.sort((a, b) => a.deltaE.compareTo(b.deltaE));

  return [
    for (final s in scored.take(limit))
      (
        paint: s.paint,
        deltaE: s.deltaE,
        tier: s.deltaE < 2
            ? MatchTier.twin
            : s.deltaE < 5
                ? MatchTier.close
                : s.deltaE < 10
                    ? MatchTier.approximate
                    : null,
      ),
  ];
}

List<PaintMatch> _closest(
  Iterable<Paint> candidates,
  Paint paint, {
  required int limit,
}) {
  final color = paint.color;
  if (color == null) return const [];

  final target = labFromColor(color);
  final finish = _finishOf(paint);

  final scored = <({Paint paint, double deltaE})>[];
  for (final candidate in candidates) {
    if (_finishOf(candidate) != finish) continue;
    final candidateColor = candidate.color;
    if (candidateColor == null) continue;
    scored.add((
      paint: candidate,
      deltaE: deltaE2000(target, labFromColor(candidateColor)),
    ));
  }
  scored.sort((a, b) => a.deltaE.compareTo(b.deltaE));

  return [
    for (final s in scored.take(limit))
      // Past 10 the honest answer is "no equivalent", not a bad one.
      if (s.deltaE < 10)
        (
          paint: s.paint,
          deltaE: s.deltaE,
          tier: s.deltaE < 2
              ? MatchTier.twin
              : s.deltaE < 5
                  ? MatchTier.close
                  : MatchTier.approximate,
        ),
  ];
}
