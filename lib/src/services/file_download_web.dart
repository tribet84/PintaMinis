import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Hands [content] to the browser as a file download.
///
/// A data: URI on a transient anchor, not a Blob: the file is a few hundred
/// KB of JSON at most, and the data URI needs no revokeObjectURL cleanup
/// dance. The anchor never enters the DOM — click() works detached.
void downloadTextFile({required String filename, required String content}) {
  final anchor = web.HTMLAnchorElement()
    ..href = 'data:application/json;charset=utf-8;base64,'
        '${base64Encode(utf8.encode(content))}'
    ..download = filename;
  anchor.click();
}

// Referenced so the conditional export stays honest about the js_interop
// requirement.
// ignore: unused_element
final _requiresJsInterop = ''.toJS;
