import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';

/// "Slack-style" tips karousel za TvHomeScreen loading state.
///
/// Dok ChannelCache prefetcha 40 kanala (3-10s ovisno o mrezi), umjesto
/// statickog spinnera prikazujemo rotirajuce edukativne poruke o aplikaciji.
/// Cilj: zaintrigirati gledatelja, dati osjecaj da nesto pametno radi u
/// pozadini, smanjiti perceptivno cekanje.
///
/// Format: ikona + naslov + tekst. Tips se mijenjaju svake [interval]
/// sekunde s fade-cross-fade tranzicijom. Pri pokretu cycle-a se ne radi
/// indeks reset — ako screen ostane otvoren dugo, tipovi se ponavljaju
/// (modulo length).
class TvLoadingTips extends StatefulWidget {
  final List<TvTip> tips;
  final Duration interval;
  final double maxWidth;
  // Vizualni progress loader na dnu — animira 0→1 over [progressDuration].
  // Ako stvarni loading (ChannelCache prefetch + featured pick) traje krace,
  // parent screen prebaci u content state i loader je unmount-ed. Ako traje
  // duze, loader ostaje na 100% (TweenAnimationBuilder se zaustavi na end).
  final Duration progressDuration;
  // Optional bible verse displayed above the tips. Odabire se jednom per
  // launch (constructor-time random pick), ne rotira tokom session-a — to
  // bi bilo previse pokreta na ekranu uz tips rotaciju. Native splash je
  // staticni (vidi docs/splash-bible-citations.md zasto rotacija nije
  // moguca na Android <12), pa Flutter splash kompenzira rotacijom ovdje.
  final List<BibleVerse> bibleVerses;

  const TvLoadingTips({
    super.key,
    required this.tips,
    this.interval = const Duration(seconds: 6),
    this.maxWidth = 760,
    this.progressDuration = const Duration(seconds: 10),
    this.bibleVerses = defaultBibleVerses,
  });

  @override
  State<TvLoadingTips> createState() => _TvLoadingTipsState();
}

class _TvLoadingTipsState extends State<TvLoadingTips> {
  int _index = 0;
  Timer? _timer;
  late final BibleVerse _verse;

  @override
  void initState() {
    super.initState();
    // Pick verse jednom — drzi se za cijeli loading session.
    _verse = widget.bibleVerses[Random().nextInt(widget.bibleVerses.length)];
    _timer = Timer.periodic(widget.interval, (_) {
      if (!mounted) return;
      setState(() => _index = (_index + 1) % widget.tips.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tip = widget.tips[_index];

    return Stack(
      children: [
        // Verse fix-an na vrh (32% screen height area), tips card u centru.
        // Vertikalni split: gornje 32% = verse, srednje 50% = tips, donje
        // 18% = padding/progress bar.
        Positioned(
          left: 24,
          right: 24,
          top: 0,
          height: MediaQuery.of(context).size.height * 0.32,
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: widget.maxWidth + 200),
              child: _buildVerse(theme),
            ),
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: widget.maxWidth),
            child: _buildTipCard(theme, tip),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildProgressBar(theme),
        ),
      ],
    );
  }

