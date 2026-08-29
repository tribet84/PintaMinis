/// What the live camera track can actually be asked to do.
///
/// Read from the browser's own `MediaStreamTrack.getCapabilities()`, so this
/// is the device's honest answer rather than an assumption. Every field can
/// come back unsupported: the same code runs on phones whose camera exposes
/// zoom and manual focus and on laptops that expose neither.
class CameraCapabilities {
  const CameraCapabilities({
    required this.width,
    required this.height,
    required this.minZoom,
    required this.maxZoom,
    required this.zoomStep,
    required this.currentZoom,
    required this.hasTorch,
    required this.focusModes,
  });

  /// The resolution the browser actually delivered, which is often lower than
  /// the one requested — the single most useful number when a barcode will
  /// not decode, because it sets the pixels-per-bar ceiling.
  final int width;
  final int height;

  final double minZoom;
  final double maxZoom;
  final double zoomStep;
  final double currentZoom;

  final bool hasTorch;
  final Set<String> focusModes;

  /// Zoom is the fix for the distance trap a small barcode creates: the pot
  /// has to sit far enough away for the lens to focus at all, which leaves
  /// the code too small to read. Zoom buys back the pixels without moving.
  bool get hasZoom => maxZoom > minZoom;

  bool get hasManualFocus => focusModes.contains('manual');

  /// A starting zoom that frames a dropper-bottle label without the user
  /// discovering the slider first. Capped so a camera with a huge range
  /// does not open absurdly tight and lose the pot altogether.
  double get suggestedZoom {
    if (!hasZoom) return minZoom;
    return maxZoom < 3.0 ? maxZoom : 3.0;
  }

  @override
  String toString() =>
      '${width}x$height, zoom $minZoom-$maxZoom (now $currentZoom), '
      'torch $hasTorch, focus $focusModes';
}
