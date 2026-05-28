import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Cached network thumbnail s konzistentnim placeholder + error state-om.
///
/// Wraps [CachedNetworkImage] kao drop-in zamjenu za [Image.network].
/// Disk-persistent cache (preživljava app restart) + sivi placeholder dok
/// slika loadira + standardni error widget. Cache key = URL, pa CDN
/// cache-buster URLs (`?v=…`) prirodno invalidiraju stari fajl.
///
/// Default placeholder: `theme.colorScheme.surfaceContainerHighest` sivi
/// pravokutnik bez ikone — diskretan, ne distrahira korisnika dok ceka.
/// Pri error-u prikazuje ikonu (default `broken_image_outlined`) na istoj
/// pozadini.
class CachedThumbnail extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Icon prikazan ako fetch fail-a (npr. `Icons.podcasts_outlined` za
  /// channel cover, `Icons.broken_image_outlined` za episode thumb).
  final IconData errorIcon;
  final double errorIconSize;

  /// Fade-in duration kad slika stigne nakon placeholder-a. Krátko da
  /// rail scroll ostane responsivan.
  final Duration fadeInDuration;

  const CachedThumbnail({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorIcon = Icons.broken_image_outlined,
    this.errorIconSize = 32,
    this.fadeInDuration = const Duration(milliseconds: 200),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      fadeInDuration: fadeInDuration,
      // Memory-cache resample na render width pri load-u — HD thumb-ovi
      // (1280×720) renderani na ~360dp cards ne trebaju full bitmap u RAM-u.
      memCacheWidth: width != null && width!.isFinite ? width!.toInt() * 2 : null,
      placeholder: (_, _) => Container(
        width: width,
        height: height,
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      errorWidget: (_, _, _) => Container(
        width: width,
        height: height,
        color: theme.colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          errorIcon,
          color: theme.colorScheme.onSurfaceVariant,
          size: errorIconSize,
        ),
      ),
    );
  }
}
