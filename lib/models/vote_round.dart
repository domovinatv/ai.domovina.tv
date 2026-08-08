/// Kolo glasanja („Izborni dan", `domovina_ai.vote_rounds`) i aritmetika
/// **izbornog dana**.
///
/// Plan: `docs/plans/2026-08-08-glasanje-o-kanalima.md` §5, §6.2, §7;
/// RPC ugovor **v1.1** iz `2026-08-08-glasanje-predaja.md` (nadjačava §5.2).
///
/// Dva oblika istog kola stižu s dvije strane:
/// * `current_round()` → `{id, starts_on, ends_on, status, days_left, today,
///   quorum_net, quorum_total, total_votes, voters}`
/// * `my_voting_state().round` → `{id, starts_on, ends_on, days_left}`
///
/// Zato je sve osim `id` opcionalno — kraća projekcija ne smije izgubiti model.
///
/// **Izborni dan je datum, ne trenutak.** Granicu dana računa isključivo
/// Postgres (`(now() at time zone 'Europe/Zagreb')::date`) — klijent nikad ne
/// šalje ni izmišlja datum, samo radi aritmetiku nad datumima koje je dobio od
/// servera (§6.2). Zato su svi datumi ovdje normalizirani na **UTC ponoć**:
/// `DateTime(2026, 3, 29)` u lokalnoj zoni s ljetnim pomakom traje 23 h pa bi
/// `difference(...).inDays` preskočio dan preko DST prijelaza.
library;

/// Status kola (mirror DB check constrainta).
enum VoteRoundStatus {
  open,
  closed,
  unknown;

  static VoteRoundStatus fromJson(String? raw) => switch (raw) {
        'open' => VoteRoundStatus.open,
        'closed' => VoteRoundStatus.closed,
        _ => VoteRoundStatus.unknown,
      };
}

/// Razlog zatvaranja kola bez pobjednika (§7.2).
const String kNoWinnerQuorumNotMet = 'quorum_not_met';

final RegExp _voteDayPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})');

/// Datum izbornog dana iz `YYYY-MM-DD` (ili punog ISO timestampa), normaliziran
/// na UTC ponoć. Vraća null za prazan/neispravan zapis — pokvaren datum znači
/// „ne znam", nikad pad ekrana.
///
/// **Uzima se datum kako je napisan, bez ijedne konverzije zone.** Server je
/// datum već izračunao po `Europe/Zagreb` (§6.2); `DateTime.parse` bi
/// `2026-08-09T00:00:01+02:00` pretvorio u UTC i vratio **8.8.** — klijent bi
/// tako sam sebi pomaknuo izborni dan, upravo ono što §6.2 zabranjuje.
DateTime? parseVoteDay(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) return DateTime.utc(raw.year, raw.month, raw.day);
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  final match = _voteDayPattern.firstMatch(text);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  return DateTime.utc(year, month, day);
}

/// `YYYY-MM-DD` zapis izbornog dana (isti oblik koji server šalje).
String formatVoteDay(DateTime day) {
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '${day.year.toString().padLeft(4, '0')}-$m-$d';
}

/// Broj cijelih dana od [from] do [to] (negativan ako je [to] u prošlosti).
/// Ulazi se normaliziraju na UTC ponoć pa DST ne može pomaknuti rezultat.
int voteDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Zadani kvorum iz §7.2 — koristi se samo kad kolo ne nosi vlastite vrijednosti
/// (kolone `quorum_net` / `quorum_total` su konfigurabilne bez migracije).
const int kDefaultQuorumNet = 10;
const int kDefaultQuorumTotal = 25;

class VoteRound {
  final int id;

  /// Prvi izborni dan kola. `current_round()` ga nosi; skraćena projekcija u
  /// `my_voting_state().round` (§5.2) ga nema.
  final DateTime? startsOn;

  /// Zadnji izborni dan kola — **uključivo** (§5).
  final DateTime? endsOn;

  final VoteRoundStatus status;
  final String? winnerSlug;
  final DateTime? closedAt;

