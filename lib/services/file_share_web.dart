import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:web/web.dart' as web;

import 'file_share.dart';

/// Web implementacija dijeljenja datoteke — `navigator.share({files})` (Web
/// Share API Level 2), s preuzimanjem kao ispadom.
///
/// Podrška za datoteke je uža od podrške za `share` uopće: iOS Safari i Android
/// Chrome je imaju, desktop Chrome/Firefox uglavnom ne. Zato se detekcija radi
/// probnim `File` objektom, ne provjerom postoji li `navigator.share`.

bool? _canShareCache;

bool canShareFilesImpl() {
  final cached = _canShareCache;
  if (cached != null) return cached;
  var result = false;
  try {
    final probe = web.File(
      [Uint8List(0).toJS].toJS,
      'probe.epub',
      web.FilePropertyBag(type: 'application/epub+zip'),
    );
    result = web.window.navigator.canShare(
      web.ShareData(files: [probe].toJS),
    );
  } catch (_) {
    // Stariji browser bez canShare → NoSuchMethodError/TypeError.
    result = false;
  }
  _canShareCache = result;
  return result;
}

Future<FileShareOutcome> shareFileImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? text,
  String? subject,
  Rect? sharePositionOrigin, // nema značenje na webu
}) async {
  if (canShareFilesImpl()) {
    try {
      final file = web.File(
        [bytes.toJS].toJS,
        filename,
        web.FilePropertyBag(type: mimeType),
      );
      final data = text == null
          ? web.ShareData(files: [file].toJS)
          : web.ShareData(files: [file].toJS, text: text);
      // Ponovna provjera S KONKRETNOM datotekom: browser smije odbiti tip
      // datoteke koji nije na njegovoj dopuštenoj listi.
      if (web.window.navigator.canShare(data)) {
        await web.window.navigator.share(data).toDart;
        return FileShareOutcome.shared;
      }
    } catch (e) {
      if (_isAbort(e)) return FileShareOutcome.dismissed;
      // Sve ostalo (npr. iOS „NotAllowedError" kad je gesta istekla) →
      // preuzimanje ispod, da korisnik ipak dobije datoteku.
    }
  }
  return _download(bytes, filename, mimeType);
}

bool _isAbort(Object e) {
  try {
    // ignore: invalid_runtime_check_with_js_interop_types
    if (e is web.DOMException) return e.name == 'AbortError';
  } catch (_) {}
  return false;
}

FileShareOutcome _download(Uint8List bytes, String filename, String mimeType) {
  try {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    // Blob URL, NE `data:` URL — knjiga je ~2,5 MB, a base64 data URL te
    // veličine browseri znaju tiho odbiti.
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename
      ..style.display = 'none';
    web.document.body!.appendChild(anchor);
    anchor.click();
    anchor.remove();
    // Safari prekine preuzimanje ako se URL oslobodi prerano.
    Timer(const Duration(minutes: 1), () => web.URL.revokeObjectURL(url));
    return FileShareOutcome.downloaded;
  } catch (_) {
    return FileShareOutcome.failed;
  }
}
