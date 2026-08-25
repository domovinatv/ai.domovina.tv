/// „Izborni dan" — data sloj glasanja o sljedećem kanalu.
///
/// Plan: `docs/plans/2026-08-08-glasanje-o-kanalima.md` §6.3, §8.5.
/// RPC ugovor: **v1.1** iz `docs/plans/2026-08-08-glasanje-predaja.md`
/// (nadjačava dizajn §5.2).
///
/// **Zašto singleton `ChangeNotifier`, a ne stanje u ekranu**: niz i zastavice
/// se crtaju na tri odvojena stabla (home app bar chip, `/glasanje`, `/account`),
/// pa bi prop drilling stanje negdje ispustio — isti razlog kao `PlaybackSpeed`
/// i `PlayerMute` (CLAUDE.md, „stanje kontrole ide kroz singleton").
///
/// Sav pristup bazi ide kroz RPC-eve u `domovina_ai` shemi: `voters` i `votes`
/// nemaju **nijednu** client RLS policy (§5.1), a izborni dan računa isključivo
/// Postgres (§6.2) — klijent nikad ne šalje datum.
///
/// Lokalni cache zadnjeg stanja ide kroz `local_prefs.dart`
/// (`window.localStorage` na webu; `SharedPreferences` puca u dart2js release
/// buildu — CLAUDE.md).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../main.dart' show log;
import '../models/vote_candidate.dart';
import '../models/vote_round.dart';
import '../models/voting_state.dart';
import 'auth_service.dart';
import 'local_prefs.dart';

/// Cache zadnjeg poznatog `my_voting_state()` odgovora (prikaz do prvog
/// mrežnog odgovora, ne izvor istine).
const String kVotingStateCacheKey = 'voting_state_v1';

/// Imena RPC-eva iz §5.2.
const String kRpcMyVotingState = 'my_voting_state';
const String kRpcCastVote = 'cast_vote';
const String kRpcRoundLeaderboard = 'round_leaderboard';
const String kRpcCurrentRound = 'current_round';
const String kRpcAcceptVotingTerms = 'accept_voting_terms';

/// Imena parametara — ugovor **v1.1** (`p_` prefiks, konvencija repoa):
/// `cast_vote(p_slug, p_direction)`,
/// `round_leaderboard(p_round_id, p_sort, p_tag, p_limit, p_offset, p_query)`.
/// `my_voting_state()`, `current_round()` i `accept_voting_terms()` su bez
/// parametara.
const String kParamSlug = 'p_slug';
const String kParamDirection = 'p_direction';
const String kParamRoundId = 'p_round_id';
const String kParamSort = 'p_sort';
const String kParamTag = 'p_tag';
const String kParamLimit = 'p_limit';
const String kParamOffset = 'p_offset';

/// Pretraga po nazivu kandidata (v1.1, opcionalno — default `null`).
const String kParamQuery = 'p_query';

/// Strojni kodovi grešaka iz ugovora. Server ih diže kao
/// `raise exception '<kod>'`, a PostgREST ih vrati kao HTTP 400 s tijelom
/// `{"code":"P0001","message":"<kod>"}` → čitamo **`message`** (ugovor v1.1 t.7).
enum VotingErrorCode {
  /// Identitet nije potvrđen e-Osobnom → UI vodi u Certilia flow.
  notVerified('not_verified'),

  /// Privola iz §4.3 nije prihvaćena → jednokratni ekran prije prvog glasa.
  termsNotAccepted('terms_not_accepted'),

  /// Za današnji izborni dan glas već postoji. **Nije greška** — tiho
  /// poravnanje stanja (dupli tap, druga kartica, drugi uređaj).
  alreadyVotedToday('already_voted_today'),

  /// Kandidat je u međuvremenu izašao iz igre (pobjednik, povučen).
  candidateNotAvailable('candidate_not_available'),

  /// Kolo je zatvoreno dok je ekran stajao otvoren.
  roundClosed('round_closed'),

