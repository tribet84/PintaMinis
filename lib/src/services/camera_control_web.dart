import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'camera_capabilities.dart';

/// Direct control of the live camera track, over the top of whatever widget
/// opened it.
///
/// `mobile_scanner` decodes well on web but deliberately does not expose the
/// camera itself: on this platform its `setZoomScale` throws
/// `UnsupportedError` and `setFocusPoint` throws `UnimplementedError`, so the
/// `autoZoom` and `tapToFocus` flags are inert here. The controls exist in
/// the browser all the same — `MediaStreamTrack.applyConstraints()` carries
/// `zoom`, `torch` and `focusMode`/`focusDistance` on Chromium for Android.
/// This file reaches past the plugin to them.
///
/// The track is found through the `<video>` element the preview mounts,
/// because the plugin keeps its stream private. That is a seam, not a hack:
/// exactly one preview is on screen at a time, and every entry point below
/// degrades to "unsupported" rather than throwing when it finds nothing.

/// Minimal views over the JS objects. `package:web` types the core Media
/// Capture spec, but `zoom`, `torch` and `focusDistance` come from the Image
/// Capture extensions, which it does not model — so they are read by name.
extension type _Track(JSObject _) implements JSObject {
  external JSObject getCapabilities();
  external JSObject getSettings();
  external JSPromise<JSAny?> applyConstraints(JSObject constraints);
}

_Track? _activeTrack() {
  final video = web.document.querySelector('video') as web.HTMLVideoElement?;
  final source = video?.srcObject;
  if (source == null) return null;

  final tracks = source.callMethod<JSArray<JSObject>>('getVideoTracks'.toJS);
  final list = tracks.toDart;
  if (list.isEmpty) return null;
  return _Track(list.first);
}

double? _numberAt(JSObject object, String key) {
  if (!object.has(key)) return null;
  final value = object[key];
  if (value.isA<JSNumber>()) return (value! as JSNumber).toDartDouble;
  return null;
}

/// Reads a `{min, max, step}` range, which is how the browser reports a
/// continuously adjustable capability such as zoom.
({double min, double max, double step})? _rangeAt(
  JSObject object,
  String key,
) {
  if (!object.has(key)) return null;
  final range = object[key];
  if (!range.isA<JSObject>()) return null;

  final asObject = range! as JSObject;
  final min = _numberAt(asObject, 'min');
  final max = _numberAt(asObject, 'max');
  if (min == null || max == null) return null;

  return (min: min, max: max, step: _numberAt(asObject, 'step') ?? 0.1);
}

Set<String> _stringListAt(JSObject object, String key) {
  if (!object.has(key)) return const {};
  final value = object[key];
  if (!value.isA<JSArray<JSAny?>>()) return const {};

  return {
    for (final entry in (value! as JSArray<JSAny?>).toDart)
      if (entry.isA<JSString>()) (entry! as JSString).toDart,
  };
}

/// Describes the live camera, or null when there is no preview running yet.
///
/// Callers are expected to retry: the preview needs a moment to negotiate a
/// stream, and asking before then is normal rather than a failure.
CameraCapabilities? readCameraCapabilities() {
  final track = _activeTrack();
  if (track == null) return null;

  try {
    final caps = track.getCapabilities();
    final settings = track.getSettings();
    final zoom = _rangeAt(caps, 'zoom');

    return CameraCapabilities(
      width: (_numberAt(settings, 'width') ?? 0).round(),
      height: (_numberAt(settings, 'height') ?? 0).round(),
      minZoom: zoom?.min ?? 1,
      maxZoom: zoom?.max ?? 1,
      zoomStep: zoom?.step ?? 0.1,
      currentZoom: _numberAt(settings, 'zoom') ?? zoom?.min ?? 1,
      hasTorch: caps.has('torch'),
      focusModes: _stringListAt(caps, 'focusMode'),
    );
  } on Object catch (_) {
    // A browser that types the track but not these extensions. Reporting
    // "no controls" is the honest answer; the preview still scans.
    return null;
  }
}

/// Applies an optical/digital zoom factor to the live track.
///
/// Returns false when the device or browser refuses, so the caller can hide
/// a control that would otherwise sit there doing nothing.
Future<bool> applyCameraZoom(double zoom) async {
  final track = _activeTrack();
  if (track == null) return false;

  try {
    // `advanced` is the route the Image Capture extensions specify for
    // these constraints, and the one Chromium honours; a bare `{zoom: n}`
    // is silently dropped on some builds.
    final constraint = JSObject()..['zoom'] = zoom.toJS;
    final constraints = JSObject()
      ..['advanced'] = <JSObject>[constraint].toJS;

    await track.applyConstraints(constraints).toDart;
    return true;
  } on Object catch (_) {
    return false;
  }
}

/// Nudges the camera to focus again.
///
/// Continuous autofocus can settle on the background behind a small pot and
/// stay there. Dropping to single-shot and back forces a fresh hunt at the
/// current framing.
Future<bool> retriggerAutofocus() async {
  final track = _activeTrack();
  if (track == null) return false;

  try {
    final caps = track.getCapabilities();
    final modes = _stringListAt(caps, 'focusMode');
    if (!modes.contains('single-shot') && !modes.contains('continuous')) {
      return false;
    }

    if (modes.contains('single-shot')) {
      final single = JSObject()..['focusMode'] = 'single-shot'.toJS;
      await track
          .applyConstraints(JSObject()..['advanced'] = <JSObject>[single].toJS)
          .toDart;
    }
    if (modes.contains('continuous')) {
      final continuous = JSObject()..['focusMode'] = 'continuous'.toJS;
      await track
          .applyConstraints(
            JSObject()..['advanced'] = <JSObject>[continuous].toJS,
          )
          .toDart;
    }
    return true;
  } on Object catch (_) {
    return false;
  }
}
