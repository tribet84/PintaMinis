import 'camera_capabilities.dart';

/// Camera controls are driven through browser APIs, and the app only ships
/// on web. On any other platform the scanner would come from the native
/// `mobile_scanner` implementation, which exposes zoom and focus through its
/// own controller — so this stub reports "nothing to drive" rather than
/// pretending, and the UI hides the controls it would have shown.

CameraCapabilities? readCameraCapabilities() => null;

Future<bool> applyCameraZoom(double zoom) async => false;

Future<bool> retriggerAutofocus() async => false;