  /// Mreža/baza nedostupna — nije semantička greška glasanja.
  unavailable('unavailable'),

  unknown('unknown');

  const VotingErrorCode(this.wire);

  final String wire;

  /// Poravnanje stanja umjesto poruke o grešci (§8.5).
  bool get isSilentAlignment => this == VotingErrorCode.alreadyVotedToday;

  static VotingErrorCode fromWire(String? raw) {
    if (raw == null || raw.isEmpty) return VotingErrorCode.unknown;
    for (final code in VotingErrorCode.values) {
      if (raw == code.wire || raw.contains(code.wire)) return code;
    }
    return VotingErrorCode.unknown;
  }
}

/// Greška glasanja. Nosi **strojni kod**, ne lokalizirani tekst — copy je u
/// ARB-u i razrješava ga UI (`voting*` ključevi), servis ne dira i18n.
class VotingFailure implements Exception {
  final VotingErrorCode code;

  /// Tehnički detalj za log; nikad se ne prikazuje korisniku doslovno.
  final String detail;

  const VotingFailure(this.code, [this.detail = '']);

  @override
  String toString() => 'VotingFailure(${code.wire}${detail.isEmpty ? '' : ': $detail'})';
}

/// Ishod `cast_vote` — novo stanje + što se dogodilo s nizom, da UI može
/// animirati potrošenu zastavicu (§5.2).
class CastVoteOutcome {
  final VotingState state;

  /// Koliko je zastavica izgorjelo (`flags_burned`).
  final int flagsBurned;

  /// Jesu li zastavice spasile niz (`streak_saved`).
  final bool streakSaved;

  /// Server je javio `already_voted_today` — stanje je poravnato, glas nije
  /// upisan i UI ne prikazuje grešku.
  final bool alreadyVotedToday;

  const CastVoteOutcome({
    required this.state,
    this.flagsBurned = 0,
    this.streakSaved = false,
    this.alreadyVotedToday = false,
  });
}

class VotingService extends ChangeNotifier {
  static final VotingService instance = VotingService._();
  VotingService._();

  VotingState? _state;
  VoteRound? _round;
  List<VoteCandidate> _candidates = const [];

  VoteSort _sort = VoteSort.leaderboard;
  String? _tag;
  String? _query;

  List<String> _tags = const [];

  /// Kratki javni izvadak ljestvice za home rail (§8.6).
  ///
  /// Namjerno **odvojen** od [_candidates]: rail traži 10 redaka, a
  /// `/glasanje` cijelu ljestvicu (100). Da dijele isto polje, prvi bi dohvat
  /// pobijedio i drugi ekran bi ostao na krivom broju kandidata —
  /// `ensureLoaded()` na drugom ulasku vraća već dovršeni Future i ne bi
  /// ponovno dohvatio ništa.
  List<VoteCandidate> _preview = const [];
  Future<void>? _previewLoading;

  bool _loadingState = false;
  bool _loadingCandidates = false;
  bool _cacheRead = false;
  Future<void>? _loading;

  VotingErrorCode? _lastError;

  /// Zadnje poznato stanje glasača (iz cachea dok mreža ne odgovori).
  VotingState? get state => _state;

  /// Aktivno kolo — `current_round()`, uz `my_voting_state().round` kao dopunu.
  VoteRound? get round => _round ?? _state?.round;

  /// Trenutna ljestvica (redoslijed kakav je server vratio — ne presortiravamo).
  List<VoteCandidate> get candidates => _candidates;

  VoteSort get sort => _sort;
  String? get tag => _tag;
  String? get query => _query;

