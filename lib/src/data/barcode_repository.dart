import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// The community-built EAN → paint mapping.
///
/// No public database of miniature-paint barcodes exists — brands do not
/// publish EAN lists, and commercial barcode APIs barely know this niche.
/// So the mapping is built by the users themselves: the first person to
/// scan an unknown pot teaches the app which paint it is, and every scan
/// of that code afterwards, by anyone, resolves instantly. One person's
/// thirty seconds becomes everyone's zero.
abstract class BarcodeRepository {
  /// The paint id mapped to [ean], or null if nobody has taught it yet.
  Future<String?> lookup(String ean);

  /// Records that [ean] is [paintId], for every user from now on.
  ///
  /// First write wins — see the security rules: mappings are create-only,
  /// so a later scanner can never overwrite what an earlier one taught.
  /// Correcting a genuine mistake is an admin job, deliberately.
  Future<void> teach(String ean, String paintId);
}

class FirestoreBarcodeRepository implements BarcodeRepository {
  FirestoreBarcodeRepository({
    required this.uid,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  /// Session cache: a scanning burst re-reads the same handful of codes,
  /// and each avoided read is a billed operation saved.
  final _cache = <String, String?>{};

  CollectionReference<Map<String, dynamic>> get _barcodes =>
      _firestore.collection('barcodes');

  @override
  Future<String?> lookup(String ean) async {
    if (_cache.containsKey(ean)) return _cache[ean];
    final snapshot = await _barcodes.doc(ean).get();
    final paintId = snapshot.data()?['paintId'] as String?;
    // Negative results are NOT cached: someone else may teach this code
    // while the session is open, and a stale "unknown" would make the same
    // pot ask to be identified twice.
    if (paintId != null) _cache[ean] = paintId;
    return paintId;
  }

  @override
  Future<void> teach(String ean, String paintId) async {
    try {
      await _barcodes.doc(ean).set({
        'paintId': paintId,
        'addedBy': uid,
        'addedAt': FieldValue.serverTimestamp(),
      });
      _cache[ean] = paintId;
    } catch (error) {
      // Most likely: someone taught this code between our lookup and now.
      // Their mapping stands (create-only rules); losing this write is the
      // designed outcome, not a failure worth surfacing.
      debugPrint('Barcode teach skipped for $ean: $error');
    }
  }
}
