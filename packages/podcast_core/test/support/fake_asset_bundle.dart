import 'dart:convert';

import 'package:flutter/services.dart';

/// Asset bundle za widget testove jezgre.
///
/// Brend asseti (logo, Google „G”, splash) su po ugovoru u pubspecu LJUSKE
/// (korijen repoa), ne u paketu `podcast_core` — pa ih testovi paketa ne
/// vide u svom bundleu i `Image.asset` bi prijavio grešku. Ovaj bundle vraća
/// prazan manifest i prozirni 1×1 PNG za svaki ključ, pa se widgeti grade
/// bez pravih slika. Kad `BrandConfig` (korak A1 podcasterium plana) preuzme
/// brend assete, ovaj helper više neće trebati.
class FakeAssetBundle extends CachingAssetBundle {
  static final Uint8List _transparentPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
  );

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, Object?>{})!;
    }
    if (key == 'AssetManifest.json') {
      return ByteData.sublistView(utf8.encode('{}'));
    }
    return ByteData.sublistView(_transparentPng);
  }
}
