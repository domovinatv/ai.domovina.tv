import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../l10n/app_localizations.dart';
import '../main.dart' show log;
import '../models/channel_detail.dart' show ChannelVideo;
import '../models/episode_status.dart';
import '../models/person_hub.dart' show personSlug;
import '../models/podcast_article.dart' show PodcastSection;
import '../services/background_audio.dart';
import '../services/background_playback.dart';
import '../services/episode_language.dart';
import '../services/media_session.dart';
import '../services/channel_cache.dart';
import '../services/data_service.dart';
import '../services/cdn_config.dart';
import '../services/notification_art.dart';
import '../services/open_url.dart';
import '../services/player_resume.dart';
import '../services/page_meta.dart';
import '../services/person_service.dart';
import '../services/playback_intent.dart';
import '../services/playback_speed.dart';
import '../services/player_mute.dart';
import '../services/seek_undo.dart';
import '../services/url_sync.dart';
import '../services/view_mode.dart';
import '../services/watch_progress_service.dart';
import '../widgets/anonymous_signin_bar.dart';
import '../widgets/favorite_button.dart';
import '../widgets/hero_section.dart';
import '../widgets/language_toggle_chip.dart';
import '../pinka_sdk/pinka_sdk.dart';
import '../widgets/summary_section.dart';
import '../widgets/chapters_section.dart';
import '../widgets/article_section.dart';
import '../widgets/magisterium_panel.dart';
import '../widgets/magisterium_v2_view.dart';
import '../widgets/parallel_article_view.dart';
import '../widgets/person_needle_highlight.dart' show hasPersonMention;
import '../widgets/entities_section.dart';
import '../widgets/episode_status_card.dart';
import '../widgets/youtube_embed.dart';
import '../widgets/resume_hint_banner.dart';
import '../widgets/table_of_contents.dart';
import '../widgets/video_panel.dart';
import '../widgets/view_mode_toggle_button.dart';
import '../router/nav.dart';

class EpisodeScreen extends StatefulWidget {
  final String youtubeId;

  /// Start at position in seconds (from ?t= query param, like YouTube).
  final int? startAtSeconds;

  /// Postavljeno na true kad URL eksplicitno sadrzi `/en` sufiks — overrideuje
  /// sticky pref. Ostavljeno null/false znaci: koristi sticky pref ili HR default.
  final bool initialLanguageEn;

  /// Person slug iz `?p=<slug>` (dolazak s /p/ profila govornika) — sekcija na
  /// koju `/t/<sec>` sleti dobiva crvenu "X govori ovdje" oznaku u članku.
  final String? highlightPersonSlug;

  const EpisodeScreen({
    super.key,
    required this.youtubeId,
    this.startAtSeconds,
    this.initialLanguageEn = false,
    this.highlightPersonSlug,
  });

  @override
  State<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends State<EpisodeScreen> {
  EpisodeData? _data;
  Object? _error;
  final Map<String, (bool done, bool ok)> _assetStatus = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Ruta više ne nosi `startAt`/`person` u `ValueKey`-u (vidi app_router.dart),
  /// pa isti `State` može dobiti novi `youtubeId` samo kad go_router zadrži
  /// stranicu istog ključa — a to se događa jedino pri promjeni jezika
  /// (`/v/<id>` ↔ `/v/<id>/en` imaju RAZLIČIT ključ, dakle ne). Guard je ipak
  /// tu jer bi tiho prikazivanje stare epizode pod novim ID-em bilo teško uočiti.
  @override
  void didUpdateWidget(EpisodeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.youtubeId != widget.youtubeId) {
      _data = null;
      _error = null;
      _assetStatus.clear();
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final data = await EpisodeData.loadWithProgress(
        youtubeId: widget.youtubeId,
        onProgress: (asset, done, ok) {
          if (mounted) setState(() => _assetStatus[asset] = (done, ok));
        },
      );
      if (mounted) {
        setState(() => _data = data);
        // Runtime <title>/og meta za živu SPA sesiju — isti format kao
        // worker edge-inject za /v/ (crawleri i dalje idu kroz _worker.js).
        setPageMeta(
          title: '${data.displayTitle} – DOMOVINA.ai',
          description: data.summary?.summary.abstractHr,
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) {
      return _EpisodeContent(
        data: _data!,
        startAtSeconds: widget.startAtSeconds,
        initialLanguageEn: widget.initialLanguageEn,
        highlightPersonSlug: widget.highlightPersonSlug,
      );
    }

    if (_error != null) {
      // `info.json` 404 ne znaci nuzno da epizoda ne postoji — moze biti tek
      // registrirana u channel listingu, a jos nepreuzeta (faza `queued`).
      // Takvu prepoznaje i objasni _QueuedEpisodeScreen; sve ostalo je greska.
      if (_error is VideoNotFoundException) {
        return _QueuedEpisodeScreen(youtubeId: widget.youtubeId);
      }
      final theme = Theme.of(context);
      final l = AppLocalizations.of(context);
      return Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(l.episodeLoadError('$_error'), textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back),
                    label: Text(l.commonBack),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // Loading screen with per-asset progress
    return _LoadingScreen(
      youtubeId: widget.youtubeId,
      assetStatus: _assetStatus,
    );
  }
}

/// Ekran za epizodu koja je u katalogu, ali kod nas jos nema NIJEDNU datoteku
/// (`info.json` vraca 404) — faza [EpisodeStage.queued].
///
/// Dosad je takva epizoda zavrsavala na generickom "nije pronadena na CDN-u",
/// sto je bilo i netocno (epizoda POSTOJI, vidi se u railu "Upravo stiglo") i
/// slijepa ulica. Naslov, kanal i sliku uzimamo iz channel listinga, jedinog
/// mjesta gdje takva epizoda uopce postoji, a reprodukciju nudimo kroz
/// ugradeni YouTube player.
///
/// **Rule**: embed se nudi SAMO ako je ID nasao svoj red u channel listingu.
/// Bez te provjere bi `/v/<bilo-koji-YouTube-ID>` ugradivao proizvoljan tudi
/// video pod nasim brandom.
class _QueuedEpisodeScreen extends StatefulWidget {
  final String youtubeId;

  const _QueuedEpisodeScreen({required this.youtubeId});

  @override
  State<_QueuedEpisodeScreen> createState() => _QueuedEpisodeScreenState();
}

class _QueuedEpisodeScreenState extends State<_QueuedEpisodeScreen> {
  ({String channelId, String channelName, ChannelVideo video})? _listed;
  bool _searching = true;

  @override
  void initState() {
    super.initState();
    _find();
  }

  Future<void> _find() async {
    final hit = await channelCache.findVideoAsync(widget.youtubeId);
    if (!mounted) return;
    setState(() {
      _listed = hit;
      _searching = false;
    });
    if (hit != null) {
      setPageMeta(title: '${hit.video.displayTitle} – DOMOVINA.ai');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final listed = _listed;

    if (_searching) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        body: const SafeArea(child: Center(child: CircularProgressIndicator())),
      );
    }

    // ID nije ni u jednom kanalu — to je prava 404, ne epizoda u obradi.
    if (listed == null) {
      return _NotFoundScreen(youtubeId: widget.youtubeId);
    }

    // Isti raspored kao basic layout: na širokom ekranu player desno, status
    // lijevo. Prag je isti (1100) da prijelaz između faza ne pomiče stupce.
    final wide = MediaQuery.sizeOf(context).width > 1100;

    final content = SingleChildScrollView(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  listed.video.displayTitle,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  listed.video.date ?? listed.channelName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                if (!wide) ...[
                  InAppYouTubePlayer(
                    videoId: widget.youtubeId,
                    posterUrl: CdnConfig.thumbnailUrl(widget.youtubeId),
                  ),
                  const SizedBox(height: 20),
                ],
                EpisodeStatusCard(
                  status: EpisodeStatus.measured(
                    hasInfo: false,
                    hasMedia: false,
                    hasTranscript: false,
                    hasSummary: false,
                    hasArticle: false,
                    hasMagisterium: false,
                  ),
                  footnote: l.episodeStatusNotOnCdn(widget.youtubeId),
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => openUrl(
                    'https://www.youtube.com/watch?v=${widget.youtubeId}',
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l.episodeOpenOnYouTube),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      appBar: AppBar(
        title: _Breadcrumb(
          channelName: listed.channelName,
          channelSlug: listed.channelId,
          episodeTitle: listed.video.displayTitle,
        ),
        titleSpacing: 0,
      ),
      body: SafeArea(
        top: false,
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: content),
                  _YouTubeSidePanel(youtubeId: widget.youtubeId),
                ],
              )
            : content,
      ),
    );
  }
}

/// Prava 404 — ID ne postoji ni na CDN-u ni u jednom channel listingu.
class _NotFoundScreen extends StatelessWidget {
  final String youtubeId;

