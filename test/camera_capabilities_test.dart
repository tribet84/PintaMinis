import 'package:flutter_test/flutter_test.dart';
import 'package:paintforge/src/services/camera_capabilities.dart';

CameraCapabilities caps({
  double minZoom = 1,
  double maxZoom = 1,
  Set<String> focusModes = const {},
}) {
  return CameraCapabilities(
    width: 1920,
    height: 1080,
    minZoom: minZoom,
    maxZoom: maxZoom,
    zoomStep: 0.1,
    currentZoom: minZoom,
    hasTorch: false,
    focusModes: focusModes,
  );
}

void main() {
  test('a camera with no zoom range offers no zoom control', () {
    // A laptop webcam reports min == max. Showing a slider that cannot move
    // is worse than showing nothing.
    expect(caps(minZoom: 1, maxZoom: 1).hasZoom, isFalse);
  });

  test('a camera with a zoom range offers zoom', () {
    expect(caps(minZoom: 1, maxZoom: 8).hasZoom, isTrue);
  });

  test('the opening zoom frames a pot without overshooting', () {
    // 3x turns a ~4px-per-bar barcode into ~10px, which is what makes a
    // dropper bottle decodable at a distance the lens can still focus.
    expect(caps(minZoom: 1, maxZoom: 8).suggestedZoom, 3.0);
  });

  test('a camera that cannot reach 3x opens as tight as it goes', () {
    expect(caps(minZoom: 1, maxZoom: 2).suggestedZoom, 2.0);
  });

  test('a camera with no zoom is left where it is', () {
    final fixed = caps(minZoom: 1, maxZoom: 1);
    expect(fixed.suggestedZoom, fixed.minZoom);
  });

  test('manual focus is only claimed when the device lists it', () {
    expect(caps(focusModes: const {'continuous'}).hasManualFocus, isFalse);
    expect(
      caps(focusModes: const {'continuous', 'manual'}).hasManualFocus,
      isTrue,
    );
  });
}
