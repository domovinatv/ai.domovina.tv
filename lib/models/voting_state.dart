/// Stanje glasača (`domovina_ai.my_voting_state()`) + **čista projekcija niza**
/// iz plana §6.3.
///
/// Plan: `docs/plans/2026-08-08-glasanje-o-kanalima.md` §5.2, §6.3, §6.4.
///
/// Server je jedini izvor istine: on računa izborni dan (`Europe/Zagreb`),
/// upisuje niz i troši zastavice. Funkcije u ovom fajlu **repliciraju isti
/// izraz** samo zato da UI između dva mrežna poziva može odmah prikazati
/// posljedicu tapa (optimistički update) i da se stanje iz lokalnog cachea ne
/// prikazuje kao svježe. Nikad ne postaju izvor istine — `cast_vote` odgovor
/// uvijek pregazi projekciju.
library;

import 'dart:math' as math;

import 'vote_round.dart';

/// Maksimalan broj zastavica koje glasač može držati (Brilliant: 2, §2.1).
const int kMaxVoteFlags = 2;

/// Današnji glas iz `my_voting_state().today_vote` (null dok se nije glasalo).
class TodayVote {
  final String slug;

  /// `1` = 👍, `-1` = 👎.
  final int direction;

  const TodayVote({required this.slug, required this.direction});

  bool get isUp => direction > 0;

  static TodayVote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final slug = raw['slug'] as String? ?? '';
    if (slug.isEmpty) return null;
    final dir = raw['direction'];
    return TodayVote(
      slug: slug,
      direction: dir is int ? dir : int.tryParse('${dir ?? ''}') ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {'slug': slug, 'direction': direction};
}

/// Trajni dio glasačeva stanja nad kojim radi projekcija iz §6.3.
class StreakSnapshot {
  final int streak;
  final int longestStreak;
  final int flags;
  final DateTime? lastVoteDay;

  const StreakSnapshot({
    this.streak = 0,
    this.longestStreak = 0,
    this.flags = 0,
    this.lastVoteDay,
  });

  StreakSnapshot copyWith({
    int? streak,
    int? longestStreak,
    int? flags,
    DateTime? lastVoteDay,
  }) =>
      StreakSnapshot(
        streak: streak ?? this.streak,
        longestStreak: longestStreak ?? this.longestStreak,
        flags: flags ?? this.flags,
        lastVoteDay: lastVoteDay ?? this.lastVoteDay,
      );
}

/// Rezultat projekcije **pri čitanju** (§6.3, „Pri čitanju") — ništa se ne upisuje.
class StreakDisplay {
  /// Broj propuštenih izbornih dana: `D - L - 1`, nikad negativan.
  final int missedDays;

  final bool votedToday;

  /// Zadnji dan u kojem zastavice još mogu obraniti niz.
  final bool streakAtRisk;

  /// Niz kakav se smije prikazati — 0 kad je već pukao, a korisnik to još ne zna.
  final int displayedStreak;

  /// Koliko bi zastavica izgorjelo kad bi se glasalo sada.
  final int flagsThatWillBurn;

  const StreakDisplay({
    required this.missedDays,
    required this.votedToday,
    required this.streakAtRisk,
    required this.displayedStreak,
    required this.flagsThatWillBurn,
  });

  /// Niz je pukao, a korisnik danas još nije glasao (stanje 5 iz §8.2).
  bool get streakBroken => !votedToday && displayedStreak == 0 && missedDays > 0;
}

/// Rezultat projekcije **pri glasanju** (§6.3, „Pri glasanju").
class StreakCast {
  /// Novo stanje niza nakon glasa.
  final StreakSnapshot snapshot;

  /// Koliko je zastavica potrošeno da se niz spasi (0 ako nije trebalo ili
  /// nije bilo dovoljno — troši se **sve-ili-ništa**, §6.3).
  final int flagsBurned;

  /// Zastavice su spasile niz od pucanja.
  final bool streakSaved;

  /// Niz je pukao i krenuo od 1.
  final bool streakBroken;

  /// Za taj izborni dan glas već postoji — projekcija je no-op, a server bi
  /// vratio `already_voted_today` (tiho poravnanje, ne greška).
  final bool alreadyVotedToday;

