import 'package:flutter/foundation.dart';

/// Non-web platforms would save through a share sheet or a file picker;
/// neither ships yet because the app only ships on web. This stub keeps the
/// conditional import honest instead of hiding a crash behind it.
void downloadTextFile({required String filename, required String content}) {
  debugPrint('downloadTextFile is only implemented on web ($filename)');
}
