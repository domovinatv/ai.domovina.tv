import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'file_share_web.dart' if (dart.library.io) 'file_share_native.dart'
    as platform;

/// Što se stvarno dogodilo s datotekom.
enum FileShareOutcome {
  /// Otvoren je sistemski share sheet i korisnik je izabrao odredište
  /// (WhatsApp, Mail, Spremi u Datoteke…).
  shared,

  /// Share sheet je otvoren pa zatvoren bez izbora.
  dismissed,

  /// Platforma ne zna dijeliti datoteke (tipično desktop browser) → datoteka je
  /// preuzeta kao obična datoteka.
  downloaded,

  /// Ni dijeljenje ni preuzimanje nije uspjelo.
  failed,
}

/// True kad platforma zna otvoriti share sheet **s datotekom**.
///
/// Web: `navigator.canShare({files})` — iOS Safari i Android Chrome da, desktop
/// Chrome/Firefox ne. Native: iOS/Android/macOS da.
/// Koristi se samo za TEKST gumba („Pošalji…" vs „Preuzmi") — sama
/// [shareFile] svejedno pada na preuzimanje kad dijeljenje nije moguće.
bool canShareFiles() => platform.canShareFilesImpl();

/// Podijeli [bytes] kao datoteku [filename]; ako to platforma ne može, preuzmi je.
///
/// [sharePositionOrigin] je obavezan na iPadu (popover sidro) — proslijedi
/// pravokutnik widgeta koji je akciju pokrenuo.
Future<FileShareOutcome> shareFile({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? text,
  String? subject,
  Rect? sharePositionOrigin,
}) =>
    platform.shareFileImpl(
      bytes: bytes,
      filename: filename,
      mimeType: mimeType,
      text: text,
      subject: subject,
      sharePositionOrigin: sharePositionOrigin,
    );
