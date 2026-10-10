/// Web — `<input type=file>` + `FileReader`-free čitanje kroz `arrayBuffer()`.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const fileUploadSupported = true;

Future<({String name, Uint8List bytes})?> pickImageFile() async {
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..accept = 'image/png,image/jpeg,image/webp';
  final done = Completer<web.File?>();
  input.onchange = ((web.Event _) {
    final files = input.files;
    done.complete(files != null && files.length > 0 ? files.item(0) : null);
  }).toJS;
  // `cancel` (Chrome 113+, Safari 16.4+) — bez njega Future visi dok se
  // stranica ne zatvori, što je bezopasno jer ga nitko ne čeka blokirajuće.
  input.oncancel = ((web.Event _) {
    if (!done.isCompleted) done.complete(null);
  }).toJS;
  input.click();
  final file = await done.future;
  if (file == null) return null;
  final buf = await file.arrayBuffer().toDart;
  return (name: file.name, bytes: buf.toDart.asUint8List());
}