  const StreakCast({
    required this.snapshot,
    this.flagsBurned = 0,
    this.streakSaved = false,
    this.streakBroken = false,
    this.alreadyVotedToday = false,
  });
}

/// Broj propuštenih izbornih dana između zadnjeg glasa i danas: `D - L - 1`.
///
/// Bez zadnjeg glasa (prvi glas ikad) nema propuštenih dana. Negativan rezultat
/// (zadnji glas „u budućnosti" — stari cache, pomaknut sat) se prigušuje na 0;
/// server je autoritet i sljedeći `my_voting_state()` ionako poravna stanje.
int missedVoteDays({required DateTime today, DateTime? lastVoteDay}) {
  if (lastVoteDay == null) return 0;
  return math.max(0, voteDaysBetween(lastVoteDay, today) - 1);
}

/// Projekcija za **prikaz** — isti izraz kao `my_voting_state()`, bez upisa.
///
/// Odstupanje od doslovnog izraza u §6.3: `streak_at_risk` traži i `streak > 0`.
/// Bez toga bi glasač koji nikad nije glasao (L = null → missed 0, flags 0)
/// prošao uvjet `missed == flags` i UI bi mu ponudio stanje „niz visi" nad
/// nizom od nula dana — obrana nečega što ne postoji.
StreakDisplay projectStreakForDisplay({
  required DateTime today,
  required StreakSnapshot snapshot,
}) {
  final last = snapshot.lastVoteDay;
  final votedToday = last != null && !last.isBefore(today);
  final missed = missedVoteDays(today: today, lastVoteDay: last);
  final saveable = missed <= snapshot.flags;

  return StreakDisplay(
    missedDays: missed,
    votedToday: votedToday,
    streakAtRisk: !votedToday && snapshot.streak > 0 && missed == snapshot.flags,
    displayedStreak: votedToday
        ? snapshot.streak
        : (saveable ? snapshot.streak : 0),
    flagsThatWillBurn: !votedToday && saveable ? missed : 0,
  );
}

/// Projekcija za **glasanje** — replicira prijelaz koji `cast_vote` radi u bazi.
///
/// ```
/// L == null           → niz 1
/// missed == 0         → niz + 1                     (uzastopno)
/// missed <= flags     → flags -= missed; niz + 1     (SPAŠENO)
/// inače               → niz 1; zastavice ostaju      (PUKNUO, §6.3)
/// pa: flags = min(2, flags + 1), longest = max(longest, niz), L = D
/// ```
StreakCast projectStreakForVote({
  required DateTime today,
  required StreakSnapshot snapshot,
}) {
  final last = snapshot.lastVoteDay;

  // Glas za taj dan već postoji (dupli tap, druga kartica) → ništa se ne mijenja.
  if (last != null && !last.isBefore(today)) {
    return StreakCast(snapshot: snapshot, alreadyVotedToday: true);
  }

  final missed = missedVoteDays(today: today, lastVoteDay: last);

  int streak;
  int flags = snapshot.flags;
  var burned = 0;
  var saved = false;
  var broken = false;

  if (last == null) {
    streak = 1;
  } else if (missed == 0) {
    streak = snapshot.streak + 1;
  } else if (missed <= flags) {
    flags -= missed;
    burned = missed;
    saved = true;
    streak = snapshot.streak + 1;
  } else {
    // Zastavice se NE troše kad ne mogu spasiti niz (§6.3, odstupanje od Brilliant-a).
    streak = 1;
    broken = true;
  }

  flags = math.min(kMaxVoteFlags, flags + 1);

  return StreakCast(
    snapshot: StreakSnapshot(
      streak: streak,
      longestStreak: math.max(snapshot.longestStreak, streak),
      flags: flags,
      lastVoteDay: today,
    ),
    flagsBurned: burned,
    streakSaved: saved,
    streakBroken: broken,
  );
}

/// Projekcija koju vraća `domovina_ai.my_voting_state()` (§5.2).
///
/// Polja su preslikana **doslovno** iz tog JSON-a; ništa se ne izvodi pri
/// parsiranju da se ne bi razišlo sa serverom.
class VotingState {
  /// Identitet potvrđen e-Osobnom (`app_metadata.kyc_verified`).
  final bool verified;

  /// Prihvaćena privola iz §4.3 („ovo nije tajno glasovanje").
  final bool consented;

  final bool votedToday;

  /// Današnji izborni dan po hrvatskom vremenu — **serverov** datum.
  final DateTime? today;

  final int streak;
  final int longestStreak;
  final int flags;
  final bool streakAtRisk;
  final int flagsThatWillBurn;
  final DateTime? lastVoteDay;
  final TodayVote? todayVote;
  final VoteRound? round;

  const VotingState({
    this.verified = false,
    this.consented = false,
    this.votedToday = false,
    this.today,
    this.streak = 0,
    this.longestStreak = 0,
    this.flags = 0,
    this.streakAtRisk = false,
    this.flagsThatWillBurn = 0,
    this.lastVoteDay,
    this.todayVote,
    this.round,
  });