  /// Teme za filter chipove, izvedene iz **nefiltriranog** dohvata ljestvice.
  ///
  /// Živi u servisu, ne u ekranu: `ensureLoaded()` na drugom ulasku vraća već
  /// dovršeni Future i **ne notifira**, pa bi popis izračunat u `State`-u ostao
  /// prazan i cijeli red chipova bi nestao. Ovdje preživljava ekran.
  ///
  /// Računa se jednom — da se osvježavao pri svakoj promjeni filtera, odabir
  /// taga bi pojeo sve ostale chipove (lista tada nosi samo taj tag) i korisnik
  /// se ne bi imao čime vratiti; a promjena sorta bi im preslagala redoslijed
  /// pod prstom.
  List<String> get tags => _tags;

  /// Serverov današnji izborni dan — iz stanja glasača, pa iz kola. Klijent ga
  /// nikad ne izmišlja iz vlastitog sata (§6.2).
  DateTime? get today => _state?.today ?? round?.today;

  bool get isLoading => _loadingState || _loadingCandidates;

  /// Kod zadnje greške; `null` kad je zadnja radnja prošla.
  VotingErrorCode? get lastError => _lastError;

  /// Ima li korisnik neiskorišten glas — signal za crvenu točku na home chipu.
  bool get hasUnusedVote => _state?.canVote ?? false;

  /// Vrh ljestvice za home rail — prazno dok [ensurePreviewLoaded] ne odgovori
  /// (rail se tada sam sakrije).
  List<VoteCandidate> get previewCandidates => _preview;

  /// Prikazna projekcija niza za [now] (default: serverov `today`).
  StreakDisplay? displayFor([DateTime? now]) => _state?.display(now);

  // ---------------------------------------------------------------------------
  // Učitavanje
  // ---------------------------------------------------------------------------

  /// Idempotentno — višestruki pozivi dijele isti Future.
  Future<void> ensureLoaded() => _loading ??= refresh();

  /// Osvježi kolo i stanje glasača. Nikad ne baca: greška se zabilježi u
  /// [lastError] i UI ostaje na zadnjem poznatom stanju.
  Future<void> refresh({bool withLeaderboard = true}) async {
    if (!_cacheRead) await primeFromCache();
    _loadingState = true;
    notifyListeners();
    try {
      await Future.wait([_fetchRound(), _fetchState()]);
      _lastError = null;
    } on VotingFailure catch (e) {
      _lastError = e.code;
    } catch (e) {
      _lastError = VotingErrorCode.unavailable;
      log('VotingService.refresh failed: $e');
    } finally {
      _loadingState = false;
      notifyListeners();
    }
    if (withLeaderboard) await loadLeaderboard();
  }

  /// Vrh ljestvice za home rail. Idempotentno; višestruki pozivi dijele Future.
  ///
  /// **Javno i bez sesije** — `round_leaderboard` je `anon` RPC, pa rail radi i
  /// za gosta koji nikad nije vidio da glasanje postoji (to mu je i svrha).
  /// `p_round_id` se namjerno NE šalje: server sam razriješi otvoreno kolo, pa
  /// rail košta **jedan** RPC umjesto `current_round()` + ljestvica.
  ///
  /// Nikad ne baca i nikad ne dira [lastError] — pad ove trake ne smije
  /// obojati `/glasanje` porukom o grešci; rail jednostavno ostane skriven.
  Future<void> ensurePreviewLoaded({int limit = 10}) =>
      _previewLoading ??= _loadPreview(limit);

  /// Sjemenovanje raila u testu — proizvodni kod uvijek ide kroz
  /// [ensurePreviewLoaded] (widget testovi nemaju Supabase klijenta).
  @visibleForTesting
  void debugSetPreview(List<VoteCandidate> candidates) {
    _preview = List.unmodifiable(candidates);
    _previewLoading = Future<void>.value();
    notifyListeners();
  }

