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
/// **Fallback**: ako varijanta vrati grešku, widget se tiho vrati na originalni
/// PNG. Pokriva oba uzroka — 404 (epizoda koju backfill još nije pokrio, ili
/// nova epizoda prije nego pipeline odradi KORAK 9.7) i neuspjeh dekodiranja
/// (browser bez WebP podrške). Ne razlikujemo ta dva uzroka i ne moramo —
/// ishod je isti. U sretnom slučaju fallback ne košta nijedan dodatni request —
/// nema probe-a unaprijed. Ako padne i PNG, zove se `onFailed`.
///
/// ## Podrška za WebP dekodiranje
///
/// Na **nativeu** (iOS/Android/macOS) sliku dekodira Skia unutar Flutter
/// enginea — WebP radi bez obzira na OS verziju.
///
/// Na **webu** dekodira BROWSER (Flutter napravi blob i pusti ga kroz
/// `createImageBitmap`/`<img>`), pa podrška prati browser: Chrome 32+,
/// Firefox 65+, Edge 18+, **Safari 14+ / iOS Safari 14+** (rujan 2020.).
/// Realno pokriveno ~97 % prometa, a jedini rupa (iOS ≤ 13) ionako ne vrti
/// Flutter web smisleno. I da pukne, gornji fallback vrati PNG — degradacija
/// je "sporije", ne "prazna slika".
///
/// (Za `og:image` i dijeljenje na društvenim mrežama se NE koristi WebP nego
/// `og-share.jpg` — link-preview crawleri WebP ne dokumentiraju.)
///
/// ## CORS je tvrdi uvjet
///
/// [CachedNetworkImage] povlači bajtove kroz `package:http`, pa URL MORA imati
/// `access-control-allow-origin`. `cdn.domovina.ai` ga ima (`*`) za sve slike.
/// Ne prosljeđuj ovamo URL-ove sa stranih hostova bez provjere — `Image.network`
/// na webu ima `<img>` fallback koji CORS preživi, a ovaj widget nema.
/// Vidi istu zamku u `audio_poster.dart`.
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

  /// Poziva se kad slika KONAČNO ne uspije — dakle tek nakon što je i fallback
  /// na originalni PNG pao, ne na neuspjeh same WebP varijante. Za call-siteove
  /// koji na nepostojeću sliku ne crtaju placeholder nego kolabiraju cijeli
  /// blok (hero, screenshot u članku). Poziv je već odgođen post-frame, pa
  /// [setState] unutar njega smiješ zvati izravno.
  final VoidCallback? onFailed;

  /// Zamjenjuje default error prikaz (obojani pravokutnik + [errorIcon]) kad
  /// call-site na nedostupnu sliku crta nešto svoje — npr. gradijentni backdrop
  /// heroa. Zove se SAMO pri konačnom neuspjehu; dok se pokušava fallback s
  /// WebP varijante na PNG i dalje se prikazuje neutralni placeholder, da
  /// korisnik ne vidi bljesak greške prije nego slika sjedne.
  final WidgetBuilder? errorFallbackBuilder;

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
    this.onFailed,
    this.errorFallbackBuilder,
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
      placeholder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        color: theme.colorScheme.surfaceContainerHighest,
      ),
      // Fallback se okida iz `errorWidget`, a ne iz `errorListener`. Oboje su
      // legitimni hookovi paketa, ali `errorWidget` je onaj koji SIGURNO ide
      // kroz build kad load padne (on crta ono što korisnik vidi), pa je
      // fallback vezan uz njega — bez oslanjanja na to fira li `errorListener`
      // na svakoj platformi. Zove se iz build faze → setState ide post-frame.
      //
      // NAPOMENA: ovaj put nije pokriven automatskim testom (mockanje
      // flutter_cache_managera je nerazmjerno); pokriven je samo izbor URL-a u
      // `test/cdn_thumbnail_variants_test.dart`. Ako mijenjaš ovu granu,
      // provjeri ručno na epizodi kojoj `thumb-*.webp` 404-a a `thumbnail.png`
      // postoji.
      errorWidget: (ctx, _, _) {
        // Varijanta pukla (404 od backfill rupe, ili dekoder bez WebP-a) →
        // prebaci se jednom na originalni PNG i dotad drži neutralni
        // placeholder, da korisnik ne vidi bljesak greške prije slike.
        if (isVariant) {
          if (!_variantFailed) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && !_variantFailed) {
                setState(() => _variantFailed = true);
              }
            });
          }
          return Container(
            width: widget.width,
            height: widget.height,
            color: theme.colorScheme.surfaceContainerHighest,
          );
        }
        // Pao je i PNG → slike stvarno nema.
        if (widget.onFailed != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onFailed!.call();
          });
        }
        final custom = widget.errorFallbackBuilder;
        if (custom != null) return custom(ctx);
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