  Widget _buildVerse(ThemeData theme) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '"${_verse.text}"',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.92),
            fontStyle: FontStyle.italic,
            fontFamily: 'serif',
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '— ${_verse.reference}',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            fontFamily: 'serif',
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar(ThemeData theme) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: widget.progressDuration,
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pripremam katalog…',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  Text(
                    '${(value * 100).round()}%',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.tertiary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: value,
              minHeight: 4,
              color: theme.colorScheme.tertiary,
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTipCard(ThemeData theme, TvTip tip) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      // ValueKey po indexu — bez ovoga AnimatedSwitcher misli da je isti
      // widget pa ne triggera tranziciju.
      child: Padding(
        key: ValueKey(_index),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              tip.icon,
              size: 48,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(height: 20),
            Text(
              tip.title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tip.body,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < widget.tips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: i == _index ? 18 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: i == _index
                          ? theme.colorScheme.tertiary
                          : theme.colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class TvTip {
  final IconData icon;
  final String title;
  final String body;

  const TvTip({
    required this.icon,
    required this.title,
    required this.body,
  });
}

/// Biblijski citat za prikaz iznad tips karousela. Curation iz
/// docs/splash-bible-citations.md (Magisterium AI preporuka).
class BibleVerse {
  final String text;
  final String reference;

  const BibleVerse(this.text, this.reference);
}

const defaultBibleVerses = <BibleVerse>[
  // Mt 10,26 short form je primarni native splash citat (vidi
  // android/app/src/main/res/drawable-nodpi/splash_tagline_1.png).
  // Ovdje izostavljamo kratki Mt 10,26 da Flutter splash nikad ne
  // ponavlja sto je user upravo gledao 12-19s na nativnom splashu.
  BibleVerse(
    'Jer ništa nije tajno osim da bi se očitovalo; niti je što skrito osim da iziđe na vidjelo.',
    'Marko 4,22',
  ),
  BibleVerse(
    'Ta ništa nije tajno što se neće očitovati; ništa skriveno što se ne bi doznalo i na vidjelo izišlo.',
    'Luka 8,17',
  ),
  BibleVerse(
    'Ništa nije prikriveno što se neće otkriti ni tajno što se neće doznati.',
    'Luka 12,2',
  ),
  BibleVerse(
    'Naša je pak domovina na nebesima, odakle iščekujemo Spasitelja, Gospodina Isusa Krista.',
    'Filipljanima 3,20',
  ),
  BibleVerse(
    'Upoznat ćete istinu i istina će vas osloboditi.',
    'Ivan 8,32',
  ),
  BibleVerse(
    "Vaša riječ neka bude: 'Da, da – ne, ne!' Što je više od toga, od Zloga je.",
    'Matej 5,37',
  ),
  BibleVerse(
    'U svijetu ćete imati muku, ali hrabri budite – ja sam pobijedio svijet!',
    'Ivan 16,33',
  ),
  BibleVerse(
    'Gdje ti je blago, ondje će ti biti i srce.',
    'Matej 6,21',
  ),
  BibleVerse(
    'Tražite stoga najprije Kraljevstvo Božje i pravednost njegovu, a sve će vam se ostalo dodati.',
    'Matej 6,33',
  ),
  BibleVerse(
    'Ja sam Put i Istina i Život: nitko ne dolazi Ocu osim po meni.',
    'Ivan 14,6',
  ),
  BibleVerse(
    'Podajte dakle caru carevo, a Bogu Božje.',
    'Matej 22,21',
  ),
  BibleVerse(
    'Žetva je velika, ali radnika malo.',
    'Matej 9,37',
  ),
  BibleVerse(
    'Iz obilja srca usta mu govore.',
    'Luka 6,45',
  ),
];

/// Default set tips-a za TvHomeScreen prefetch loading state. Hrvatski,
/// edukativan ton, fokus na vrijednost koju AI sloj donosi gledatelju.
const defaultTvTips = <TvTip>[
  TvTip(
    icon: Icons.auto_awesome_rounded,
    title: 'Pametan katalog hrvatskih podcasta',
    body:
        'DOMOVINA.ai obrađuje sadržaj pomoću AI-a — svaka epizoda dobiva sažetak, poglavlja, teme i ključne tvrdnje.',
  ),
  TvTip(
    icon: Icons.podcasts_rounded,
    title: 'Više od 40 kanala na jednom mjestu',
    body:
        'Bitno.net, Hrvatska katolička mreža, Mladi za Domovinu, Muževni budite, Redefinicija — sve u jednom toku.',
  ),
  TvTip(
    icon: Icons.menu_book_rounded,
    title: 'Magisterium AI',
    body:
        'Spomenuti pojmovi povezuju se s izvorima učenja Crkve — encilkike, dokumenti Sabora, sveti oci.',
  ),
  TvTip(
    icon: Icons.translate_rounded,
    title: 'Hrvatski i engleski',
    body:
        'Svaka obrađena epizoda dolazi s prijevodom sažetka i članka — za dijasporu i druge govornike.',
  ),
  TvTip(
    icon: Icons.bookmark_added_rounded,
    title: 'Nastavi gdje si stao',
    body:
        'Pozicija se sprema preko uređaja — pokreni epizodu na mobitelu, nastavi na TV-u, dovrši u autu.',
  ),
  TvTip(
    icon: Icons.search_rounded,
    title: 'Pretraga po sadržaju',
    body:
        'Tražilica gleda u sažetke i citate, ne samo u naslove — pitaj o temi i pronađi gdje su je obradili.',
  ),
];