  Future<void> _loadPreview(int limit) async {
    try {
      final result = await _rpc(kRpcRoundLeaderboard, params: {
        kParamSort: VoteSort.leaderboard.wire,
        kParamLimit: limit,
        kParamOffset: 0,
      });
      if (result is List) {
        _preview = result
            .whereType<Map>()
            .map((e) => VoteCandidate.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        notifyListeners();
      }
    } catch (e) {
      log('VotingService.ensurePreviewLoaded failed: $e');
    }
  }

  Future<void> _fetchRound() async {
    final result = await _rpc(kRpcCurrentRound);
    if (result is Map) {
      _round = VoteRound.fromJson(result.cast<String, dynamic>());
    }
  }

  Future<void> _fetchState() async {
    // Ljestvica je javna, stanje glasača nije — bez sesije nema što tražiti.
    if (!AuthService.instance.isSignedIn) {
      _state = null;
      return;
    }
    final result = await _rpc(kRpcMyVotingState);
    if (result is Map) {
      _state = VotingState.fromJson(result.cast<String, dynamic>());
      _writeCache();
    }
  }

  /// Ljestvica kola. [sort], [tag] i [query] se pamte da ih osvježavanje ne
  /// izgubi; [clearTag] / [clearQuery] su jedini način da se filter makne
  /// (prosljeđivanje `null` znači „ostavi kako je").
  Future<void> loadLeaderboard({
    VoteSort? sort,
    String? tag,
    String? query,
    bool clearTag = false,
    bool clearQuery = false,
    int limit = 100,
    int offset = 0,
  }) async {
    _sort = sort ?? _sort;
    _tag = clearTag ? null : (tag ?? _tag);
    final trimmed = query?.trim();
    // Prazan upit briše pretragu; izostavljen (`null`) je ostavlja kakva jest.
    _query = clearQuery
        ? null
        : (trimmed == null ? _query : (trimmed.isEmpty ? null : trimmed));
    _loadingCandidates = true;
    notifyListeners();
    try {
      final result = await _rpc(kRpcRoundLeaderboard, params: {
        kParamRoundId: round?.id,
        kParamSort: _sort.wire,
        kParamTag: _tag,
        kParamLimit: limit,
        kParamOffset: offset,
        kParamQuery: _query,
      });
      if (result is List) {
        _candidates = result
            .whereType<Map>()
            .map((e) => VoteCandidate.fromJson(e.cast<String, dynamic>()))
            .toList(growable: false);
        _rebuildTags();
        _lastError = null;
      }
    } catch (e) {
      _lastError = VotingErrorCode.unavailable;
      log('VotingService.loadLeaderboard failed: $e');
    } finally {
      _loadingCandidates = false;
      notifyListeners();
    }
  }

  /// Najčešće teme iz trenutne (nefiltrirane) ljestvice, silazno po učestalosti.
  ///
  /// Filtriran dohvat se preskače: kad je tag postavljen, lista nosi samo taj
  /// tag i popis bi se sveo na jedan chip bez povratka.
  void _rebuildTags({int limit = 14}) {
    if (_tags.isNotEmpty) return;
    if (_tag != null || (_query ?? '').isNotEmpty) return;
    if (_candidates.isEmpty) return;
    final brojac = <String, int>{};
    for (final c in _candidates) {
      for (final t in c.tags) {
        brojac[t] = (brojac[t] ?? 0) + 1;
      }
    }
    final sortirani = brojac.keys.toList()
      ..sort((a, b) {
        final razlika = brojac[b]!.compareTo(brojac[a]!);
        return razlika != 0 ? razlika : a.compareTo(b);
      });
    _tags = sortirani.take(limit).toList(growable: false);
  }

  // ---------------------------------------------------------------------------
  // Glasanje
  // ---------------------------------------------------------------------------

  /// Potroši današnji glas na [slug] u smjeru [direction] (`1` 👍 / `-1` 👎).
  ///
  /// Optimistički pomiče niz i tally odmah po tapu, pa ih vrati na staro ako
  /// RPC padne. `already_voted_today` **ne** baca: stanje se tiho poravna sa
  /// serverom (§8.5) i ishod nosi [CastVoteOutcome.alreadyVotedToday].
  Future<CastVoteOutcome> castVote({
    required String slug,
    required int direction,
  }) async {
    if (direction != kVoteDirectionUp && direction != kVoteDirectionDown) {
      throw ArgumentError.value(direction, 'direction', 'mora biti 1 ili -1');
    }

    final previousState = _state;
    final previousCandidates = _candidates;

    _state = _state?.applyOptimisticVote(
      slug: slug,
      direction: direction,
      on: today,
    );
    _candidates = _candidates
        .map((c) => c.slug == slug ? c.withOptimisticVote(direction) : c)
        .toList(growable: false);
    notifyListeners();

    try {
      final result = await _rpc(kRpcCastVote, params: {
        kParamSlug: slug,
        kParamDirection: direction,
      });
      final json = (result as Map).cast<String, dynamic>();
      _state = VotingState.fromJson(json);
      _round = _state?.round ?? _round;
      _lastError = null;
      _writeCache();
      // Tallyji u railu su od ovog trenutka stariji od ljestvice — sljedeći
      // ulazak na home ih ponovno dohvati (novi `State` sam zove
      // `ensurePreviewLoaded`, a bez ovoga bi dobio dovršeni Future).
      _previewLoading = null;
      notifyListeners();
      return CastVoteOutcome(
        state: _state!,
        flagsBurned: _asInt(json['flags_burned']),
        streakSaved: json['streak_saved'] == true,
      );
    } catch (e) {
      // Rollback optimističkog pomaka — na SVAKU grešku, i na tiho poravnanje:
      // glas nije upisan sada (ili je upisan ranije, možda na drugog
      // kandidata), pa lokalni +1 ne smije ostati. Hvatamo široko jer bi
      // neuhvaćena iznimka (parsiranje, mreža) ostavila lažni +1 na ekranu.
      _state = previousState;
      _candidates = previousCandidates;

      final failure = e is VotingFailure
          ? e
          : VotingFailure(VotingErrorCode.unavailable, '$e');
      _lastError = failure.code;

      if (failure.code.isSilentAlignment) {
        _lastError = null;
        await refresh(withLeaderboard: false);
        return CastVoteOutcome(
          state: _state ?? previousState ?? const VotingState(),
          alreadyVotedToday: true,
        );
      }

      notifyListeners();
      log('cast_vote failed: $failure');
      throw failure;
    }
  }

  /// Privola iz §4.3 — jednokratno, prije prvog glasa.
  Future<void> acceptTerms() async {
    await _rpc(kRpcAcceptVotingTerms);
    _state = _state?.copyWith(consented: true);
    _writeCache();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // RPC + mapiranje grešaka
  // ---------------------------------------------------------------------------

  Future<Object?> _rpc(String fn, {Map<String, dynamic>? params}) async {
    final client = _client;
    if (client == null) {
      throw const VotingFailure(VotingErrorCode.unavailable, 'no supabase client');
    }
    try {
      final cleaned = params == null
          ? null
          : {
              for (final e in params.entries)
                if (e.value != null) e.key: e.value,
            };
      final result =
          await client.schema('domovina_ai').rpc(fn, params: cleaned);
      // RPC koji vrati `{"error": "<kod>"}` umjesto da digne iznimku.
      if (result is Map && result['error'] is String) {
        throw VotingFailure(
            VotingErrorCode.fromWire(result['error'] as String), fn);
      }
      return result;
    } on sb.PostgrestException catch (e) {
      log('$fn RPC failed: ${e.code} ${e.message}');
      throw VotingFailure(_mapPostgrest(e), '${e.code}: ${e.message}');
    }
  }

  sb.SupabaseClient? get _client {
    try {
      return sb.Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Mapiranje po ugovoru v1.1 t.7: `raise exception '<kod>'` iz plpgsql-a
  /// dolazi kao HTTP 400 s tijelom `{"code":"P0001","message":"<kod>"}` →
  /// **strojni kod je u `message`, ne u `code`**.
  ///
  /// `code` je Postgresov SQLSTATE i namjerno se NE gleda kao izvor semantike:
  /// `42501` / `401` znače da `execute` pravo na RPC-u fali (greška u
  /// migraciji/deployu), a ne da s glasanjem nešto nije u redu — takvo se
  /// stanje mora vidjeti kao neočekivana greška, ne prešutjeti.
  static VotingErrorCode _mapPostgrest(sb.PostgrestException e) {
    if (e.code == '42501' || e.code == '401' || e.code == '403') {
      log('voting: nedostaje execute pravo na RPC-u (${e.code}) — provjeri '
          'grant execute u migraciji');
      return VotingErrorCode.unknown;
    }
    return VotingErrorCode.fromWire(e.message);
  }

  static int _asInt(Object? v) =>
      v is int ? v : int.tryParse('${v ?? ''}') ?? 0;

  // ---------------------------------------------------------------------------
  // Lokalni cache (local_prefs — nikad SharedPreferences na webu)
  // ---------------------------------------------------------------------------

  /// Dekodiraj spremljeno stanje. Vraća `null` kad je zapis pokvaren ili kad
  /// pripada **drugom** računu.
  ///
  /// Provjera računa nije kozmetika: `voter` preživljava brisanje računa
  /// (§4.1), pa isti uređaj može redom nositi dva različita `user_id`-a —
  /// niz iz tuđeg/starog zapisa nikad se ne smije prikazati kao svoj. Pravi
  /// niz svejedno stiže s prvim `my_voting_state()` odgovorom.
  @visibleForTesting
  static VotingState? decodeCachedState(String? raw, {String? userId}) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final envelope = jsonDecode(raw);
      if (envelope is! Map) return null;
      final owner = envelope['user_id'] as String?;
      if (owner == null || owner.isEmpty || owner != userId) return null;
      final state = envelope['state'];
      if (state is! Map) return null;
      return VotingState.fromJson(state.cast<String, dynamic>());
    } catch (e) {
      log('voting: neispravan cache zapis ($e)');
      return null;
    }
  }

  @visibleForTesting
  static String encodeCachedState(VotingState state, {String? userId}) =>
      jsonEncode({
        'v': 1,
        'user_id': userId,
        'state': state.toJson(),
      });

  /// Prikaži zadnje poznato stanje prije nego mreža odgovori. [refresh] je zove
  /// sam; ekran je smije pozvati ranije (u `initState`) za trenutni paint.
  ///
  /// Web čita `window.localStorage` sinkrono, native `SharedPreferences`
  /// asinkrono — pa je i ovdje API asinkron (CLAUDE.md: nikad
  /// `SharedPreferences` na webu).
  Future<void> primeFromCache() async {
    if (_cacheRead || _state != null) {
      _cacheRead = true;
      return;
    }
    _cacheRead = true;
    final raw = kIsWeb
        ? getLocalStorageString(kVotingStateCacheKey)
        : (await SharedPreferences.getInstance())
            .getString(kVotingStateCacheKey);
    final cached = decodeCachedState(
      raw,
      userId: AuthService.instance.currentUser?.id,
    );
    if (cached != null) {
      _state = cached;
      notifyListeners();
    }
  }

  void _writeCache() {
    final state = _state;
    if (state == null) return;
    final raw = encodeCachedState(
      state,
      userId: AuthService.instance.currentUser?.id,
    );
    if (kIsWeb) {
      setLocalStorageString(kVotingStateCacheKey, raw);
      return;
    }
    SharedPreferences.getInstance()
        .then((p) => p.setString(kVotingStateCacheKey, raw))
        .catchError((Object e) {
      log('voting: cache write failed ($e)');
      return false;
    });
  }

  /// Test hook: vrati servis u početno stanje.
  @visibleForTesting
  void debugReset() {
    _state = null;
    _round = null;
    _candidates = const [];
    _sort = VoteSort.leaderboard;
    _tag = null;
    _query = null;
    _tags = const [];
    _lastError = null;
    _cacheRead = false;
    _loading = null;
    _loadingState = false;
    _loadingCandidates = false;
  }
}
