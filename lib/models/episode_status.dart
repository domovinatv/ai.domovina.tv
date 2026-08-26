import '../l10n/app_localizations.dart';
import 'channel_detail.dart' show VideoPipeline;

/// Faza obrade jedne epizode, onako kako je korisnik vidi.
///
/// Pipeline ima desetak koraka, ali korisniku su smisleni samo prijelazi koji
/// mijenjaju **što može učiniti** s epizodom: može li je uopće otvoriti, može
/// li je pustiti kod nas, i ima li tekstualni sloj (sažetak/članak/analizu).
/// Zato pet faza, ne deset.
///
/// **Rule**: faza se izvodi iz IZMJERENOG stanja CDN-a ([EpisodeStatus.measured]),
/// ne iz `pipeline` zastavica u channel listingu. Listing je producentova
/// namjera i zna kasniti za stvarnošću u oba smjera — izmjereno 26.8.2026.:
/// `DnzG2OvRflI` ima `video_h264.mp4` na CDN-u uz `has_transcript:false`, a
/// `UclibQB3SZM` ima listinganu `thumbnail` putanju koja vraća 404. Listing
/// vantage ([EpisodeStatus.fromPipeline]) postoji samo za railove, gdje nemamo
/// ništa bolje i gdje je oznaka meka informacija.
enum EpisodeStage {
  /// Ništa nije kod nas — ni `info.json`. Epizodu znamo isključivo iz channel
  /// listinga (yt-dlp je registrirao video, ali ga preuzimanje još nije
  /// dohvatilo, ili je palo). Jedina reprodukcija je YouTube.
  queued,

  /// `info.json` postoji, medija ne. Imamo naslov, opis, trajanje i sličicu,
  /// ali ni `video_h264.mp4` ni `audio.mp3` ni legacy `video.mp4`.
  fetched,

  /// Medija je na CDN-u i može se pustiti kod nas, ali tekstualnog sloja nema.
  mediaReady,

  /// Prijepis (ili sažetak) postoji, članak još ne.
  transcribed,

  /// Članak postoji — epizoda ima puni layout. Ovo stanje UI status-karticom
  /// ne komunicira; postoji da je enum potpun i da railovi znaju "gotovo".
  published,
}

/// Jedan korak u vidljivoj listi napretka.
enum EpisodeStep { fetch, media, transcript, summary, article, magisterium }

/// Stanje pojedinog koraka. [active] je korak koji je na redu — ne znamo radi
/// li se baš sad, ali je prvi neispunjeni, pa ga tako i prikazujemo.
enum EpisodeStepState { done, active, pending }

/// Izvedeni status epizode: faza + lista koraka s njihovim stanjem.
class EpisodeStatus {
  final EpisodeStage stage;
  final Map<EpisodeStep, EpisodeStepState> steps;

  /// True kad je stanje izvedeno iz stvarnih CDN probe-ova, a ne iz listinga.
  final bool measured;

  /// True kad [stage] doista nešto tvrdi. Listing zna samo za tekstualne
  /// artefakte — kad su sve zastavice false, epizoda je *negdje* između „u redu
  /// čekanja" i „prepisujemo", a koje od toga se iz listinga NE MOŽE znati.
  /// Tada je ovo false i [badge] šuti umjesto da pogodi.
  final bool stageCertain;

  const EpisodeStatus({
    required this.stage,
    required this.steps,
    required this.measured,
    this.stageCertain = true,
  });

  /// Status iz IZMJERENOG stanja — ono što je episode screen doista dohvatio.
  ///
  /// [hasMedia] dolazi iz `DataService.resolveMedia()` probe-a, ostalo iz
  /// prisutnosti pojedinog JSON-a/SRT-a.
  factory EpisodeStatus.measured({
    required bool hasInfo,
    required bool hasMedia,
    required bool hasTranscript,
    required bool hasSummary,
    required bool hasArticle,
    required bool hasMagisterium,
  }) {
    // Prijepis ne može postojati bez preuzetog zvuka — ako ga imamo, medija je
    // bila tu i kad probe trenutno kaže suprotno (npr. transcode u tijeku).
    final mediaDone = hasMedia || hasTranscript;
    final stage = !hasInfo
        ? EpisodeStage.queued
        : hasArticle
            ? EpisodeStage.published
            : (hasTranscript || hasSummary)
                ? EpisodeStage.transcribed
                : mediaDone
                    ? EpisodeStage.mediaReady
                    : EpisodeStage.fetched;

    return EpisodeStatus(
      stage: stage,
      measured: true,
      steps: _steps([
        hasInfo,
        mediaDone,
        hasTranscript,
        hasSummary,
        hasArticle,
        hasMagisterium,
      ]),
    );
  }

