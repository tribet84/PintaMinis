import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Color, Offset, Size;

import 'package:image/image.dart' as img;

/// Decodes a picked photo for pixel sampling.
///
/// Kept separate from the widget so the geometry below stays a pure
/// function — the part that actually breaks when someone refactors the
/// layout is the tap-to-pixel mapping, and that must be testable without
/// pumping widgets.
img.Image? decodeForSampling(Uint8List bytes) => img.decodeImage(bytes);

/// The colour under a tap on an image rendered with BoxFit.contain.
///
/// [viewport] is the box the image is drawn in, [position] the tap in that
/// box's local coordinates. Returns null for taps on the letterbox bars —
/// sampling the background would hand back a colour the photo does not
/// contain, which is worse than doing nothing.
Color? sampleColorAt(
  img.Image image, {
  required Size viewport,
  required Offset position,
}) {
  final scale = math.min(
    viewport.width / image.width,
    viewport.height / image.height,
  );
  final drawnWidth = image.width * scale;
  final drawnHeight = image.height * scale;
  final left = (viewport.width - drawnWidth) / 2;
  final top = (viewport.height - drawnHeight) / 2;

  final x = (position.dx - left) / scale;
  final y = (position.dy - top) / scale;
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) return null;

  final pixel = image.getPixel(x.floor(), y.floor());
  return Color.fromARGB(
    255,
    pixel.r.toInt(),
    pixel.g.toInt(),
    pixel.b.toInt(),
  );
}