  const _NotFoundScreen({required this.youtubeId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.video_file_outlined, size: 48),
                const SizedBox(height: 12),
                Text(
                  l.episodeNotFoundDetailed(youtubeId),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Text(
                  CdnConfig.infoUrl(youtubeId),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.go('/'),
                  icon: const Icon(Icons.arrow_back),
                  label: Text(l.commonBack),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Desni stupac s ugrađenim YouTube playerom — zamjena za [VideoPanel] na
/// epizodama kojima medija još nije kod nas.
///
/// Zašto stupac a ne inline blok: na širokom ekranu je desna strana mjesto na
/// kojem korisnik i inače očekuje player (ondje stoji `VideoPanel`), a status
/// kartica s koracima obrade time ostaje iznad pregiba umjesto da je 16:9 blok
/// gurne dolje. Panel se ne skrola sa sadržajem — kao ni `VideoPanel`.
class _YouTubeSidePanel extends StatelessWidget {
  final String youtubeId;

  /// Isti raspon kao `VideoPanel` (360), ali malo širi jer je ovdje player
  /// jedini sadržaj stupca, a YouTube kontrole na 360 dp postaju skučene.
  static const double width = 440;

  const _YouTubeSidePanel({required this.youtubeId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);

    // Bez ispune i bez lijevog ruba: `VideoPanel` ih nosi jer je gust panel s
    // kontrolama i poglavljima, a ovdje je sadržaj samo player — obrub na
    // svijetloj temi ispadne bijela crta koja siječe stranicu ni zbog čega.
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: InAppYouTubePlayer(
              videoId: youtubeId,
              posterUrl: CdnConfig.thumbnailUrl(youtubeId),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                const Icon(Icons.smart_display, size: 16, color: Color(0xFFFF0000)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l.episodeYouTubeUntilProcessed,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  final String youtubeId;
  final Map<String, (bool done, bool ok)> assetStatus;

  const _LoadingScreen({required this.youtubeId, required this.assetStatus});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final doneCount = assetStatus.values.where((s) => s.$1).length;
    final totalCount = assetStatus.isEmpty ? 7 : assetStatus.length;
    final progress = totalCount > 0 ? doneCount / totalCount : 0.0;

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Progress ring
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      value: assetStatus.isEmpty ? null : progress,
                      strokeWidth: 4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l.episodeLoading,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    youtubeId,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Asset status list
                  ...assetStatus.entries.map((e) {
                    final (done, ok) = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: done
                                ? Icon(
                                    ok
                                        ? Icons.check_circle
                                        : Icons.remove_circle_outline,
                                    size: 18,
                                    color: ok
                                        ? const Color(0xFF2E7D32)
                                        : theme.colorScheme.onSurfaceVariant
                                              .withAlpha(100),
                                  )
                                : const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            e.key,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: done && !ok
                                  ? theme.colorScheme.onSurfaceVariant
                                        .withAlpha(100)
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

/// Trorazinski breadcrumb koji zamjenjuje obični channel-name title u app baru:
///
///   `Početna  ›  <Kanal>  ›  <Epizoda>`
///
/// Prva dva čvora su tap-abilni (`context.go`), epizoda je trenutni čvor
/// (bold, ne-klikabilan, ellipsis). Derivira se iz same epizode
/// (`info.channelId` / `info.channel`) pa radi neovisno o tome je li korisnik
/// stigao s homepagea, kanala ili izravnog deep-linka — uvijek nudi i "natrag
/// na Početnu" i "natrag na kanal". Navigacija ide preko `context.go` jer app
/// koristi go_router replace-semantiku (nema push stacka).
///
/// [channelSlug] je naš route-ready slug (npr. `muzevni-budite`), razriješen
/// preko `channelCache.channelIdForName` — NIJE YouTube UC… id iz
/// `info.channelId` (taj ne postoji kao `/c/:slug`). Dok se index ne učita
/// (deep-link) slug je null pa se kanal-čvor sakrije.
class _Breadcrumb extends StatelessWidget {
  final String channelName;
  final String? channelSlug;
  final String episodeTitle;

  const _Breadcrumb({
    required this.channelName,
    required this.channelSlug,
    required this.episodeTitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final slug = channelSlug;
    final hasChannel =
        slug != null && slug.isNotEmpty && channelName.isNotEmpty;
    final width = MediaQuery.sizeOf(context).width;
    // Mobitel (<600): breadcrumb je horizontalno skrolabilan i prikazuje PUNI
    // put (uklj. epizodu) — konzistentno sa skrolabilnim redom akcija. Na
    // tabletu/desktopu: Flexible + ellipsis, epizoda tek >760.
    final scrollable = width < 600;
    final showEpisode = scrollable || width > 760;

    Widget crumb(String label, {VoidCallback? onTap, bool current = false}) {
      Widget text = Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: current ? FontWeight.w600 : FontWeight.w500,
          color: current ? theme.colorScheme.onSurface : muted,
        ),
      );
      if (onTap == null) return text;
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: text,
        ),
      );
    }

    Widget sep() => Icon(Icons.chevron_right, size: 18, color: muted);

    // U scrollable modu NE koristimo Flexible (unbounded width u horizontalnom
    // scrollu bi pucao) — crumbovi idu na intrinzičnu širinu.
    Widget node(Widget child) => scrollable ? child : Flexible(child: child);

    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        crumb('Početna', onTap: () => context.go('/')),
        if (hasChannel) ...[
          sep(),
          node(
            crumb(
              channelName,
              onTap: () => context.go('/c/$slug'),
              // Kad epizodu skrivamo (širina 600–760), kanal je zadnji čvor.
              current: !showEpisode,
            ),
          ),
        ],
        if (showEpisode) ...[sep(), node(crumb(episodeTitle, current: true))],
      ],
    );

    // Rubnih 12px živi OVDJE (content padding unutar scrolla / Padding oko
    // statičnog reda), a _episodeAppBar ima titleSpacing: 0 — inače bi se
    // scrollabilni breadcrumb rezao 12px od ruba ekrana.
    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: row,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: row,
    );
  }
}

class _EpisodeContent extends StatefulWidget {
  final EpisodeData data;
  final int? startAtSeconds;
  final bool initialLanguageEn;
  final String? highlightPersonSlug;

  const _EpisodeContent({
    required this.data,
    this.startAtSeconds,
    this.initialLanguageEn = false,
    this.highlightPersonSlug,
  });

  @override
  State<_EpisodeContent> createState() => _EpisodeContentState();
}

class _EpisodeContentState extends State<_EpisodeContent>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();
  late final Map<String, GlobalKey> _sectionKeys;
  late final Map<String, GlobalKey> _magSectionKeys;
  String? _activeTimestamp; // prati video player poziciju
  String? _scrollTimestamp; // prati scroll poziciju srednje liste

  /// True kad je aktivan paralelni desktop layout (sticky "Članak ‖ Magisterium"
  /// header). Postavlja se u build(); koristi ga _scrollToSection da odbije
  /// fixed pinned visinu (app bar + sticky header) pri scrollu na sekciju.
  bool _parallelActive = false;

  // Mobile tab switcher: 0 = članak, 1 = Magisterium.
  // Aktivan samo kad je !isWide && hasMag (inače nema tab bara).
  int _mobileTab = 0;

  /// Sprjecava ponavljanje auto-open endDrawera ako korisnik zatvori panel.
  bool _endDrawerAutoOpened = false;

  /// Kad app ode u background dok je endDrawer otvoren, Android unisti
  /// SurfaceView pa media_kit auto-pauzira. Mitigacija: zatvori drawer
  /// na `paused` (Video widget detacha -> audio nastavi) i reopen na
  /// `resumed` da korisnik pri povratku (npr. klik na notifikaciju) vidi
  /// player kakav je bio.
  bool _endDrawerWasOpenBeforeBg = false;

  // Video
  Player? _player;
  VideoController? _videoController;
  StreamSubscription<Duration>? _positionSub;
  bool _videoReady = false;

  /// Sortirane sekcije kao (Duration, timestampString) za sync Video→Text
  late final List<({Duration dur, String ts})> _sortedSections;

  /// Chapters za VideoPanel
  late final List<VideoChapterMark> _videoChapters;

  /// Sprječava auto-scroll iz video listenera dok korisnik ručno scrolla
  DateTime? _lastManualScroll;

  /// Sprjecava auto-sync activeTimestamp iz video position listenera
  /// tijekom rucnog klika na chapter (preroll seek, TOC klik, itd.)
  DateTime? _seekLock;
  static const _seekLockDuration = Duration(milliseconds: 2100);

  /// Kratki lock koji sprjecava scroll listener da overridea scrollTimestamp
  /// dok traje programatski scroll (auto-scroll iz video playbacka).
  DateTime? _scrollLock;

  /// URL sync — zadnja sekunda za koju smo update-ali address bar.
  /// Razlog: position stream fira ~5×/s; želimo update najviše 1×/s i samo
  /// kad se sekunda promijenila.
  int _lastUrlSyncedSec = -1;

  /// Inline resume hint — nije SnackBar (lingera preko ekrana), nego widget
  /// u Stack-u koji se uništava s screenom. null = sakriven.
  int? _resumeHintSeconds;
  Timer? _resumeHintTimer;
  static const _resumeHintDuration = Duration(seconds: 4);

  /// Odgovor na „želi li korisnik da ovo svira?". Ožičen na
  /// `player.stream.playing` (jedini izvor koji hvata i media_kitove interne
  /// kontrole), s prozorom tolerancije oko poznatih framework tranzicija —
  /// zatvaranje endDrawera (dispose `Video` widgeta → media_kit pauza) i
  /// odlazak u pozadinu (SurfaceView teardown). Zamjenjuje raniji snapshot
  /// „je li svirao kad je drawer otvoren", koji je poništavao korisnikovu
  /// Pauzu ako je stisnuta dok je drawer bio otvoren.
  /// Vidi `services/playback_intent.dart`.
  PlaybackIntent? _playbackIntent;

  /// „Vrati me gdje sam bio" nakon ručnog skoka po timelineu. Programske
  /// skokove (resume pri otvaranju, tap na poglavlje — odluka D2) najavljujemo
  /// kroz `suppress()`. Vidi `services/seek_undo.dart`.
  SeekUndo? _seekUndo;

  /// Per-episode jezik prikaza. URL `/en` sufix ima prednost nad sticky pref.
  /// Inicijalno HR; ako URL nije EN, ucitaj sticky pref iz prefs-a.
  EpisodeLanguage _language = EpisodeLanguage.hr;

  /// Naš route-ready channel slug (npr. `muzevni-budite`) za breadcrumb `/c/`
  /// link. Razrješava se iz channel indexa po imenu kanala (vidi
  /// `_resolveChannelSlug`). Null dok se index ne učita ili ako nema matcha —
  /// breadcrumb tada sakrije kanal-čvor.
  String? _channelSlug;

  /// Cover-art za audio-only epizode (CORS-safe channel avatar square).
  /// Razrješava se iz channel indexa u [_resolveChannelSlug].
  String? _audioArtUrl;

  /// Person-highlight marker (dolazak s /p/ profila preko `?p=<slug>`):
  /// timestamp sekcije za pill oznaku + razriješeno ime osobe (needle za
  /// inline highlight u tekstu svih sekcija). Pill se prikaže samo kad je
  /// tvrdnja provjerljiva: osoba je diarizirani govornik ("govori ovdje") ILI
  /// ciljna sekcija stvarno sadrži spomen imena ("ovdje se spominje").
  /// Vidi [_initPersonHighlight].
  String? _personHighlightTs;
  String? _personHighlightName;
  bool _personHighlightSpeaks = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolveChannelSlug();

    // 1) URL forsiranje (npr. /v/<id>/en) — najjaci signal.
    if (widget.initialLanguageEn && widget.data.hasTranslationEn) {
      _language = EpisodeLanguage.en;
    } else {
      // 2) Sticky pref iz prosle sesije — samo ako EN prijevod postoji.
      // Bez prijevoda toggle se i ne prikazuje, pa nema smisla startati u EN.
      loadPreferredLanguage().then((saved) {
        if (!mounted) return;
        if (saved == EpisodeLanguage.en && widget.data.hasTranslationEn) {
          setState(() => _language = EpisodeLanguage.en);
          _syncLanguageUrl(EpisodeLanguage.en);
        }
      });
    }
    final article = widget.data.article;
    _sectionKeys = {
      if (article != null)
        for (final iter in article.iterations)
          for (final sec in iter.sections) sec.screenshotTimestamp: GlobalKey(),
    };

    // Keys za Magisterium stupac — scroll sync (primary variant)
    final magPrimary = widget.data.magisteriumPrimary;
    _magSectionKeys = {
      if (magPrimary != null)
        for (final iter in magPrimary.iterations)
          for (final sec in iter.sections)
            if (sec.magisterium != null) sec.screenshotTimestamp: GlobalKey(),
    };

    _sortedSections = [
      if (article != null)
        for (final iter in article.iterations)
          for (final sec in iter.sections)
            (
              dur: _parseDuration(sec.screenshotTimestamp),
              ts: sec.screenshotTimestamp,
            ),
    ]..sort((a, b) => a.dur.compareTo(b.dur));

    _videoChapters = _sortedSections.map((s) {
      final label = _subtitleForTimestamp(s.ts);
      return VideoChapterMark(position: s.dur, timestamp: s.ts, label: label);
    }).toList();

    _initPersonHighlight();

    _scrollController.addListener(_onScroll);
    // Brzina je globalna postavka (D1) — gumb je mijenja na singletonu, ekran
    // je odavde prenosi na svoj Player. Jedan smjer, bez dvostrukog puta.
    PlaybackSpeed.instance.addListener(_applyPlaybackRate);
    _initVideo();
  }

  /// Ruta zadržava isti `State` kad se promijeni SAMO `startAt` ili `?p=`
  /// (ključ je od 6.9.2026. `video-<id>-<jezik>` — vidi app_router.dart), pa se
  /// ta dva propa moraju primijeniti OVDJE. Prije toga je promjena timestampa
  /// bila novi ključ → novi State → uništen player i ponovno učitavanje svih
  /// artefakata; sada je to seek na živom playeru.
  @override
  void didUpdateWidget(_EpisodeContent oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Nova ciljna sekunda iz URL-a (share link, tap na moment s /p/ profila).
    final startAt = widget.startAtSeconds;
    if (startAt != oldWidget.startAtSeconds && startAt != null) {
      final player = _player;
      if (player != null) {
        // Programski skok — ne smije se ponuditi kao "Vrati me natrag".
        _seekUndo?.suppress();
        player.seek(Duration(seconds: startAt));
      }
    }

    // Novi (ili maknuti) person-highlight marker.
    if (widget.highlightPersonSlug != oldWidget.highlightPersonSlug) {
      _personHighlightTs = null;
      _personHighlightName = null;
      _personHighlightSpeaks = false;
      _initPersonHighlight();
    }
  }

  /// Primijeni trenutnu globalnu brzinu na player + osvježi media sesiju.
  void _applyPlaybackRate() {
    final player = _player;
    if (player == null) return;
    final rate = PlaybackSpeed.instance.rate;
    player.setRate(rate);
    // Native media sesiju ažurira `background_audio.dart` preko
    // `player.stream.rate`; web nema takav stream pa gura odmah.
    MediaSession.setPositionState(
      duration: Duration(seconds: widget.data.info.duration),
      position: player.state.position,
      playbackRate: rate,
    );
  }

  /// Razriješi `?p=<slug>` u (ime osobe za needle highlight, timestamp sekcije
  /// za pill). Ime se matcha protiv diariziranih govornika epizode istim
  /// [personSlug] foldom koji koristi i backend (pa dobijemo pravo ime s
  /// dijakriticima bez dodatnog fetcha); fallback je "otfoldani" slug (Title
  /// Case, bez dijakritika) + async dorada s person API-ja.
  ///
  /// Pill se postavlja SAMO kad je tvrdnja provjerljiva (feedback 2026-07-23:
  /// "govori ovdje" bio prikazan i za osobu koja se samo spominje):
  ///  - osoba je diarizirani govornik → "X govori ovdje"
  ///  - inače, ciljna sekcija sadrži spomen imena → "Ovdje se spominje: X"
  ///  - inače bez pilla — inline needle highlight pokazuje spomene drugdje.
  ///
  /// BEZ `/t/<sec>` u URL-u (epizodni spomen — `mention_ts` se nije razriješio
  /// iz article.json, ~40% spomena) nemamo ciljnu sekundu, pa je sami tražimo:
  /// prva sekcija koja referencira osobu postaje sidro (pill + auto-scroll).
  /// Prije 2026-07-27 se u tom slučaju NIŠTA nije razrješavalo — ni ime ni
  /// pill — pa je jedini trag bio crveni chip u „Osobe" na dnu članka.
  void _initPersonHighlight() {
    final slug = widget.highlightPersonSlug;
    final startAt = widget.startAtSeconds;
    if (slug == null || slug.isEmpty) return;
    if (_sortedSections.isEmpty) return;

    // Sekcija u koju deep-link sekunda pada (zadnja s početkom <= startAt);
    // prije prve sekcije → prva (deep-link na sam uvod). Bez startAt-a sidro
    // tražimo tek dolje, po sadržaju.
    String? ts;
    if (startAt != null) {
      final pos = Duration(seconds: startAt);
      ts = _sortedSections.first.ts;
      for (final s in _sortedSections) {
        if (pos >= s.dur) {
          ts = s.ts;
        } else {
          break;
        }
      }
    }

    var name = slug
        .split('-')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
    var speaks = false;
    final speakers = widget.data.summary?.summary.speakers ?? const [];
    for (final sp in speakers) {
      final dn = sp.displayName;
      if (dn != null && personSlug(dn) == slug) {
        name = dn;
        speaks = true;
        break;
      }
    }

    _personHighlightName = name;
    // Bez ciljne sekunde ne možemo tvrditi "govori ovdje" ni za diariziranog
    // govornika — sidro nalazimo po spomenu, pa je i tvrdnja "spominje se".
    _personHighlightSpeaks = speaks && ts != null;

    /// Referencira li sekcija osobu: ime u tekstu (dijakritik-neosjetljivo) ILI
    /// među `entities` (AI atribucija — ime često nije u prozi članka).
    bool refersToPerson(String sectionTs) {
      final sec = _sectionFor(sectionTs);
      if (sec == null) return false;
      return hasPersonMention(sec.content, name) ||
          sec.entities.any((e) => personSlug(e) == slug);
    }

    if (ts != null) {
      // Pill samo kad je tvrdnja provjerljiva na TOJ sekciji.
      if (speaks || refersToPerson(ts)) _personHighlightTs = ts;
    } else {
      // Epizodni spomen: prva sekcija koja referencira osobu postaje sidro.
      for (final s in _sortedSections) {
        if (refersToPerson(s.ts)) {
          _personHighlightTs = s.ts;
          break;
        }
      }
      if (_personHighlightTs != null) _scrollToPersonAnchor(_personHighlightTs!);
    }
    log('person highlight: $slug → "$name" @ ${ts ?? _personHighlightTs} '
        '(speaks=$speaks, startAt=$startAt, pill=${_personHighlightTs != null})');

    // Slug nije među govornicima ove epizode (npr. spomen ili drukčije
    // diarizirano ime) → fallback ime iz sluga nema dijakritike ("Stojic").
    // Doradi async s pravim imenom s person API-ja (5-min CDN cache, jeftino).
    if (!speaks) {
      PersonService.fetch(slug).then((hub) {
        final proper = hub?.name.trim();
        if (!mounted || proper == null || proper.isEmpty) return;
        setState(() => _personHighlightName = proper);
      });
    }
  }

  /// Doscrollaj članak na sekciju u kojoj se osoba spominje, kad deep-link nema
  /// `/t/<sec>`. Video se NAMJERNO ne seeka — znamo sekciju, ne sekundu; lažni
  /// seek bi odveo korisnika na krivo mjesto reprodukcije.
  ///
  /// Isti re-scroll safety net kao [_setInitialChapter]: async sadržaj
  /// (Magisterium, web fontovi, kasne slike) pomiče target nakon prvog frame-a.
  /// Svaki pokušaj odustaje čim je korisnik sam počeo scrollati.
  void _scrollToPersonAnchor(String ts) {
    _scrollTimestamp = ts;
    void go() {
      if (!mounted) return;
      if (_lastManualScroll != null) return;
      _scrollLock = DateTime.now();
      _scrollToSection(ts);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => go());
    Future<void>.delayed(const Duration(milliseconds: 300), go);
    Future<void>.delayed(const Duration(milliseconds: 1200), go);
  }

  /// Sekcija članka s danim screenshot timestampom, ili null.
  PodcastSection? _sectionFor(String ts) {
    final article = widget.data.article;
    if (article == null) return null;
    for (final iter in article.iterations) {
      for (final sec in iter.sections) {
        if (sec.screenshotTimestamp == ts) return sec;
      }
    }
    return null;
  }

  /// `p=<slug>` query string za playback URL sync — čuva person marker u
  /// adresnoj traci da copy-paste link zadrži oznaku. Null bez aktivnog markera.
  String? get _highlightQuery => _personHighlightName != null
      ? 'p=${widget.highlightPersonSlug}'
      : null;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    PlaybackSpeed.instance.removeListener(_applyPlaybackRate);
    _positionSub?.cancel();
    _resumeHintTimer?.cancel();
    WatchProgressService.instance.flush();
    BackgroundAudio.instance.detach();
    MediaSession.clear();
    _playbackIntent?.dispose();
    _seekUndo?.dispose();
    final player = _player;
    if (player != null) {
      PlayerMute.instance.detach(player);
      player.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final s = _scaffoldKey.currentState;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      if (s?.isEndDrawerOpen == true) {
        _endDrawerWasOpenBeforeBg = true;
        s!.closeEndDrawer();
      }
      final intent = _playbackIntent;
      // Korisnikova Pauza je neopoziva — odlazak u pozadinu je ne poništava.
      if (intent != null && !intent.wantsPlayback) return;

      if (!BackgroundPlayback.instance.enabled) {
        // Pref iskljucen: pozadina znaci tisinu, isto na webu i nativeu.
        // Namjerno BEZ suppress() — ovu pauzu i zelimo upisati u namjeru, da
        // se reprodukcija ne vrati na sljedecoj framework tranziciji.
        _player?.pause();
        return;
      }

      // Pref ukljucen: pauzu koju izazove sama tranzicija (Android SurfaceView
      // teardown, browser throttling) ne smijemo procitati kao korisnikovu.
      intent?.suppress();
      // Android kill-a SurfaceView kad Video widget ode u bg pa media_kit
      // auto-pauzira. Force-play kratko nakon tranzicije — foreground service
      // iz audio_service-a drzi process zivim, pa play() prodje.
      // Web: ne force-playamo, browser sam drzi audio u pozadinskom tabu.
      if (!kIsWeb) {
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (!mounted) return;
          if (intent != null && !intent.shouldResume) return;
          _player?.play();
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_endDrawerWasOpenBeforeBg) {
        _endDrawerWasOpenBeforeBg = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _scaffoldKey.currentState?.openEndDrawer();
        });
      }
    }
  }

  /// `onEndDrawerChanged` za oba layouta (mobilni s Magisteriumom i bez njega).
  ///
  /// Zatvaranje endDrawera dispose-a `Video` widget, a media_kit na to
  /// pauzira player — bez resumea korisnik gubi zvuk na swipe-right, što je
  /// glavni mobile use case (audio dok scrollaš po članku). Zato: otvori
  /// prozor tolerancije pa nakon animacije vrati reprodukciju SAMO ako
  /// namjera i dalje postoji. Ako je korisnik prije zatvaranja stisnuo Pauzu,
  /// [PlaybackIntent.shouldResume] je false i ostaje pauzirano.
  ///
  /// Timing: Flutterov `DrawerController.close()` zove `drawerCallback(false)`
  /// odmah nakon `fling()`, dakle na POČETKU close animacije; sadržaj drawera
  /// se unmounta tek kad kontroler dođe u `dismissed`. Prozor tolerancije
  /// stignemo otvoriti prije framework pauze.
  void _onEndDrawerChanged(bool isOpen) {
    if (isOpen) return;
    // Drawer zatvaramo i sami kad app ide u pozadinu — tada o reprodukciji
    // odlučuje didChangeAppLifecycleState (poštuje i pref „u pozadini"),
    // pa ovaj handler mora šutjeti da mu ne kontrira resumeom.
    if (_endDrawerWasOpenBeforeBg) return;

    final intent = _playbackIntent;
    intent?.suppress();
    if (intent == null) return;
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      if (intent.shouldResume) _player?.play();
    });
  }

  // ---------- helpers -------------------------------------------------------

  /// Toggle handler — sticky pref + URL sync + setState rebuild kroz scope.
  void _onLanguageChanged(EpisodeLanguage lang) {
    if (lang == _language) return;
    setState(() => _language = lang);
    savePreferredLanguage(lang);
    _syncLanguageUrl(lang);
  }

  /// Update adresne trake za novi jezik bez triggera router refresha.
  /// Cuva timestamp iz playera ako je >0.
  void _syncLanguageUrl(EpisodeLanguage lang) {
    final pos = _player?.state.position ?? Duration.zero;
    final sec = pos.inSeconds;
    replaceLanguage(
      '/v/${widget.data.youtubeId}',
      isEn: lang == EpisodeLanguage.en,
      seconds: sec,
      query: _highlightQuery,
    );
    _lastUrlSyncedSec = sec;
  }

  /// Razriješi naš channel slug iz indexa po imenu kanala (info.json `channel`
  /// ↔ index.json `name`). Index se učita lazy (cache-first) pa ovo radi i na
  /// izravni deep-link na `/v/<id>` bez prethodnog posjeta homepageu.
  Future<void> _resolveChannelSlug() async {
    await channelCache.loadIndex();
    if (!mounted) return;
    final name = widget.data.info.channel;
    final id = channelCache.channelIdForName(name);
    final art = channelCache.avatarSquareForChannelName(name);
    setState(() {
      if (id != null) _channelSlug = id.replaceAll('_', '-');
      _audioArtUrl = art;
    });
  }

  /// Kandidati za kampanju kanala — fallback sticky trake "Zid podrške" kad
  /// epizoda nema vlastitu kampanju (UC… id iz info.json + naš interni
  /// channel id, čim se slug razriješi).
  List<String> get _channelSupportRefs => [
    ?widget.data.info.youtubeChannelId,
    ?_channelSlug?.replaceAll('-', '_'),
  ];

  /// Ruta punog ekrana podrške: epizodna kampanja → `/v/:id/support`,
  /// kampanja kanala (fallback) → `/c/:slug/support` (match ide po `uc`
  /// parametru pa radi i prije nego se slug razriješi).
  String _supportPath({required bool viaChannel}) {
    final data = widget.data;
    if (!viaChannel) {
      return Uri(
        path: '/v/${data.youtubeId}/support',
        queryParameters: {'name': data.displayTitle},
      ).toString();
    }
    final uc = data.info.youtubeChannelId;
    return Uri(
      path: '/c/${_channelSlug ?? 'kanal'}/support',
      queryParameters: {'uc': ?uc, 'name': data.info.channel},
    ).toString();
  }

  Duration _parseDuration(String ts) {
    // "HH:MM:SS" → Duration
    final parts = ts.split(':').map(int.parse).toList();
    if (parts.length == 3) {
      return Duration(hours: parts[0], minutes: parts[1], seconds: parts[2]);
    }
    return Duration.zero;
  }

  String _subtitleForTimestamp(String ts) {
    final article = widget.data.article;
    if (article == null) return ts;
    for (final iter in article.iterations) {
      for (final sec in iter.sections) {
        if (sec.screenshotTimestamp == ts) return sec.subtitle;
      }
    }
    return ts;
  }

  void _showResumeHint(int positionSeconds) {
    if (!mounted) return;
    _resumeHintTimer?.cancel();
    setState(() => _resumeHintSeconds = positionSeconds);
    _resumeHintTimer = Timer(_resumeHintDuration, () {
      if (mounted) setState(() => _resumeHintSeconds = null);
    });
  }

  // ---------- video ---------------------------------------------------------

  Future<void> _initVideo() async {
    final videoUri = widget.data.videoUri;
    // Nema playabilne medije (sva 3 probe-a 404) — ne pokušavaj otvoriti player
    // (izbjegava beskonačni spinner / open na prazan URI). UI ostaje graceful.
    if (!widget.data.hasMedia || videoUri.isEmpty) {
      debugPrint(
        'Video: no media for ${widget.data.youtubeId} — skipping player',
      );
      return;
    }
    // URL explicit timestamp (`/v/<id>/t/<sec>` ili `?t=`) ima prednost nad
    // saved progress-om. Inače resume na zadnju poziciju ako > 5s i ako
    // epizoda nije completed (≥ 90% rewatch konvencija — kreni od početka).
    int? startAt = widget.startAtSeconds;
    bool resumedFromSaved = false;
    if (startAt == null) {
      final saved = WatchProgressService.instance.getSync(
        widget.data.youtubeId,
      );
      if (saved != null && !saved.completed && saved.positionSeconds > 5) {
        startAt = saved.positionSeconds;
        resumedFromSaved = true;
      }
    }
    debugPrint(
      'Video: opening $videoUri'
      '${startAt != null ? ' @${startAt}s' : ''}'
      '${resumedFromSaved ? ' (resumed)' : ''}',
    );

    try {
      final player = Player();
      final controller = VideoController(player);

      // Detekcija skoka mora slušati poziciju PRIJE open/seeka — media_kit
      // streamovi su broadcast (ne replay), pa kasnija pretplata izgubi rane
      // evente.
      _seekUndo = SeekUndo(positionStream: player.stream.position);
      // Resume-seek pri otvaranju NIJE korisnikov skok. Prozor je namjerno
      // dug: `openAndResume` čeka duration (do 5 s) prije nego seekne, pa bi
      // standardnih 1,2 s isteklo prije samog skoka.
      _seekUndo!.suppress(window: const Duration(seconds: 8));

      // Otvori + pouzdano resume-seek (čeka duration prije seeka — inače libmpv
      // na iOS odbaci seek pa video kreće od 0). Ako je browser odbio unmuted
      // autoplay, helper padne na muted fallback i to zapiše u `PlayerMute`
      // singleton — odatle ga čitaju gumb za zvuk i „Uključi zvuk" CTA.
      await openAndResume(player, uri: videoUri, startAtSeconds: startAt);
      if (mounted) {
        // Otvaranje je gotovo → skrati prozor natrag na normalnu duljinu.
        _seekUndo?.suppress();
        // Zapamćena brzina (D1: globalna za uređaj) vrijedi od prve sekunde.
        await player.setRate(PlaybackSpeed.instance.rate);
      }

      _positionSub = player.stream.position.listen(_onVideoPosition);

      if (mounted) {
        // Namjera se veže tek sad: `openAndResume` je gotov, pa je
        // `state.playing` konačan odgovor je li reprodukcija uopće krenula
        // (web autoplay policy je može odbiti). Sve kasnije promjene — naši
        // gumbi, media_kitov tap-to-pause, tipkovnica, lock screen — stižu
        // kroz stream.
        _playbackIntent = PlaybackIntent(
          playingStream: player.stream.playing,
          isPlayingNow: () => player.state.playing,
          initiallyWants: player.state.playing,
        );
        setState(() {
          _player = player;
          _videoController = controller;
          _videoReady = true;
        });
        debugPrint('Video: ready');

        if (resumedFromSaved && startAt != null) {
          _showResumeHint(startAt);
        }

        // Background audio session — lock screen + notification na native, no-op na webu.
        // Artwork strategija:
        //   iOS: 1:1 channel avatar (savrseno fit u Now Playing square widget).
        //   Android: 2:1 runtime-composed slika (1:1 avatar + 16:9 thumbnail)
        //     jer Android 13+ MediaStyle crop-a u widescreen; kompozicija ispuni
        //     tile elegantno. Fallback na 1:1 avatar ili YouTube thumbnail.
        await channelCache.loadIndex();
        final channelName = widget.data.info.channel;
        final squareUrl = channelCache.avatarSquareForChannelName(channelName);
        final thumbUrl = widget.data.info.thumbnail;
        final composed = squareUrl != null
            ? await NotificationArt.composeForAndroid(
                videoId: widget.data.youtubeId,
                avatarSquareUrl: squareUrl,
                thumbnail16x9Url: thumbUrl,
              )
            : null;
        final mediaTitle = widget.data.displayTitle;
        BackgroundAudio.instance.attach(
          player: player,
          title: mediaTitle,
          artist: channelName,
          artUri: composed ?? squareUrl ?? thumbUrl,
          duration: Duration(seconds: widget.data.info.duration),
        );

        // Media Session API — web ekvivalent za background audio. Signal
        // OS-u (iOS Now Playing, Android media notification) da je tab
        // "playing media" pa audio nastavlja kad tab izgubi fokus / zaslon
        // se zaključa / korisnik prijeđe na drugi tab. No-op na native.
        MediaSession.attachMetadata(
          title: mediaTitle,
          artist: channelName,
          artUrl: squareUrl ?? thumbUrl,
        );
        MediaSession.setActionHandlers(
          onPlay: () => _player?.play(),
          onPause: () => _player?.pause(),
          onSeekTo: (pos) => _player?.seek(pos),
          onSeekBackward: (off) {
            final cur = _player?.state.position ?? Duration.zero;
            _player?.seek(cur - off);
          },
          onSeekForward: (off) {
            final cur = _player?.state.position ?? Duration.zero;
            _player?.seek(cur + off);
          },
        );
        // Track playing state → playbackState
        player.stream.playing.listen((isPlaying) {
          MediaSession.setPlaybackState(isPlaying);
        });

        // Postavi inicijalni chapter za startAt
        if (startAt != null) {
          _setInitialChapter(Duration(seconds: startAt));
        }

        // Mobile (Android/iOS/web): auto-open video endDrawer cim video postane
        // spreman. Razlog: video je autoplay (na webu možda muted zbog browser
        // policy-a, ali user vidi vizual), korisnik odmah ima video u fokusu.
        // Ako mu smeta, swipe-right zatvara endDrawer (Flutter default gesture).
        // Desktop (width > 900) ima inline video panel/stupac, ne endDrawer —
        // tu auto-open nije primjenjiv.
        if (!_endDrawerAutoOpened) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            final width = MediaQuery.sizeOf(context).width;
            // Mobile threshold — isto kao isWide u build() (width > 900).
            if (width <= 900) {
              _scaffoldKey.currentState?.openEndDrawer();
              _endDrawerAutoOpened = true;
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Video: init failed — $e');
    }
  }

  /// Postavi activeTimestamp + scrollTimestamp za inicijalnu poziciju.
  ///
  /// Re-scroll safety net: nakon initial scrolla zakažemo još 2 scrolla
  /// (300ms i 1200ms) jer ostali async content (Magisterium content, web
  /// fonts, late slike koje su tek izračunale visinu nakon prvog frame-a)
  /// mogu pomaknuti target sekciju izvan viewporta. AspectRatio rezervacija
  /// na screenshotima rješava 90% slučajeva — ovo pokriva ostatak.
  void _setInitialChapter(Duration pos) {
    String? ts;
    for (final s in _sortedSections) {
      if (pos >= s.dur) {
        ts = s.ts;
      } else {
        break;
      }
    }
    if (ts != null) {
      setState(() {
        _activeTimestamp = ts;
        _scrollTimestamp = ts;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToSection(ts!);
      });
      // Re-scroll twice da apsorbiramo late layout shifts (slike, fontovi).
      // Provjeri _lastManualScroll prije svakog poziva — ako je korisnik
      // počeo ručno scrollati, ne overrideaj.
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        if (_lastManualScroll != null) return;
        _scrollToSection(ts!);
      });
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (!mounted) return;
        if (_lastManualScroll != null) return;
        _scrollToSection(ts!);
      });
    }
  }

  void _onVideoPosition(Duration pos) {
    // URL sync na webu — adresna traka prati player na 1Hz.
    // Nema veze sa seekLockom; želimo da se address bar updatea i tijekom
    // ručno-induciranog seeka (čim novi pos stigne).
    final sec = pos.inSeconds;
    if (sec != _lastUrlSyncedSec) {
      _lastUrlSyncedSec = sec;
      replaceTimestamp(
        '/v/${widget.data.youtubeId}',
        sec,
        langSuffix: _language == EpisodeLanguage.en ? '/en' : null,
        query: _highlightQuery,
      );
      // Media Session position update — drži lock screen scrub bar u syncu.
      // Throttled na sec granularnost (isti gate kao URL sync).
      // playbackRate: bez stvarne brzine scrub bar na lock screenu ekstrapolira
      // na 1,0× i vidno drifta pri 1,5×.
      MediaSession.setPositionState(
        duration: Duration(seconds: widget.data.info.duration),
        position: pos,
        playbackRate: PlaybackSpeed.instance.rate,
      );
      // Watch progress — debounced 5s upsert u localStorage (mock).
      // v3: prosljedjujemo title + thumbnail kao denorm cache (skida sekundarni
      // CDN fetch za "Continue watching" carousel kad backend ode live).
      // Spremi CDN thumbnail URL umjesto `info.thumbnail` koji pokazuje na
      // i.ytimg.com — taj host blokira CORS, pa NetworkImage failirao kad bi
      // se rail "Nastavi slusati" pokusao renderati.
      WatchProgressService.instance.scheduleSave(
        episodeId: widget.data.youtubeId,
        positionSeconds: sec,
        durationSeconds: widget.data.info.duration,
        channelId: widget.data.info.channelId,
        episodeTitle: widget.data.displayTitle,
        episodeThumbnailUrl: CdnConfig.thumbnailUrl(widget.data.youtubeId),
      );
    }

    // Preskoči auto-sync tijekom rucnog klika na chapter
    final lock = _seekLock;
    final now = DateTime.now();
    if (lock != null && now.difference(lock) < _seekLockDuration) {
      return;
    }

    // Pronadji aktivnu sekciju: zadnja sekcija čiji timestamp <= pos
    String? newTs;
    for (final s in _sortedSections) {
      if (pos >= s.dur) {
        newTs = s.ts;
      } else {
        break;
      }
    }
    if (newTs == null || newTs == _activeTimestamp) return;

    // Sprjecava flicker: odmah nakon seekLocka, ne dopusti backward jump
    // na raniji chapter (preroll -2s uzrokuje kratki period na prethodnom).
    if (lock != null &&
        now.difference(lock) <
            _seekLockDuration + const Duration(milliseconds: 500)) {
      final currentIdx = _sortedSections.indexWhere(
        (s) => s.ts == _activeTimestamp,
      );
      final newIdx = _sortedSections.indexWhere((s) => s.ts == newTs);
      if (newIdx < currentIdx) return; // ignoriraj backward jump
    }

    // Postavi oba timestampa — video i scroll pointer syncani
    setState(() {
      _activeTimestamp = newTs!;
      _scrollTimestamp = newTs;
    });

    // Auto-scroll teksta samo ako korisnik nije ručno scrollao zadnje 2 sekunde
    final lastScroll = _lastManualScroll;
    if (lastScroll == null ||
        DateTime.now().difference(lastScroll) > const Duration(seconds: 2)) {
      _scrollLock = DateTime.now();
      _scrollToSection(newTs);
    }
  }

  // ---------- scroll --------------------------------------------------------

  void _onScroll() {
    final now = DateTime.now();
    // Ne reagiraj na programatski scroll (seek ili auto-scroll iz playbacka)
    final sLock = _seekLock;
    if (sLock != null && now.difference(sLock) < _seekLockDuration) return;
    final scLock = _scrollLock;
    if (scLock != null &&
        now.difference(scLock) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastManualScroll = now;
    _updateActiveSectionFromScroll();
  }

  void _updateActiveSectionFromScroll() {
    for (final entry in _sectionKeys.entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final pos = box.localToGlobal(Offset.zero);
      final screenH = MediaQuery.sizeOf(context).height;
      if (pos.dy >= 0 && pos.dy < screenH * 0.4) {
        if (_scrollTimestamp != entry.key) {
          setState(() => _scrollTimestamp = entry.key);
        }
        return;
      }
    }
  }

  // Alignment offset — appbar je ~56px, na tipicnom viewportu (800px) to je ~0.08.
  // Scrollamo ispod headera da chapter naslov bude jasno vidljiv.
  static const _scrollAlignment = 0.18;

  void _scrollToSection(String timestamp) {
    final ctx = _sectionKeys[timestamp]?.currentContext;
    if (ctx != null) {
      final box = ctx.findRenderObject() as RenderBox?;
      if (box != null && _scrollController.hasClients) {
        // Citamo STVARNU ekransku poziciju cilja (localToGlobal) i korigiramo
        // scroll da sjedne tocno `gap` px ispod pinned zone. Robusno naspram
        // getOffsetToReveal kvirkova (npr. in-group pinned header double-count u
        // paralelnom layoutu) i neovisno o visini ekrana.
        //
        // Pinned zona = safe-area top (SliverAppBar je primary → na mobitelu mu
        // status bar / notch povecava visinu za padding.top) + app bar; u
        // paralelnom desktop layoutu jos i sticky naslovi stupaca. Na desktopu je
        // padding.top == 0 pa je ponasanje identicno prijasnjem.
        final currentY = box.localToGlobal(Offset.zero).dy;
        final topInset = MediaQuery.paddingOf(context).top;
        const gap = 16.0;
        final pinned = _parallelActive
            ? topInset + kToolbarHeight + kParallelStickyHeaderHeight
            : topInset + kToolbarHeight;
        final desiredY = pinned + gap;
        final target = (_scrollController.offset + (currentY - desiredY)).clamp(
          0.0,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(target);
      } else {
        Scrollable.ensureVisible(
          ctx,
          duration: Duration.zero,
          alignment: _scrollAlignment,
        );
      }
    }
    _scrollMagToSection(timestamp);
  }

  void _scrollMagToSection(String timestamp) {
    final key = _magSectionKeys[timestamp];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(
        key!.currentContext!,
        duration: Duration.zero,
        alignment: _scrollAlignment,
      );
    }
  }

  /// Kad korisnik seekuje slider, uvijek scrollaj na ispravnu sekciju.
  void _onVideoSeek(Duration pos) {
    String? newTs;
    for (final s in _sortedSections) {
      if (pos >= s.dur) {
        newTs = s.ts;
      } else {
        break;
      }
    }
    if (newTs == null) return;
    setState(() => _activeTimestamp = newTs!);
    _scrollToSection(newTs);
  }

  /// Seek video na timestamp + play + scroll teksta.
  /// [preroll]: ako true, seekaj 2s prije za kontekst (samo video chapter lista).
  Future<void> _seekAndPlay(String timestamp, {bool preroll = false}) async {
    _seekLock = DateTime.now();
    // Tap na poglavlje je namjerna navigacija — Undo se NE nudi (odluka D2).
    // Prozor je 2 s jer na webu `play()` prethodi seeku pa skok može kasniti.
    _seekUndo?.suppress(window: const Duration(seconds: 2));
    // Odmah postavi oba pointera i scrollaj — ne cekaj async seek
    setState(() {
      _activeTimestamp = timestamp;
      _scrollTimestamp = timestamp;
    });
    _scrollToSection(timestamp);

    final dur = _parseDuration(timestamp);
    var seekTo = dur;
    if (preroll) {
      seekTo = dur - const Duration(seconds: 2);
      if (seekTo < Duration.zero) seekTo = Duration.zero;
    }
    if (kIsWeb) {
      await _player?.play();
      await _player?.seek(seekTo);
    } else {
      await _player?.seek(seekTo);
      await _player?.play();
    }
  }

  void _drawerTap(String timestamp) {
    _scaffoldKey.currentState?.closeDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seekAndPlay(timestamp);
    });
  }

  /// Kopira share link na trenutnu poziciju playera (path-based `/v/<id>/t/<sec>`).
  /// Ako player nije spreman ili je na ~0s, dijeli base URL bez timestampa.
  /// Worker injecta chapter-aware OG tagove na ovaj path — vidi web/_worker.js.
  void _copyMomentLink(BuildContext context, String youtubeId) {
    final pos = _player?.state.position ?? Duration.zero;
    final sec = pos.inSeconds;
    final url = sec > 5
        ? 'https://domovina.ai/v/$youtubeId/t/$sec'
        : 'https://domovina.ai/v/$youtubeId';
    Clipboard.setData(ClipboardData(text: url));
    final l = AppLocalizations.of(context);
    final label = sec > 5 ? _formatClock(sec) : l.episodeWholeEpisode;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l.episodeLinkCopied(label)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// AppBar akcija za otvaranje izvora epizode: YouTube za standardne, izvorna
  /// podcast stranica (webpage_url) za audio-only. Null kad nema URL-a.
  Widget? _sourceAction(EpisodeData data) {
    final l = AppLocalizations.of(context);
    final url = data.info.sourceUrl;
    if (url == null) return null;
    // X/Twitter izvor: `id` je sintetički pa `sourceUrl` vodi na webpage_url
    // (x.com/…/status/…) — pokaži 𝕏 oznaku, ne crvenu YouTube ikonu.
    if (data.info.isX) {
      return IconButton(
        icon: const Text('𝕏', style: TextStyle(fontSize: 18)),
        tooltip: l.episodeOpenOnX,
        onPressed: () => openUrl(url),
      );
    }
    if (data.isAudioOnly) {
      return IconButton(
        icon: const Icon(Icons.open_in_new),
        tooltip: l.commonOpenSource,
        onPressed: () => openUrl(url),
      );
    }
    return IconButton(
      icon: const Icon(Icons.smart_display, color: Color(0xFFFF0000)),
      tooltip: l.episodeOpenOnYouTube,
      onPressed: () => openUrl(url),
    );
  }

  String _formatClock(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String p(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${p(m)}:${p(s)}' : '$m:${p(s)}';
  }

  // ---------- build ---------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    // Basic path — video je dostupan ali AI pipeline jos nije producirao
    // clanak/sazetak/poglavlja. Renderiramo samo player + osnovne info.
    if (!data.hasAiContent) {
      return EpisodeLanguageScope(
        language: _language,
        hasTranslationEn: data.hasTranslationEn,
        child: _buildBasicLayout(context),
      );
    }
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > 900;
    final showVideo = _videoReady && width > 1100;
    final wantEn = _language == EpisodeLanguage.en;
    // EN je superset HR-a — kad je toggle na EN, koristi EN verzije asseta
    // (sadrze i HR polja za fallback per-field). Inace HR original.
    // hasAiContent guard gore garantira data.article != null; summary postoji
    // zajedno (pipeline ih producira u istom batchu) — pa `!` assertion.
    final summaryForUi = data.summaryFor(wantEn)!;
    final articleForUi = data.articleFor(wantEn)!;
    final magVariants = data.magisteriumVariantsFor(wantEn: wantEn);
    final magV2 = data.magisteriumFullV2For(wantEn: wantEn);
    final magPrimary = data.magisteriumPrimaryFor(wantEn: wantEn);
    final hasMag =
        magVariants.isNotEmpty ||
        data.magisteriumFull != null ||
        data.magisteriumFullPrompt != null ||
        magV2 != null;
    // Magisterium stupac: zasebni scrollable panel na širokim ekranima
    final showMagColumn = hasMag && width > 1500;
    // Paralelni prikaz: clanak i Magisterium per-sekcija jedan uz drugi u
    // dijeljenom scrollu (timestampovi poravnati). Zahtijeva per-sekcija
    // Magisterium podatke; ako epizoda ima samo V2 esej (magPrimary == null),
    // pada na klasicni magColumn (V2 esej nema per-sekcija timestampove).
    final useParallel = showMagColumn && magPrimary != null;
    _parallelActive = useParallel;
    // Mobile: bottom tabovi za switch između článka i Magisteriuma.
    // Bez ovog, Magisterium content je "zakopan" ispod dugačke article liste.
    final showMobileBottomBar = !isWide;
    final isMobileWithTabs = !isWide && hasMag;

    final appBar = _episodeAppBar(
      twoRow: width < 600,
      leading: _backLeading(context),
      title: _Breadcrumb(
        channelName: data.info.channel,
        channelSlug: _channelSlug,
        episodeTitle: data.displayTitle,
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Center(
            child: Text(
              data.info.id,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'monospace',
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        FavoriteButton(
          episodeId: data.youtubeId,
          episodeTitle: data.displayTitle,
          channelName: data.info.channel,
        ),
        if (data.hasTranslationEn)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Center(
              child: LanguageToggleChip(
                current: _language,
                onChanged: _onLanguageChanged,
                compact: true,
              ),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.share_outlined),
          tooltip: l.episodeCopyMomentLink,
          onPressed: () => _copyMomentLink(context, data.youtubeId),
        ),
        if (_sourceAction(data) != null) _sourceAction(data)!,
        ViewModeToggleButton(
          toSimple: true,
          onPressed: () async {
            await saveSimpleModePref(true);
            if (!context.mounted) return;
            final target = _language == EpisodeLanguage.en
                ? '/m/${data.youtubeId}/en'
                : '/m/${data.youtubeId}';
            // Isti sadržaj, druga prezentacija → NE novi history entry.
            swapPresentation(context, target);
          },
        ),
        if (_videoReady && !showVideo)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: const Icon(Icons.ondemand_video),
              tooltip: l.episodeVideo,
              onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
            ),
          ),
      ],
    );

    final standardContent = SliverToBoxAdapter(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HeroSection(
                info: data.info,
                youtubeId: data.youtubeId,
                summary: summaryForUi.summary,
              ),
              // Traka spomenutih osoba odmah ispod naslova. Puna sekcija
              // entiteta je na dnu članka — predaleko da se vidi tko je u
              // epizodi, i predaleko za crveni marker kad se dođe s /p/ profila.
              PeopleRail(
                summary: summaryForUi.summary,
                highlightPersonSlug: widget.highlightPersonSlug,
              ),
              // "Zid podrške" za epizodu — sam se sakrije ako epizoda nema
              // aktivnu pinka kampanju (vidi lib/pinka_sdk/). SEPA QR +
              // on-chain EURe (Gnosis Safe) + in-app DOMOVINA novčanik.
              PinkaSupportCard.episode(
                youtubeId: data.youtubeId,
                onOpen: (_) => drillDown(
                  context,
                  Uri(
                    path: '/v/${data.youtubeId}/support',
                    queryParameters: {'name': data.displayTitle},
                  ).toString(),
                ),
              ),
              if (data.hasTranslationEn)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Text(
                        l.episodeLanguageLabel,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 10),
                      LanguageToggleChip(
                        current: _language,
                        onChanged: _onLanguageChanged,
                      ),
                    ],
                  ),
                ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              SummarySection(summary: summaryForUi),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              ChaptersSection(
                outline: data.outline!,
                videoId: data.isAudioOnly ? null : data.youtubeId,
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              ArticleSection(
                article: articleForUi,
                youtubeId: data.youtubeId,
                sectionKeys: _sectionKeys,
                showScreenshot: !data.isAudioOnly,
                highlightTimestamp: _personHighlightTs,
                highlightPersonName: _personHighlightName,
                highlightSpeaks: _personHighlightSpeaks,
                onPlayTap: _videoReady
                    ? (ts) {
                        _seekAndPlay(ts, preroll: true);
                        // Na mobilu (!isWide) korisnik vidi samo text — bez
                        // drawera, klik na play je "tihi seek" bez vizuala.
                        // Otvori endDrawer s playerom da odmah vidi video.
                        // Wide mode ima video panel/stupac side-by-side
                        // pa drawer otvaranje nije potrebno.
                        if (!isWide) {
                          _scaffoldKey.currentState?.openEndDrawer();
                        }
                      }
                    : null,
                magisterium: magPrimary,
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 12),
              // Magisterium inline: samo kad NIJE prikazan kao stupac
              // i kad nismo u mobile-tab modu (tamo ima svoj zasebni tab).
              if (hasMag && !showMagColumn && !isMobileWithTabs) ...[
                if (magV2 != null)
                  MagisteriumV2View(data: magV2)
                else
                  MagisteriumPanel(
                    variants: magVariants,
                    magisteriumFull: data.magisteriumFull,
                    magisteriumFullPrompt: data.magisteriumFullPrompt,
                  ),
                Divider(height: 1, color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 12),
              ],
              EntitiesSection(
                summary: summaryForUi.summary,
                highlightPersonSlug: widget.highlightPersonSlug,
              ),
              _MetadataFooter(data: data),
            ],
          ),
        ),
      ),
    );

    // Paralelni desktop sadrzaj: hero/sazetak/poglavlja na citkoj sirini (860),
    // pa clanak ‖ Magisterium per-sekcija na siroj (dijele isti scroll →
    // timestampovi poravnati), pa entiteti/footer natrag na 860. Naslovi
    // stupaca su sticky (SliverPersistentHeader) unutar SliverMainAxisGroup-a
    // pa pinaju samo dok je paralelna zona vidljiva i otpinaju kad odscrolla.
    final List<Widget> parallelSlivers = useParallel
        ? [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HeroSection(
                        info: data.info,
                        youtubeId: data.youtubeId,
                        summary: summaryForUi.summary,
                      ),
                      // Traka osoba — vidi standardni layout iznad.
                      PeopleRail(
                        summary: summaryForUi.summary,
                        highlightPersonSlug: widget.highlightPersonSlug,
                      ),
                      // "Zid podrške" za epizodu — vidi standardni layout iznad.
                      PinkaSupportCard.episode(
                        youtubeId: data.youtubeId,
                        onOpen: (_) => drillDown(
                  context,
                          Uri(
                            path: '/v/${data.youtubeId}/support',
                            queryParameters: {'name': data.displayTitle},
                          ).toString(),
                        ),
                      ),
                      if (data.hasTranslationEn)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                          child: Row(
                            children: [
                              Text(
                                l.episodeLanguageLabel,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 10),
                              LanguageToggleChip(
                                current: _language,
                                onChanged: _onLanguageChanged,
                              ),
                            ],
                          ),
                        ),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      SummarySection(summary: summaryForUi),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      ChaptersSection(
                        outline: data.outline!,
                        videoId: data.isAudioOnly ? null : data.youtubeId,
                      ),
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            SliverMainAxisGroup(
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: ParallelColumnsStickyDelegate(
                    // Score je jezicno-neovisan; EN overlay varijanta cesto nema
                    // overall_score pa fallbackamo na HR primary score.
                    overallScore:
                        magPrimary.overallScore ??
                        data.magisteriumPrimary?.overallScore,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1500),
                      child: ParallelArticleView(
                        article: articleForUi,
                        magisterium: magPrimary,
                        youtubeId: data.youtubeId,
                        sectionKeys: _sectionKeys,
                        showScreenshot: !data.isAudioOnly,
                        highlightTimestamp: _personHighlightTs,
                        highlightPersonName: _personHighlightName,
                        highlightSpeaks: _personHighlightSpeaks,
                        onPlayTap: _videoReady
                            ? (ts) => _seekAndPlay(ts, preroll: true)
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 860),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Divider(
                        height: 1,
                        color: theme.colorScheme.outlineVariant,
                      ),
                      const SizedBox(height: 12),
                      EntitiesSection(
                summary: summaryForUi.summary,
                highlightPersonSlug: widget.highlightPersonSlug,
              ),
                      _MetadataFooter(data: data),
                    ],
                  ),
                ),
              ),
            ),
          ]
        : const [];

    final scrollBody = CustomScrollView(
      controller: _scrollController,
      slivers: useParallel
          ? [appBar, ...parallelSlivers]
          : [appBar, standardContent],
    );

    // Mobile Magisterium tab — zasebni scroll view s istim SliverAppBar patternom
    Widget? mobileMagScroll;
    if (isMobileWithTabs) {
      mobileMagScroll = CustomScrollView(
        slivers: [
          _episodeAppBar(
            twoRow: width < 600,
            leading: _backLeading(context),
            title: _Breadcrumb(
              channelName: data.info.channel,
              channelSlug: _channelSlug,
              episodeTitle: data.displayTitle,
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Center(
                  child: Text(
                    data.info.id,
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              FavoriteButton(
          episodeId: data.youtubeId,
          episodeTitle: data.displayTitle,
          channelName: data.info.channel,
        ),
              ViewModeToggleButton(
                toSimple: true,
                onPressed: () async {
                  await saveSimpleModePref(true);
                  if (!context.mounted) return;
                  swapPresentation(context, '/m/${data.youtubeId}');
                },
              ),
              if (_videoReady)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: IconButton(
                    icon: const Icon(Icons.ondemand_video),
                    tooltip: l.episodeVideo,
                    onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                  ),
                ),
            ],
          ),
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                // Preferiraj v2 view ako postoji (noviji format), inace stari Panel.
                child: magV2 != null
                    ? MagisteriumV2View(
                        data: magV2,
                        padding: const EdgeInsets.all(16),
                      )
                    : MagisteriumPanel(
                        variants: magVariants,
                        magisteriumFull: data.magisteriumFull,
                        magisteriumFullPrompt: data.magisteriumFullPrompt,
                      ),
              ),
            ),
          ),
        ],
      );
    }

    // Magisterium stupac — neovisno scrollable, blog-post stil. Samo kad NE
    // koristimo paralelni prikaz (tj. epizoda ima samo V2 esej bez per-sekcija
    // timestampova) — inace Magisterium zivi unutar scrollBody-a.
    Widget? magColumn;
    if (showMagColumn && !useParallel) {
      // V2 view nema fillParent/sectionKeys — wrappamo u SingleChildScrollView
      // da bi stupac imao vlastiti scroll, isto kao stari Panel s fillParent.
      final inner = magV2 != null
          ? SingleChildScrollView(
              child: MagisteriumV2View(
                data: magV2,
                padding: const EdgeInsets.all(20),
              ),
            )
          : MagisteriumPanel(
              variants: magVariants,
              magisteriumFull: data.magisteriumFull,
              magisteriumFullPrompt: data.magisteriumFullPrompt,
              fillParent: true,
              sectionKeys: _magSectionKeys,
            );
      magColumn = Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
        ),
        child: inner,
      );
    }

    Widget body;
    if (useParallel) {
      // Paralelni stupci zive UNUTAR scrollBody-a (dijele scroll) → nema
      // zasebnog magColumn-a. Samo TOC (+ video) okolo.
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: articleForUi,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onSectionTap: _seekAndPlay,
          ),
          Expanded(child: scrollBody),
          if (showVideo)
            VideoPanel(
              player: _player!,
              seekUndo: _seekUndo,
              youtubeId: widget.data.youtubeId,
              audioOnly: data.isAudioOnly,
              posterUrl: _audioArtUrl,
              controller: _videoController!,
              chapters: _videoChapters,
              activeTimestamp: _activeTimestamp,
              scrollTimestamp: _scrollTimestamp,
              onChapterTap: _seekAndPlay,
              onSeek: _onVideoSeek,
              totalDurationSeconds: data.info.duration,
              speakerTimeline: data.speakerTimeline,
              speakers: summaryForUi.summary.speakers,
            ),
        ],
      );
    } else if (showVideo && showMagColumn) {
      // Ultrawide: TOC | content | magisterium | video
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: articleForUi,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onSectionTap: _seekAndPlay,
          ),
          Expanded(flex: 3, child: scrollBody),
          Expanded(flex: 2, child: magColumn!),
          VideoPanel(
            player: _player!,
            seekUndo: _seekUndo,
            youtubeId: widget.data.youtubeId,
            audioOnly: data.isAudioOnly,
            posterUrl: _audioArtUrl,
            controller: _videoController!,
            chapters: _videoChapters,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onChapterTap: _seekAndPlay,
            onSeek: _onVideoSeek,
            totalDurationSeconds: data.info.duration,
            speakerTimeline: data.speakerTimeline,
            speakers: summaryForUi.summary.speakers,
          ),
        ],
      );
    } else if (showMagColumn) {
      // Wide bez videa: TOC | content | magisterium
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: articleForUi,
            activeTimestamp: _activeTimestamp,
            onSectionTap: (ts) {
              setState(() => _activeTimestamp = ts);
              _seekAndPlay(ts);
            },
          ),
          Expanded(flex: 3, child: scrollBody),
          Expanded(flex: 2, child: magColumn!),
        ],
      );
    } else if (showVideo) {
      // Desktop wide: TOC | content | video
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: articleForUi,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onSectionTap: _seekAndPlay,
          ),
          Expanded(child: scrollBody),
          VideoPanel(
            player: _player!,
            seekUndo: _seekUndo,
            youtubeId: widget.data.youtubeId,
            audioOnly: data.isAudioOnly,
            posterUrl: _audioArtUrl,
            controller: _videoController!,
            chapters: _videoChapters,
            activeTimestamp: _activeTimestamp,
            scrollTimestamp: _scrollTimestamp,
            onChapterTap: _seekAndPlay,
            onSeek: _onVideoSeek,
            totalDurationSeconds: data.info.duration,
            speakerTimeline: data.speakerTimeline,
            speakers: summaryForUi.summary.speakers,
          ),
        ],
      );
    } else if (isWide) {
      // Desktop narrow: TOC | content (bez video panela)
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TableOfContents(
            article: articleForUi,
            activeTimestamp: _activeTimestamp,
            onSectionTap: (ts) {
              setState(() => _activeTimestamp = ts);
              _seekAndPlay(ts);
            },
          ),
          Expanded(child: scrollBody),
        ],
      );
    } else if (isMobileWithTabs) {
      // Mobitel s Magisteriumom: IndexedStack — članak (tab 0) ili Magisterium (tab 1)
      body = IndexedStack(
        index: _mobileTab,
        children: [scrollBody, mobileMagScroll!],
      );
    } else {
      // Mobitel bez Magisteriuma: samo scroll content, Drawer za TOC
      body = scrollBody;
    }

    return EpisodeLanguageScope(
      language: _language,
      hasTranslationEn: data.hasTranslationEn,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: theme.colorScheme.surfaceContainerLow,
        onEndDrawerChanged: _onEndDrawerChanged,
        drawer: isWide
            ? null
            : Drawer(
                child: SafeArea(
                  child: TableOfContents(
                    article: articleForUi,
                    activeTimestamp: _activeTimestamp,
                    scrollTimestamp: _scrollTimestamp,
                    onSectionTap: _drawerTap,
                  ),
                ),
              ),
        endDrawer: _videoReady && !showVideo
            ? Drawer(
                width: 360,
                child: SafeArea(
                  child: VideoPanel(
                    player: _player!,
                    seekUndo: _seekUndo,
                    youtubeId: widget.data.youtubeId,
                    audioOnly: data.isAudioOnly,
                    posterUrl: _audioArtUrl,
                    controller: _videoController!,
                    chapters: _videoChapters,
                    activeTimestamp: _activeTimestamp,
                    onChapterTap: _seekAndPlay,
                    onSeek: _onVideoSeek,
                    totalDurationSeconds: data.info.duration,
                    speakerTimeline: data.speakerTimeline,
                    speakers: summaryForUi.summary.speakers,
                    width: null,
                  ),
                ),
              )
            : null,
        // SliverAppBar (primary: true) respektira top safe area, pa top: false.
        // Bottom: true samo kad nema bottomNavigationBara (inace bi stvorilo gap).
        body: SafeArea(
          top: false,
          bottom: !showMobileBottomBar,
          child: Stack(
            children: [
              body,
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.2),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: _resumeHintSeconds == null
                        ? const SizedBox.shrink()
                        : ResumeHintBanner(
                            key: ValueKey(_resumeHintSeconds),
                            seconds: _resumeHintSeconds!,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Dno ekrana: "gost" traka (samo neprijavljenima) + sticky "Zid
        // podrške" (sam se sakrije bez aktivne kampanje) + postojeća mobilna
        // navigacija. Donji safe area primjenjuje SAMO vanjski SafeArea —
        // pojedine trake se pale/gase pa nijedna ne zna je li najniža.
        bottomNavigationBar: SafeArea(
          top: false,
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AnonymousSignInBar(applyBottomSafeArea: false),
            PinkaSupportBar.episode(
              youtubeId: data.youtubeId,
              channelRefs: _channelSupportRefs,
              applyBottomSafeArea: false,
              onOpen: (_, viaChannel) =>
                  drillDown(context, _supportPath(viaChannel: viaChannel)),
            ),
            if (showMobileBottomBar)
              Material(
                color: theme.colorScheme.surface,
                elevation: 3,
                child: SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        _BottomBarButton(
                          icon: Icons.menu,
                          label: l.episodeContents,
                          isActive: false,
                          onTap: () {
                            final s = _scaffoldKey.currentState;
                            if (s == null) return;
                            if (s.isDrawerOpen) {
                              s.closeDrawer();
                            } else {
                              s.openDrawer();
                            }
                          },
                        ),
                        if (isMobileWithTabs) ...[
                          _BottomBarButton(
                            icon: _mobileTab == 0
                                ? Icons.article
                                : Icons.article_outlined,
                            label: l.episodeArticle,
                            isActive: _mobileTab == 0,
                            onTap: () => setState(() => _mobileTab = 0),
                          ),
                          _BottomBarButton(
                            icon: _mobileTab == 1
                                ? Icons.menu_book
                                : Icons.menu_book_outlined,
                            label: 'Magisterium',
                            isActive: _mobileTab == 1,
                            onTap: () => setState(() => _mobileTab = 1),
                          ),
                        ],
                        // Na mobitelu player živi u `endDraweru`, pa je ovo
                        // jedina površina koju korisnik vidi kad hladno otvori
                        // share link. Ako je browser nametnuo muted autoplay,
                        // gumb preuzima ulogu unmutea: tap je user gesture koji
                        // browser traži, pa zvuk pali ODMAH (i usput otvara
                        // player). Bez toga je epizoda u mrtvoj točki — vrti se
                        // bez zvuka i nema se gdje kliknuti.
                        ListenableBuilder(
                          listenable: PlayerMute.instance,
                          builder: (context, _) {
                            final blocked =
                                PlayerMute.instance.autoplayBlocked;
                            return _BottomBarButton(
                              icon: blocked
                                  ? Icons.volume_off
                                  : Icons.ondemand_video,
                              label: blocked
                                  ? l.mediaBoostVolume
                                  : l.episodeVideo,
                              isActive: blocked,
                              onTap: _videoReady
                                  ? () {
                                      if (blocked) {
                                        PlayerMute.instance.setMuted(false);
                                        if (!(_player?.state.playing ??
                                            true)) {
                                          _player?.play();
                                        }
                                      }
                                      final s = _scaffoldKey.currentState;
                                      if (s == null) return;
                                      if (s.isEndDrawerOpen) {
                                        s.closeEndDrawer();
                                      } else {
                                        s.openEndDrawer();
                                      }
                                    }
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
              ),
          ],
          ),
        ),
      ),
    );
  }

  // ---------- basic layout (video without AI pipeline content) -------------

  /// Renderiranje epizode koja jos nije prosla AI obradu — samo player +
  /// osnovne info iz info.json. Trigger: `data.hasAiContent == false`
  /// (article.json je 404 na CDN-u).
  Widget _buildBasicLayout(BuildContext context) {
    final data = widget.data;
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width > 900;
    final showVideo = _videoReady && width > 1100;
    // Ugrađeni YouTube ima smisla samo kad kod nas NEMA što pustiti — inače bi
    // na stranici bila dva playera. Sintetički ID-evi (X, ne-YT izvori) nemaju
    // YouTube video iza sebe.
    final youTubeIsTheOnlyWay =
        data.status.needsExternalSource && !data.info.isX && data.info.ytMatched;
    final embedYouTube = youTubeIsTheOnlyWay &&
        InAppYouTubePlayer.canEmbed(
          playableInEmbed: data.info.playableInEmbed,
        );
    // Web bi embed mogao, ali ga je vlasnik kanala isključio — recimo to
    // naglas umjesto da korisnika bez objašnjenja izbacimo na youtube.com.
    final embedBlocked = youTubeIsTheOnlyWay &&
        youTubeEmbedSupported &&
        !data.info.playableInEmbed;
    // Na širokom ekranu embed ide u desni stupac — na isto mjesto gdje stoji
    // `VideoPanel` kad medija postoji, pa reprodukcija uvijek živi na istoj
    // strani ekrana i ne gura status-karticu ispod pregiba.
    final showEmbedPanel = embedYouTube && !showVideo && width > 1100;

    final scrollBody = CustomScrollView(
      controller: _scrollController,
      slivers: [
        _episodeAppBar(
          twoRow: width < 600,
          leading: _backLeading(context),
          title: _Breadcrumb(
            channelName: data.info.channel,
            channelSlug: _channelSlug,
            episodeTitle: data.displayTitle,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Center(
                child: Text(
                  data.info.id,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            FavoriteButton(
          episodeId: data.youtubeId,
          episodeTitle: data.displayTitle,
          channelName: data.info.channel,
        ),
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: l.episodeCopyMomentLink,
              onPressed: () => _copyMomentLink(context, data.youtubeId),
            ),
            if (_sourceAction(data) != null) _sourceAction(data)!,
            if (_videoReady && !showVideo)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: IconButton(
                  icon: const Icon(Icons.ondemand_video),
                  tooltip: l.episodeVideo,
                  onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
                ),
              ),
          ],
        ),
        SliverToBoxAdapter(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    HeroSection(info: data.info, youtubeId: data.youtubeId),
                    const SizedBox(height: 20),
                    // In-app YouTube player — jedina reprodukcija kad medije
                    // kod nas nema (faza `queued`/`fetched`). Facade, pa
                    // iframe krene tek na korisnikov tap.
                    if (embedYouTube && !showEmbedPanel) ...[
                      InAppYouTubePlayer(
                        videoId: data.youtubeId,
                        posterUrl: CdnConfig.thumbnailUrl(data.youtubeId),
                      ),
                      const SizedBox(height: 20),
                    ],
                    EpisodeStatusCard(
                      status: data.status,
                      audioOnly: data.isAudioOnly,
                    ),
                    const SizedBox(height: 16),
                    // Primarna radnja slijedi FAZU, ne izvor: kad je medija
                    // kod nas, korisnika vodimo u naš player. Na uskom ekranu
                    // je player u endDraweru, pa bez ovog gumba na mobitelu
                    // nema vidljivog načina da se epizoda uopće pusti — dosad
                    // je i takva epizoda nudila samo odlazak na YouTube.
                    if (_videoReady && !showVideo)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () =>
                              _scaffoldKey.currentState?.openEndDrawer(),
                          icon: Icon(
                            data.isAudioOnly
                                ? Icons.headphones
                                : Icons.play_arrow,
                          ),
                          label: Text(
                            data.isAudioOnly
                                ? l.episodeListen
                                : l.episodeWatchOurPlayer,
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    // X/Twitter izvor: sintetički `id` — NIKAD YouTube link.
                    // Vodi na izvorni X post (webpage_url).
                    if (data.info.isX && data.info.sourceUrl != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => openUrl(data.info.sourceUrl!),
                          icon: const Text('𝕏', style: TextStyle(fontSize: 18)),
                          label: Text(l.episodeOpenOnX),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      )
                    // Odlazak na YouTube nosi crveni naglasak SAMO kad je
                    // doista jedini put do reprodukcije. Kad epizodu možemo
                    // pustiti sami (embed na stranici ili naš player), spušta
                    // se na tihu poveznicu da ne konkurira primarnoj radnji.
                    else if (!data.info.isX && data.info.ytMatched)
                      Padding(
                        padding: EdgeInsets.only(top: _videoReady ? 8 : 0),
                        child: SizedBox(
                          width: double.infinity,
                          child: (embedYouTube || _videoReady)
                              ? TextButton.icon(
                                  onPressed: () => openUrl(
                                    'https://www.youtube.com/watch?v=${data.youtubeId}',
                                  ),
                                  icon: const Icon(Icons.open_in_new, size: 18),
                                  label: Text(l.episodeOpenOnYouTube),
                                )
                              : FilledButton.icon(
                                  onPressed: () => openUrl(
                                    'https://www.youtube.com/watch?v=${data.youtubeId}',
                                  ),
                                  icon: const Icon(Icons.smart_display),
                                  label: Text(l.episodeWatchOnYouTube),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF0000),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                  ),
                                ),
                        ),
                      )
                    else if (data.info.sourceUrl != null)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => openUrl(data.info.sourceUrl!),
                          icon: const Icon(Icons.open_in_new),
                          label: Text(l.commonOpenSource),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    if (embedBlocked)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          l.episodeEmbedBlocked,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    Widget body;
    if (showEmbedPanel) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: scrollBody),
          _YouTubeSidePanel(youtubeId: data.youtubeId),
        ],
      );
    } else if (showVideo) {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: scrollBody),
          VideoPanel(
            player: _player!,
            seekUndo: _seekUndo,
            youtubeId: widget.data.youtubeId,
            audioOnly: data.isAudioOnly,
            posterUrl: _audioArtUrl,
            controller: _videoController!,
            chapters: const [],
            onChapterTap: (_) {},
            onSeek: _onVideoSeek,
            totalDurationSeconds: data.info.duration,
            speakerTimeline: data.speakerTimeline,
          ),
        ],
      );
    } else {
      body = scrollBody;
    }

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      onEndDrawerChanged: _onEndDrawerChanged,
      endDrawer: _videoReady && !showVideo
          ? Drawer(
              width: 360,
              child: SafeArea(
                child: VideoPanel(
                  player: _player!,
                  seekUndo: _seekUndo,
                  youtubeId: widget.data.youtubeId,
                  audioOnly: data.isAudioOnly,
                  posterUrl: _audioArtUrl,
                  controller: _videoController!,
                  chapters: const [],
                  onChapterTap: (_) {},
                  onSeek: _onVideoSeek,
                  totalDurationSeconds: data.info.duration,
                  speakerTimeline: data.speakerTimeline,
                  width: null,
                ),
              ),
            )
          : null,
      body: SafeArea(
        top: false,
        bottom: !isWide,
        child: Stack(
          children: [
            body,
            Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, -0.2),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _resumeHintSeconds == null
                      ? const SizedBox.shrink()
                      : ResumeHintBanner(
                          key: ValueKey(_resumeHintSeconds),
                          seconds: _resumeHintSeconds!,
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
      // "Gost" traka + sticky "Zid podrške" iznad (opcionalne) mobilne
      // navigacije — vidi standardni layout gore.
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const AnonymousSignInBar(applyBottomSafeArea: false),
          PinkaSupportBar.episode(
            youtubeId: data.youtubeId,
            channelRefs: _channelSupportRefs,
            applyBottomSafeArea: false,
            onOpen: (_, viaChannel) =>
                drillDown(context, _supportPath(viaChannel: viaChannel)),
          ),
          if (!isWide)
            Material(
              color: theme.colorScheme.surface,
              elevation: 3,
              child: SizedBox(
                  height: 64,
                  child: Row(
                    children: [
                      _BottomBarButton(
                        icon: Icons.ondemand_video,
                        label: l.episodeVideo,
                        isActive: false,
                        onTap: _videoReady
                            ? () {
                                final s = _scaffoldKey.currentState;
                                if (s == null) return;
                                if (s.isEndDrawerOpen) {
                                  s.closeEndDrawer();
                                } else {
                                  s.openEndDrawer();
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
            ),
        ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _MetadataFooter extends StatelessWidget {
  final EpisodeData data;

  const _MetadataFooter({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    // Footer se renderira samo iz full layout-a, koji je guarded
    // `data.hasAiContent` granom na vrhu _EpisodeContent.build() — pa su
    // summary/article ovdje garantirano non-null.
    final summary = data.summary!;
    final article = data.article!;

    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.episodeMetadata,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          _MetaRow('YouTube ID', data.info.id),
          _MetaRow(l.episodeMetaChannel, data.info.channel),
          _MetaRow(l.episodeMetaModelSummary, summary.model),
          _MetaRow(l.episodeMetaModelArticle, article.metadata.model),
          if (data.magisteriumPrimary != null)
            _MetaRow(
              l.episodeMetaModelTheology,
              data.magisteriumPrimary!.model,
            ),
          _MetaRow(
            l.episodeMetaGenerated,
            summary.generatedAt.toIso8601String().substring(0, 10),
          ),
          _MetaRow(
            l.episodeMetaLanguage,
            summary.summary.language.toUpperCase(),
          ),
          _MetaRow(l.episodeMetaContentType, summary.summary.contentType),
          _MetaRow(l.episodeMetaSentiment, summary.summary.sentiment),
        ],
      ),
    );
  }
}

class _BottomBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color color;
    if (onTap == null) {
      color = theme.colorScheme.onSurfaceVariant.withAlpha(80);
    } else if (isActive) {
      color = theme.colorScheme.primary;
    } else {
      color = theme.colorScheme.onSurfaceVariant;
    }

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;

  const _MetaRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Episode SliverAppBar s responsivnim rasporedom akcija. Na mobitelu
/// (twoRow=true) breadcrumb ostaje u gornjem redu, a akcije se sele u drugi red
/// (bottom) — inače se breadcrumb + 6-7 akcija prelijeva na uskom ekranu i
/// "većina buttona se ne vidi". Akcije u drugom redu su desno-poravnate i
/// horizontalno skrolabilne (touch), pa nikad ne overflowaju. Desktop/tablet:
/// akcije inline kao prije.
/// [leading] je gumb ← i postoji SAMO kad ima što popati.
///
/// Do 6.9.2026. epizoda nije imala gumb „nazad" uopće (`automaticallyImplyLeading:
/// false`, samo breadcrumb), pa na iOS-u — gdje edge-swipe ne radi jer stog nije
/// postojao — nije bilo izlaza osim breadcrumba „Početna", koji je na uskom
/// ekranu često bio odscrollan izvan vidljivog. `automaticallyImplyLeading`
/// ostaje `false` jer bi Flutterov ugrađeni ← ignorirao `titleSpacing: 0` koji
/// breadcrumb treba.
/// Gumb ← samo kad postoji stog. Bez njega breadcrumb ostaje jedini izlaz, a
/// `titleSpacing: 0` puni rub — pa se ne troši mjesto na prazan slot.
Widget? _backLeading(BuildContext context) {
  if (!context.canPop()) return null;
  return IconButton(
    icon: const Icon(Icons.arrow_back),
    tooltip: AppLocalizations.of(context).commonBack,
    onPressed: () => back(context),
  );
}

SliverAppBar _episodeAppBar({
  required Widget title,
  required List<Widget> actions,
  required bool twoRow,
  Widget? leading,
}) {
  return SliverAppBar(
    pinned: true,
    automaticallyImplyLeading: false,
    leading: leading,
    // 0 jer _Breadcrumb nosi vlastiti rubni padding (na mobitelu kao content
    // padding UNUTAR horizontalnog scrolla — vidi komentar u _Breadcrumb).
    titleSpacing: leading == null ? 0 : null,
    title: title,
    actions: twoRow ? null : actions,
    bottom: twoRow
        ? PreferredSize(
            preferredSize: const Size.fromHeight(46),
            child: SizedBox(
              height: 46,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: actions),
              ),
            ),
          )
        : null,
  );
}
