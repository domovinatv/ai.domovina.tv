import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Runtime composer za Android MediaStyle notification artwork.
///
/// Android 13+ renderira notification art u widescreen pravokutniku
/// (~2:1), pa 1:1 square cover izgleda katastrofalno (odreze lijevo+desno).
/// Ovaj modul dinamicki kombinira 1:1 channel avatar (lijevo) + 16:9
/// episode thumbnail (desno) u jedan 1280×640 (2:1) PNG, sprema u temp
/// directory i vraca `file://` URI koji audio_service proslijedi media
/// notifikaciji.
///
/// Na web-u i iOS-u vraca null (tamo Now Playing radi savrseno s 1:1
/// sliko, nema potrebe za kompozicijom).
///
/// Rezultat je cache-iran in-memory po `videoId` tako da se kompozicija
/// dogadja samo jednom per session per epizoda.
class NotificationArt {
  NotificationArt._();

  static final Map<String, String> _cache = {};

  /// Generiraj 2:1 composite artwork za Android. Vraca `file://` URI ili
  /// null ako: nismo na Androidu, download/decode pao, ili I/O greska.
  static Future<String?> composeForAndroid({
    required String videoId,
    required String avatarSquareUrl,
    required String thumbnail16x9Url,
  }) async {
    if (kIsWeb) return null;
    if (defaultTargetPlatform != TargetPlatform.android) return null;

    final cached = _cache[videoId];
    if (cached != null) {
      final cachedPath = Uri.parse(cached).toFilePath();
      if (await File(cachedPath).exists()) return cached;
    }

    try {
      final avatar = await _downloadAndDecode(avatarSquareUrl);
      final thumb = await _downloadAndDecode(thumbnail16x9Url);
      if (avatar == null || thumb == null) return null;

      final path = await _compose(
        videoId: videoId,
        avatar: avatar,
        thumb: thumb,
      );
      final uri = Uri.file(path).toString();
      _cache[videoId] = uri;
      return uri;
    } catch (e) {
      debugPrint('NotificationArt: compose failed — $e');
      return null;
    }
  }

  static Future<ui.Image?> _downloadAndDecode(String url) async {
    final resp = await http.get(Uri.parse(url));
    if (resp.statusCode != 200) return null;
    final codec = await ui.instantiateImageCodec(resp.bodyBytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<String> _compose({
    required String videoId,
    required ui.Image avatar,
    required ui.Image thumb,
  }) async {
    // 2:1 canvas (1280x640). Lijeva polovica (640x640) = 1:1 avatar.
    // Desna polovica (640x640) = 16:9 thumbnail (640x360) centriran
    // vertikalno na tamnoj pozadini.
    const canvasW = 1280.0;
    const canvasH = 640.0;
    const leftW = 640.0;
    const rightX = 640.0;
    const rightW = 640.0;
    const thumbRenderH = 360.0;
    const thumbY = (canvasH - thumbRenderH) / 2;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      const Rect.fromLTWH(0, 0, canvasW, canvasH),
    );

    // Pozadina — neutralno tamna da thumbnail letterbox izgleda cisto.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, canvasW, canvasH),
      Paint()..color = const Color(0xFF111318),
    );

    // Lijevo: 1:1 avatar -> 640x640 (cover fit, ne crop).
    canvas.drawImageRect(
      avatar,
      Rect.fromLTWH(0, 0, avatar.width.toDouble(), avatar.height.toDouble()),
      const Rect.fromLTWH(0, 0, leftW, canvasH),
      Paint()..filterQuality = FilterQuality.high,
    );

    // Desno: 16:9 thumbnail -> 640x360 centriran vertikalno.
    canvas.drawImageRect(
      thumb,
      Rect.fromLTWH(0, 0, thumb.width.toDouble(), thumb.height.toDouble()),
      const Rect.fromLTWH(rightX, thumbY, rightW, thumbRenderH),
      Paint()..filterQuality = FilterQuality.high,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(canvasW.toInt(), canvasH.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    final bytes = byteData!.buffer.asUint8List();

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/notif_art_$videoId.png';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}
