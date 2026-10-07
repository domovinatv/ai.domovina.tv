/// Odabir jedne slikovne datoteke (logo branda u checkoutu sponzorskog
/// trenutka). Web ide preko `<input type=file>` iz `package:web`; native
/// nema implementaciju ([fileUploadSupported] je false) i UI tada ne nudi
/// upload — logo je neobavezan, a novi paket bi trebalo provjeriti protiv
/// `--wasm` builda (vidi passkeys).
library;

import 'dart:typed_data';

import 'file_pick_web.dart' if (dart.library.io) 'file_pick_stub.dart'
    as platform;

typedef PickedFile = ({String name, Uint8List bytes});

bool get fileUploadSupported => platform.fileUploadSupported;

/// Null kad korisnik odustane ili odabir ne uspije.
Future<PickedFile?> pickImageFile() => platform.pickImageFile();
