import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'file_share.dart';

/// Native implementacija — datoteka se zapiše u privremeni direktorij pa preda
/// sistemskom share sheetu (`UIActivityViewController` / `ACTION_SEND`).
///
/// Zašto preko datoteke na disku: iOS i Android share primaju URL datoteke, ne
/// bajtove. Privremeni direktorij sustav sam čisti.

bool canShareFilesImpl() =>
    Platform.isIOS || Platform.isAndroid || Platform.isMacOS;

Future<FileShareOutcome> shareFileImpl({
  required Uint8List bytes,
  required String filename,
  required String mimeType,
  String? text,
  String? subject,
  Rect? sharePositionOrigin,
}) async {
  try {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$filename';
    await File(path).writeAsBytes(bytes, flush: true);

    final result = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: mimeType, name: filename)],
        text: text,
        subject: subject,
        // iPad: bez sidra share sheet ne zna gdje iscrtati popover.
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
    switch (result.status) {
      case ShareResultStatus.success:
        return FileShareOutcome.shared;
      case ShareResultStatus.dismissed:
        return FileShareOutcome.dismissed;
      case ShareResultStatus.unavailable:
        // Android ne javlja ishod — sheet se otvorio, što je ono što nas zanima.
        return FileShareOutcome.shared;
    }
  } catch (_) {
    return FileShareOutcome.failed;
  }
}