  /// `'quorum_not_met'` kad je kolo zatvoreno bez pobjednika (§7.2).
  final String? noWinnerReason;

  final int? quorumNet;
  final int? quorumTotal;

  /// `days_left` iz `my_voting_state().round` — server ga računa po hrvatskom
  /// danu. Kad ga nema, izvedi ga preko [daysLeftOn].
  final int? daysLeft;

  /// Serverov današnji izborni dan (`current_round().today`). Jedini datum
  /// kojem klijent smije vjerovati kad još nema `my_voting_state()` — npr.
  /// gost koji gleda ljestvicu bez sesije.
  final DateTime? today;

  /// Ukupno glasova u kolu (transparentnost iz §4.2 / §11.3).
  final int? totalVotes;

  /// Broj glasača u kolu.
  final int? voters;

  const VoteRound({
    required this.id,
    this.startsOn,
    this.endsOn,
    this.status = VoteRoundStatus.open,
    this.winnerSlug,
    this.closedAt,
    this.noWinnerReason,
    this.quorumNet,
    this.quorumTotal,
    this.daysLeft,
    this.today,
    this.totalVotes,
    this.voters,
  });

  bool get isOpen => status == VoteRoundStatus.open;

  /// Zatvoreno kolo bez pobjednika — tally se prenosi u sljedeće (§7.2).
  bool get hasNoWinner =>
      status == VoteRoundStatus.closed && (winnerSlug ?? '').isEmpty;

  int get effectiveQuorumNet => quorumNet ?? kDefaultQuorumNet;
  int get effectiveQuorumTotal => quorumTotal ?? kDefaultQuorumTotal;

  /// Preostali dani do kraja kola, uključujući današnji. Na zadnji dan kola je
  /// **0**, dan poslije negativan.
  int daysLeftOn(DateTime today) {
    if (endsOn == null) return daysLeft ?? 0;
    return voteDaysBetween(today, endsOn!);
  }

  /// Prima li kolo glas na dan [today].
  ///
  /// §6.4: glas na dan kad kolo završava ulazi u **to** kolo, ne u sljedeće —
  /// `ends_on` je uključiv.
  bool acceptsVotesOn(DateTime today) {
    if (!isOpen) return false;
    if (endsOn == null) return true;
    return !today.isAfter(endsOn!);
  }

  factory VoteRound.fromJson(Map<String, dynamic> json) {
    int? asInt(Object? v) => v is int ? v : int.tryParse('${v ?? ''}');
    return VoteRound(
      id: asInt(json['id']) ?? 0,
      startsOn: parseVoteDay(json['starts_on']),
      endsOn: parseVoteDay(json['ends_on']),
      status: VoteRoundStatus.fromJson(json['status'] as String?),
      winnerSlug: json['winner_slug'] as String?,
      closedAt: json['closed_at'] == null
          ? null
          : DateTime.tryParse('${json['closed_at']}'),
      noWinnerReason: json['no_winner_reason'] as String?,
      quorumNet: asInt(json['quorum_net']),
      quorumTotal: asInt(json['quorum_total']),
      daysLeft: asInt(json['days_left']),
      today: parseVoteDay(json['today']),
      totalVotes: asInt(json['total_votes']),
      voters: asInt(json['voters']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (startsOn != null) 'starts_on': formatVoteDay(startsOn!),
        if (endsOn != null) 'ends_on': formatVoteDay(endsOn!),
        'status': status.name,
        if (winnerSlug != null) 'winner_slug': winnerSlug,
        if (closedAt != null) 'closed_at': closedAt!.toIso8601String(),
        if (noWinnerReason != null) 'no_winner_reason': noWinnerReason,
        if (quorumNet != null) 'quorum_net': quorumNet,
        if (quorumTotal != null) 'quorum_total': quorumTotal,
        if (daysLeft != null) 'days_left': daysLeft,
        if (today != null) 'today': formatVoteDay(today!),
        if (totalVotes != null) 'total_votes': totalVotes,
        if (voters != null) 'voters': voters,
      };
}
