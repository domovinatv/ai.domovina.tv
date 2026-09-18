import 'package:flutter/widgets.dart';

/// Native platforme nemaju `HtmlElementView`/iframe — embed se ne nudi.
bool get supported => false;

Widget buildYouTubeEmbed({
  required String videoId,
  required int startSeconds,
}) =>
    const SizedBox.shrink();