  /// Status iz channel listinga (`pipeline` zastavice). Slabiji vantage: o
  /// `info.json`-u i mediji listing ne zna **ništa** — nema zastavicu za njih.
  /// Koristi se za oznake na karticama u railovima, gdje probe nije izvediv.
  ///
  /// **Rule**: kad nijedna zastavica nije podignuta, faza se NE pogađa
  /// ([stageCertain] je false, [badge] vraća null i call-site padne na neutralno
  /// „U obradi"). Prva izvedba je u tom slučaju tvrdila „Preuzimamo" i time na
  /// naslovnici svakoj epizodi u railu zalijepila istu, uglavnom netočnu
  /// oznaku — izmjereno 26.8.2026.: 12 od 20 tih epizoda imalo je mediju na
  /// CDN-u, dakle bile su dvije faze dalje.
  factory EpisodeStatus.fromPipeline(VideoPipeline? p) {
    final hasTranscript = (p?.hasTranscript ?? false) || (p?.hasDiarized ?? false);
    final hasSummary = p?.hasSummary ?? false;
    final hasArticle = p?.hasArticle ?? false;
    final derived = EpisodeStatus.measured(
      hasInfo: true,
      hasMedia: hasTranscript,
      hasTranscript: hasTranscript,
      hasSummary: hasSummary,
      hasArticle: hasArticle,
      hasMagisterium: p?.hasMagisterium ?? false,
    );
    return EpisodeStatus(
      stage: derived.stage,
      steps: derived.steps,
      measured: false,
      // Samo podignuta zastavica nosi informaciju; njihov izostanak ne nosi.
      stageCertain: hasTranscript || hasSummary || hasArticle,
    );
  }

  static Map<EpisodeStep, EpisodeStepState> _steps(List<bool> done) {
    final order = EpisodeStep.values;
    final map = <EpisodeStep, EpisodeStepState>{};
    var activeAssigned = false;
    for (var i = 0; i < order.length; i++) {
      if (done[i]) {
        map[order[i]] = EpisodeStepState.done;
      } else if (!activeAssigned) {
        map[order[i]] = EpisodeStepState.active;
        activeAssigned = true;
      } else {
        map[order[i]] = EpisodeStepState.pending;
      }
    }
    return map;
  }

  /// Kratka oznaka za karticu u railu / channel listingu ("U redu čekanja",
  /// "Prepisujemo", …). Null za [EpisodeStage.published] — gotova epizoda ne
  /// nosi oznaku.
  String? badge(AppLocalizations l) {
    if (!stageCertain) return null;
    switch (stage) {
      case EpisodeStage.queued:
        return l.episodeStageQueuedBadge;
      case EpisodeStage.fetched:
        return l.episodeStageFetchedBadge;
      case EpisodeStage.mediaReady:
        return l.episodeStageMediaReadyBadge;
      case EpisodeStage.transcribed:
        return l.episodeStageTranscribedBadge;
      case EpisodeStage.published:
        return null;
    }
  }

  /// Naslov status-kartice na episode ekranu.
  String headline(AppLocalizations l) {
    switch (stage) {
      case EpisodeStage.queued:
        return l.episodeStageQueuedHeadline;
      case EpisodeStage.fetched:
        return l.episodeStageFetchedHeadline;
      case EpisodeStage.mediaReady:
        return l.episodeStageMediaReadyHeadline;
      case EpisodeStage.transcribed:
        return l.episodeStageTranscribedHeadline;
      case EpisodeStage.published:
        return l.episodeStagePublishedHeadline;
    }
  }

  /// Objašnjenje ispod naslova — što je kod nas, što još nije, i što korisnik
  /// u međuvremenu MOŽE (pustiti kod nas / gledati s YouTubea).
  String body(AppLocalizations l, {required bool audioOnly}) {
    switch (stage) {
      case EpisodeStage.queued:
        return l.episodeStageQueuedBody;
      case EpisodeStage.fetched:
        return l.episodeStageFetchedBody;
      case EpisodeStage.mediaReady:
        return audioOnly
            ? l.episodeStageMediaReadyBodyAudio
            : l.episodeStageMediaReadyBodyVideo;
      case EpisodeStage.transcribed:
        return l.episodeStageTranscribedBody;
      case EpisodeStage.published:
        return l.episodeStagePublishedBody;
    }
  }

  /// True kad epizoda kod nas nema što pustiti — UI tada mora ponuditi izvor
  /// (YouTube embed na webu, vanjska poveznica na nativeu) umjesto playera.
  bool get needsExternalSource =>
      stage == EpisodeStage.queued || stage == EpisodeStage.fetched;
}

/// Naziv koraka u listi napretka.
String episodeStepLabel(EpisodeStep step, AppLocalizations l) {
  switch (step) {
    case EpisodeStep.fetch:
      return l.episodeStepFetch;
    case EpisodeStep.media:
      return l.episodeStepMedia;
    case EpisodeStep.transcript:
      return l.episodeStepTranscript;
    case EpisodeStep.summary:
      return l.episodeStepSummary;
    case EpisodeStep.article:
      return l.episodeStepArticle;
    case EpisodeStep.magisterium:
      return l.episodeStepMagisterium;
  }
}
