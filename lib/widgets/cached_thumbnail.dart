import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/cdn_config.dart';

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
///
/// ## Automatske WebP varijante
///
/// Ako je [url] kanonski thumbnail (`/images/{id}/thumbnail.png`), widget ga
/// SAM zamijeni WebP varijantom primjerenom stvarnoj render-širini
/// (`thumb-320/640/1280.webp`). Nijedan call-site ne mora znati za varijante —
/// zato logika živi ovdje, a ne u ~12 mjesta koja zovu `CdnConfig.thumbnailUrl`.
///
/// Razlog: PNG original je 1280×720, tipično ~800 KB. Lista od 20 epizoda
/// povlači ~16 MB. Ista slika kao WebP q80 @320px je ~13 KB — 61× manje
/// (mjereno na produkcijskom `KvJlt9ewgTQ`). To je bio pravi uzrok sporog
/// učitavanja listi, a ne broj paralelnih HTTP requestova.
///
/// Varijante su unaprijed generirane (`fetch.domovina.tv/generate_webp_thumbs.js`)
/// i leže na R2 kao statični immutable fajlovi — nema resize servisa u request
/// pathu, sve ide s Cloudflare edge cachea.
///
/// **Fallback**: ako varijanta vrati grešku (404 — epizoda koju backfill još
/// nije pokrio, ili nova epizoda prije nego pipeline odradi korak), widget se
/// tiho vrati na originalni PNG. U sretnom slučaju to ne košta nijedan dodatni
/// request — nema probe-a unaprijed.
///
/// WebP je siguran za in-app prikaz: Flutter sam dekodira sliku, ne ovisi o
/// browseru. (Za `og:image` i dijeljenje na društvenim mrežama se NE koristi
/// WebP nego `og-share.jpg` — link-preview crawleri WebP ne dokumentiraju.)
class CachedThumbnail extends StatefulWidget {
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

  /// Escape hatch: `false` prisiljava originalni [url] bez WebP nadogradnje.
  /// Koristi samo ako ti stvarno treba baš original (npr. share/export flow).
  final bool useVariants;

  const CachedThumbnail({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.errorIcon = Icons.broken_image_outlined,
    this.errorIconSize = 32,
    this.fadeInDuration = const Duration(milliseconds: 200),
    this.useVariants = true,
  });

  @override
  State<CachedThumbnail> createState() => _CachedThumbnailState();
}

class _CachedThumbnailState extends State<CachedThumbnail> {
  /// Postane `true` kad WebP varijanta pukne → render pada na originalni PNG.
  bool _variantFailed = false;

  @override
  void didUpdateWidget(CachedThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Novi URL = nova slika; prošli neuspjeh se ne prenosi (recikliranje
    // widgeta u ListView-u bi inače trajno zaključalo fallback na PNG).
    if (oldWidget.url != widget.url) _variantFailed = false;
  }

  /// Efektivna render-širina u logičkim pikselima. Ako [widget.width] nije
  /// zadan (slika puni parent), koristimo širinu ekrana kao gornju ogradu —
  /// pesimistično, ali nikad premalo.
  double _renderWidthLogical(BuildContext context) {
    final w = widget.width;
    if (w != null && w.isFinite && w > 0) return w;
    return MediaQuery.sizeOf(context).width;
  }

  /// Vraća URL koji stvarno treba dohvatiti: WebP varijantu ako je moguće,
  /// inače originalni [widget.url].
  String _resolveUrl(BuildContext context, double dpr) {
    if (!widget.useVariants || _variantFailed) return widget.url;

    final match = CdnConfig.thumbnailUrlPattern.firstMatch(widget.url);
    if (match == null) return widget.url;

    final ytId = match.group(1)!;
    final targetPx = _renderWidthLogical(context) * dpr;
    return CdnConfig.thumbnailVariantUrl(
      ytId,
      CdnConfig.pickThumbWidth(targetPx),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final resolvedUrl = _resolveUrl(context, dpr);
    final isVariant = resolvedUrl != widget.url;

    return CachedNetworkImage(
      imageUrl: resolvedUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      fadeInDuration: widget.fadeInDuration,
      // Memory-cache resample na render width pri load-u — HD thumb-ovi
      // (1280×720) renderani na ~360dp cards ne trebaju full bitmap u RAM-u.
      memCacheWidth: widget.width != null && widget.width!.isFinite
          ? (widget.width! * dpr).round()
          : null,
      // Varijanta 404-a (backfill je još ne pokriva) → jednom se prebaci na
      // originalni PNG. Bez ovoga bi epizoda bez varijante ostala prazna.
      errorListener: isVariant
          ? (_) {
              if (!mounted || _variantFailed) return;
              setState(() => _variantFailed = true);
            }
          : null,
      placeholder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      errorWidget: (_, _, _) {
        // Dok fallback ne "sjedne" prikaži placeholder umjesto ikone greške —
        // inače bi korisnik na trenutak vidio broken-image pa sliku.
        if (isVariant) {
          return Container(
            width: widget.width,
            height: widget.height,
            color: theme.colorScheme.surfaceContainerHighest,
          );
        }
        return Container(
          width: widget.width,
          height: widget.height,
          color: theme.colorScheme.surfaceContainerHighest,
          alignment: Alignment.center,
          child: Icon(
            widget.errorIcon,
            color: theme.colorScheme.onSurfaceVariant,
            size: widget.errorIconSize,
          ),
        );
      },
    );
  }
}