  /// Smije li korisnik uopće glasati (gate prije tapa; server ponavlja provjeru).
  bool get canVote => verified && !votedToday;

  /// Fali samo privola — prvi glas otvara jednokratni ekran iz §4.3.
  bool get needsConsent => verified && !consented;

  StreakSnapshot get snapshot => StreakSnapshot(
        streak: streak,
        longestStreak: longestStreak,
        flags: flags,
        lastVoteDay: lastVoteDay,
      );

  /// Lokalna projekcija za prikaz. [now] je izborni dan za koji se prikazuje;
  /// bez njega se uzima serverov `today`.
  ///
  /// **Za stanje iz cachea proslijedi [now]**: server je projekciju izračunao
  /// za *svoj* dan, a korisnik je aplikaciju možda otvorio dan kasnije. Zadnji
  /// fallback je lokalni sat — jedini slučaj u kojem klijent uopće dira datum,
  /// i to samo dok prvi `my_voting_state()` ne odgovori (§6.2).
  StreakDisplay display([DateTime? now]) => projectStreakForDisplay(
        today: now ?? today ?? DateTime.now(),
        snapshot: snapshot,
      );

  /// Optimističko stanje odmah nakon tapa na 👍/👎 — vrijedi dok `cast_vote`
  /// ne vrati pravo stanje (ili dok se ne napravi rollback).
  VotingState applyOptimisticVote({
    required String slug,
    required int direction,
    DateTime? on,
  }) {
    final day = on ?? today;
    if (day == null) return this;
    final cast = projectStreakForVote(today: day, snapshot: snapshot);
    if (cast.alreadyVotedToday) return this;
    return copyWith(
      votedToday: true,
      today: day,
      streak: cast.snapshot.streak,
      longestStreak: cast.snapshot.longestStreak,
      flags: cast.snapshot.flags,
      streakAtRisk: false,
      flagsThatWillBurn: 0,
      lastVoteDay: cast.snapshot.lastVoteDay,
      todayVote: TodayVote(slug: slug, direction: direction),
    );
  }

  VotingState copyWith({
    bool? verified,
    bool? consented,
    bool? votedToday,
    DateTime? today,
    int? streak,
    int? longestStreak,
    int? flags,
    bool? streakAtRisk,
    int? flagsThatWillBurn,
    DateTime? lastVoteDay,
    TodayVote? todayVote,
    VoteRound? round,
  }) =>
      VotingState(
        verified: verified ?? this.verified,
        consented: consented ?? this.consented,
        votedToday: votedToday ?? this.votedToday,
        today: today ?? this.today,
        streak: streak ?? this.streak,
        longestStreak: longestStreak ?? this.longestStreak,
        flags: flags ?? this.flags,
        streakAtRisk: streakAtRisk ?? this.streakAtRisk,
        flagsThatWillBurn: flagsThatWillBurn ?? this.flagsThatWillBurn,
        lastVoteDay: lastVoteDay ?? this.lastVoteDay,
        todayVote: todayVote ?? this.todayVote,
        round: round ?? this.round,
      );

  factory VotingState.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v, [int fallback = 0]) =>
        v is int ? v : int.tryParse('${v ?? ''}') ?? fallback;
    bool asBool(Object? v) => v == true || v == 'true';

    final roundJson = json['round'];
    return VotingState(
      verified: asBool(json['verified']),
      consented: asBool(json['consented']),
      votedToday: asBool(json['voted_today']),
      today: parseVoteDay(json['today']),
      streak: asInt(json['streak']),
      longestStreak: asInt(json['longest_streak']),
      flags: asInt(json['flags']),
      streakAtRisk: asBool(json['streak_at_risk']),
      flagsThatWillBurn: asInt(json['flags_that_will_burn']),
      lastVoteDay: parseVoteDay(json['last_vote_day']),
      todayVote: TodayVote.fromJson(json['today_vote']),
      round: roundJson is Map
          ? VoteRound.fromJson(roundJson.cast<String, dynamic>())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'verified': verified,
        'consented': consented,
        'voted_today': votedToday,
        'today': today == null ? null : formatVoteDay(today!),
        'streak': streak,
        'longest_streak': longestStreak,
        'flags': flags,
        'streak_at_risk': streakAtRisk,
        'flags_that_will_burn': flagsThatWillBurn,
        'last_vote_day': lastVoteDay == null ? null : formatVoteDay(lastVoteDay!),
        'today_vote': todayVote?.toJson(),
        'round': round?.toJson(),
      };
}
