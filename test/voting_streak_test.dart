/// Projekcija niza („streak") za glasanje o kanalima.
///
/// Pokriva **svih 10 rubnih slučajeva iz §6.4** dizajn dokumenta
/// `docs/plans/2026-08-08-glasanje-o-kanalima.md`. Server (T1) ima vlastiti SQL
/// scenarij nad istim slučajevima; ovdje se testira **klijentska replika** iz
/// §6.3 — ista aritmetika kojom UI prikazuje stanje između dva mrežna poziva i
/// odmah po tapu (optimistički update).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/models/vote_candidate.dart';
import 'package:domovina_ai/models/vote_round.dart';
import 'package:domovina_ai/models/voting_state.dart';
import 'package:domovina_ai/services/voting_service.dart';

/// Izborni dan u kolovozu 2026. (UTC ponoć — vidi `parseVoteDay`).
DateTime day(int d) => DateTime.utc(2026, 8, d);

StreakSnapshot snap({
  int streak = 0,
  int longest = 0,
  int flags = 0,
  int? lastDay,
}) =>
    StreakSnapshot(
      streak: streak,
      longestStreak: longest,
      flags: flags,
      lastVoteDay: lastDay == null ? null : day(lastDay),
    );

void main() {
  // ===========================================================================
  // §6.4 — deset rubnih slučajeva
  // ===========================================================================

  group('§6.4 rubni slučajevi', () {
    test('1. prvi glas ikad → niz 1, zastavice 1', () {
      final cast = projectStreakForVote(today: day(8), snapshot: snap());

      expect(cast.snapshot.streak, 1);
      expect(cast.snapshot.flags, 1);
      expect(cast.snapshot.longestStreak, 1);
      expect(cast.snapshot.lastVoteDay, day(8));
      expect(cast.flagsBurned, 0);
      expect(cast.streakSaved, isFalse);
      expect(cast.streakBroken, isFalse);
    });

    test('2. glas u 23:59:59 pa u 00:00:01 → dva izborna dana, niz 2', () {
      // Granicu dana računa Postgres; klijent vidi samo dva različita datuma.
      final prvi = projectStreakForVote(today: day(8), snapshot: snap());
      final drugi =
          projectStreakForVote(today: day(9), snapshot: prvi.snapshot);

      expect(prvi.snapshot.streak, 1);
      expect(drugi.snapshot.streak, 2);
      expect(drugi.snapshot.flags, 2);
      expect(drugi.flagsBurned, 0);
      expect(drugi.streakBroken, isFalse);
    });

    test('2b. isti trenutak s obje strane ponoći ne pomiče dan sam od sebe', () {
      // 23:59:59 i 00:00:01 istog kalendarskog dana po hrvatskom vremenu ostaju
      // JEDAN izborni dan — parseVoteDay reže vrijeme.
      expect(parseVoteDay('2026-08-08T23:59:59+02:00'), day(8));
      expect(parseVoteDay('2026-08-09T00:00:01+02:00'), day(9));
      expect(voteDaysBetween(day(8), day(9)), 1);
    });

    test('3. dupli tap → druga projekcija je no-op (already_voted_today)', () {
      final prvi = projectStreakForVote(today: day(8), snapshot: snap());
      final drugi =
          projectStreakForVote(today: day(8), snapshot: prvi.snapshot);

      expect(drugi.alreadyVotedToday, isTrue);
      expect(drugi.snapshot.streak, prvi.snapshot.streak);
      expect(drugi.snapshot.flags, prvi.snapshot.flags);
      expect(drugi.flagsBurned, 0);

      // I tally se ne smije duplirati: optimistički update se ne primjenjuje.
      final state = VotingState(
        verified: true,
        consented: true,
        votedToday: true,
        today: day(8),
        streak: 1,
        flags: 1,
        lastVoteDay: day(8),
        todayVote: const TodayVote(slug: 'rebootcast', direction: 1),
      );
      final ponovo =
          state.applyOptimisticVote(slug: 'projekt-velebit', direction: 1);
      expect(identical(ponovo, state), isTrue);
      expect(ponovo.todayVote!.slug, 'rebootcast');

      // A greška servera je tiho poravnanje, ne poruka o grešci.
      expect(VotingErrorCode.fromWire('already_voted_today'),
          VotingErrorCode.alreadyVotedToday);
      expect(VotingErrorCode.alreadyVotedToday.isSilentAlignment, isTrue);
      expect(VotingErrorCode.roundClosed.isSilentAlignment, isFalse);
    });

    test('4. propušten 1 dan uz 1 zastavicu → spašeno, na kraju 1 zastavica', () {
      // Zadnji glas 6.8., danas 8.8. → propušten je 7.8.
      final cast = projectStreakForVote(
        today: day(8),
        snapshot: snap(streak: 5, longest: 9, flags: 1, lastDay: 6),
      );

      expect(cast.flagsBurned, 1);
      expect(cast.streakSaved, isTrue);
      expect(cast.streakBroken, isFalse);
      expect(cast.snapshot.streak, 6);
      expect(cast.snapshot.flags, 1); // 1 − 1 potrošena + 1 za današnji dolazak
      expect(cast.snapshot.longestStreak, 9);
    });

    test('5. propuštena 2 dana uz 2 zastavice → obje potrošene, na kraju 1', () {
      final cast = projectStreakForVote(
        today: day(8),
        snapshot: snap(streak: 12, longest: 12, flags: 2, lastDay: 5),
      );

      expect(cast.flagsBurned, 2);
      expect(cast.streakSaved, isTrue);
      expect(cast.snapshot.streak, 13);
      expect(cast.snapshot.flags, 1); // 2 − 2 + 1
      expect(cast.snapshot.longestStreak, 13);
    });

    test('6. propuštena 3 dana uz 2 zastavice → niz 1, zastavice pojedene', () {
      // REVIDIRANO 25.8.2026. (migracija 20260825122100): prije je vrijedilo
      // sve-ili-ništa — zastavice su ostajale netaknute i glas je uz to nosio
      // nagradu, pa je korisnik koji je propustio 12 dana izgubio niz i DOBIO
      // zastavicu. Sada se troše i kad ne mogu spasiti, a nagrade nema.
      final cast = projectStreakForVote(
        today: day(8),
        snapshot: snap(streak: 12, longest: 12, flags: 2, lastDay: 4),
      );

      expect(cast.streakBroken, isTrue);
      expect(cast.streakSaved, isFalse);
      expect(cast.flagsBurned, 2, reason: 'djelomično trošenje: pojede se sve');
      expect(cast.snapshot.streak, 1);
      expect(cast.snapshot.flags, 0, reason: 'puknuće ne nosi nagradu');
      expect(cast.snapshot.longestStreak, 12); // najduži se pamti zauvijek
    });

    test('6b. stvarni slučaj s produkcije: 12 propuštenih uz 1 zastavicu', () {
      // stepanic.matija@gmail.com: glas 12.8. (prvi ikad), pa 25.8.
      // Po staroj logici: niz 1, zastavice 1 → 2. Po novoj: zastavica nestane.
      final cast = projectStreakForVote(
        today: day(25),
        snapshot: snap(streak: 1, longest: 1, flags: 1, lastDay: 12),
      );

      expect(cast.streakBroken, isTrue);
      expect(cast.flagsBurned, 1);
      expect(cast.snapshot.streak, 1);
      expect(cast.snapshot.flags, 0);
      expect(cast.snapshot.longestStreak, 1);
    });

    test('6c. prvi glas ikad NIJE puknuće — nosi zastavicu', () {
      final cast = projectStreakForVote(today: day(8), snapshot: snap());

      expect(cast.streakBroken, isFalse);
      expect(cast.flagsBurned, 0);
      expect(cast.snapshot.streak, 1);
      expect(cast.snapshot.flags, 1);
    });

    test('7. zastavice na stropu → ostaje 2, ne 3', () {
      final cast = projectStreakForVote(
        today: day(8),
        snapshot: snap(streak: 3, longest: 3, flags: kMaxVoteFlags, lastDay: 7),
      );

      expect(cast.snapshot.flags, kMaxVoteFlags);
      expect(cast.snapshot.streak, 4);
    });

    test('8. brisanje računa → nova verifikacija istog OIB-a čuva niz', () {
      // Trajni pseudonim `voters.oib_hash` preživljava brisanje računa (§4.1),
      // pa server vrati isti niz pod NOVIM user_id-em. Klijentska projekcija
      // ovisi isključivo o snapshotu — identitet računa u nju ne ulazi.
      final vraceno = {
        'verified': true,
        'consented': true,
        'voted_today': false,
        'today': '2026-08-08',
        'streak': 12,
        'longest_streak': 19,
        'flags': 2,
        'streak_at_risk': false,
        'flags_that_will_burn': 0,
        'last_vote_day': '2026-08-07',
        'today_vote': null,
        'round': {
          'id': 7,
          'starts_on': '2026-08-01',
          'ends_on': '2026-08-14',
          'days_left': 6,
        },
      };

      final stari = VotingState.fromJson(vraceno);
      final novi = VotingState.fromJson(vraceno);
      expect(novi.streak, stari.streak);
      expect(novi.flags, stari.flags);
      expect(novi.longestStreak, 19);
      expect(
        projectStreakForVote(today: day(8), snapshot: novi.snapshot)
            .snapshot
            .streak,
        projectStreakForVote(today: day(8), snapshot: stari.snapshot)
            .snapshot
            .streak,
      );

      // Cache je vezan uz račun: zapis starog user_id-a se NE prikazuje novom.
      final raw = VotingService.encodeCachedState(stari, userId: 'stari-uuid');
      expect(VotingService.decodeCachedState(raw, userId: 'stari-uuid')?.streak,
          12);
      expect(VotingService.decodeCachedState(raw, userId: 'novi-uuid'), isNull);
      expect(VotingService.decodeCachedState(raw, userId: null), isNull);
      expect(VotingService.decodeCachedState('{nije json', userId: 'x'), isNull);
    });

    test('9. glas na dan kad kolo završava ulazi u to kolo, ne u sljedeće', () {
      final kolo = VoteRound(
        id: 7,
        startsOn: day(1),
        endsOn: day(14),
        status: VoteRoundStatus.open,
      );

      expect(kolo.acceptsVotesOn(day(14)), isTrue); // ends_on je UKLJUČIV
      expect(kolo.daysLeftOn(day(14)), 0);
      expect(kolo.acceptsVotesOn(day(15)), isFalse);
      expect(kolo.daysLeftOn(day(8)), 6);

      // Zatvoreno kolo ne prima glas ni na svoj zadnji dan.
      const zatvoreno = VoteRound(id: 7, status: VoteRoundStatus.closed);
      expect(zatvoreno.acceptsVotesOn(day(8)), isFalse);
    });

    test('10. kandidat proglašen pobjednikom usred kola → nije za glasanje', () {
      final ukrig = VoteCandidate.fromJson({
        'slug': 'rebootcast',
        'display_name': 'Rebootcast',
        'status': 'candidate',
      });
      expect(ukrig.isVotable, isTrue);

      for (final status in ['winner', 'onboarding', 'onboarded', 'withdrawn']) {
        final c = VoteCandidate.fromJson({
          'slug': 'projekt-velebit',
          'display_name': 'Projekt Velebit',
          'status': status,
        });
        expect(c.isVotable, isFalse, reason: 'status=$status');
      }

      expect(VotingErrorCode.fromWire('candidate_not_available'),
          VotingErrorCode.candidateNotAvailable);
      expect(VotingErrorCode.candidateNotAvailable.isSilentAlignment, isFalse);
    });
  });

  // ===========================================================================
  // §6.3 — projekcija pri čitanju
  // ===========================================================================

  group('projekcija pri čitanju (§6.3)', () {
    test('glasao danas → niz se prikazuje, ništa ne gori', () {
      final d = projectStreakForDisplay(
        today: day(8),
        snapshot: snap(streak: 12, flags: 2, lastDay: 8),
      );
      expect(d.votedToday, isTrue);
      expect(d.displayedStreak, 12);
      expect(d.streakAtRisk, isFalse);
      expect(d.flagsThatWillBurn, 0);
      expect(d.streakBroken, isFalse);
    });

    test('nije glasao, bez propuštenih dana → niz stoji', () {
      final d = projectStreakForDisplay(
        today: day(8),
        snapshot: snap(streak: 12, flags: 2, lastDay: 7),
      );
      expect(d.missedDays, 0);
      expect(d.displayedStreak, 12);
      expect(d.flagsThatWillBurn, 0);
      expect(d.streakAtRisk, isFalse); // još ima 2 dana rezerve
    });

    test('niz visi kad je broj propuštenih dana jednak broju zastavica', () {
      final d = projectStreakForDisplay(
        today: day(8),
        snapshot: snap(streak: 12, flags: 1, lastDay: 6),
      );
      expect(d.missedDays, 1);
      expect(d.streakAtRisk, isTrue); // zadnji dan obrane
      expect(d.displayedStreak, 12);
      expect(d.flagsThatWillBurn, 1);
    });

    test('niz je pukao → prikazuje se 0, zastavice ne gore', () {
      final d = projectStreakForDisplay(
        today: day(8),
        snapshot: snap(streak: 12, flags: 2, lastDay: 4),
      );
      expect(d.missedDays, 3);
      expect(d.displayedStreak, 0);
      expect(d.streakBroken, isTrue);
      expect(d.streakAtRisk, isFalse);
      expect(d.flagsThatWillBurn, 0);
    });

    test('glasač koji nikad nije glasao NIJE „niz visi"', () {
      // Doslovni izraz iz §6.3 (`missed == flags`) ovdje daje true (0 == 0),
      // što bi UI-ju dalo stanje „brani svoj niz" nad nizom od nula dana.
      // Projekcija zato traži i `streak > 0`.
      final d = projectStreakForDisplay(today: day(8), snapshot: snap());
      expect(d.streakAtRisk, isFalse);
      expect(d.displayedStreak, 0);
      expect(d.streakBroken, isFalse);
    });

    test('zadnji glas „u budućnosti" (star cache) ne daje negativan broj dana',
        () {
      final d = projectStreakForDisplay(
        today: day(8),
        snapshot: snap(streak: 3, flags: 1, lastDay: 10),
      );
      expect(d.missedDays, 0);
      expect(d.votedToday, isTrue); // server je autoritet; ne nudimo drugi glas
    });

    test('DST prijelaz ne guta dan (29.3.2026., 03:00)', () {
      final prije = DateTime.utc(2026, 3, 28);
      final poslije = DateTime.utc(2026, 3, 29);
      expect(voteDaysBetween(prije, poslije), 1);
      expect(
        projectStreakForVote(
          today: poslije,
          snapshot: StreakSnapshot(streak: 4, flags: 0, lastVoteDay: prije),
        ).snapshot.streak,
        5,
      );
    });
  });

  // ===========================================================================
  // §5.2 / v1.1 — ugovor RPC JSON-a
  // ===========================================================================

  group('RPC ugovor v1.1', () {
    test('my_voting_state se parsira polje po polje', () {
      final s = VotingState.fromJson({
        'verified': true,
        'consented': true,
        'voted_today': false,
        'today': '2026-08-08',
        'streak': 12,
        'longest_streak': 19,
        'flags': 2,
        'streak_at_risk': true,
        'flags_that_will_burn': 0,
        'last_vote_day': '2026-08-07',
        'today_vote': null,
        'round': {
          'id': 7,
          'starts_on': '2026-08-01',
          'ends_on': '2026-08-14',
          'days_left': 6,
        },
      });

      expect(s.verified, isTrue);
      expect(s.consented, isTrue);
      expect(s.votedToday, isFalse);
      expect(s.today, day(8));
      expect(s.streak, 12);
      expect(s.longestStreak, 19);
      expect(s.flags, 2);
      expect(s.streakAtRisk, isTrue);
      expect(s.flagsThatWillBurn, 0);
      expect(s.lastVoteDay, day(7));
      expect(s.todayVote, isNull);
      expect(s.round!.id, 7);
      expect(s.round!.startsOn, day(1));
      expect(s.round!.endsOn, day(14));
      expect(s.round!.daysLeft, 6);
      expect(s.canVote, isTrue);
      expect(s.needsConsent, isFalse);
    });

    test('today_vote kao objekt {slug, direction}', () {
      final s = VotingState.fromJson({
        'verified': true,
        'voted_today': true,
        'today': '2026-08-08',
        'today_vote': {'slug': 'rebootcast', 'direction': -1},
      });
      expect(s.todayVote!.slug, 'rebootcast');
      expect(s.todayVote!.direction, kVoteDirectionDown);
      expect(s.todayVote!.isUp, isFalse);
      expect(s.canVote, isFalse);
    });

    test('neverificiran gost → nema glasa, nema privole', () {
      final s = VotingState.fromJson({'verified': false});
      expect(s.canVote, isFalse);
      expect(s.needsConsent, isFalse);
      expect(s.today, isNull);
      expect(s.round, isNull);
    });

    test('verificiran bez privole traži jednokratni ekran (§4.3)', () {
      final s = VotingState.fromJson({'verified': true, 'consented': false});
      expect(s.needsConsent, isTrue);
    });

    test('current_round nosi kvorum, današnji dan i agregate', () {
      final r = VoteRound.fromJson({
        'id': 7,
        'starts_on': '2026-08-01',
        'ends_on': '2026-08-14',
        'status': 'open',
        'days_left': 6,
        'today': '2026-08-08',
        'quorum_net': 10,
        'quorum_total': 25,
        'total_votes': 214,
        'voters': 180,
      });

      expect(r.isOpen, isTrue);
      expect(r.today, day(8));
      expect(r.effectiveQuorumNet, 10);
      expect(r.effectiveQuorumTotal, 25);
      expect(r.totalVotes, 214);
      expect(r.voters, 180);

      // Bez konfiguriranih kolona padamo na brojke iz §7.2.
      const bez = VoteRound(id: 8);
      expect(bez.effectiveQuorumNet, kDefaultQuorumNet);
      expect(bez.effectiveQuorumTotal, kDefaultQuorumTotal);
    });

    test('zatvoreno kolo bez pobjednika nosi razlog', () {
      final r = VoteRound.fromJson({
        'id': 7,
        'status': 'closed',
        'no_winner_reason': kNoWinnerQuorumNotMet,
      });
      expect(r.hasNoWinner, isTrue);
      expect(r.noWinnerReason, 'quorum_not_met');
    });

    test('round_leaderboard redak → kandidat + tally + rank', () {
      final c = VoteCandidate.fromJson({
        'slug': 'podcast-inkubator',
        'display_name': 'Podcast Inkubator',
        'youtube_url': 'https://www.youtube.com/@podcastinkubator',
        'youtube_channel_id': 'UCabcdefghijklmnopqrstuv',
        'avatar_url':
            'https://cdn.domovina.ai/registry/avatars/podcast-inkubator.jpg',
        'tags': ['talk-show', 'society'],
        'voditelji': ['Marko Petrak', 'Ratko Martinović'],
        'subscribers': 400000,
        'episodes_estimate': 320,
        'quality_score': 100,
        'tier': 1,
        'notes': 'Najgledaniji hrvatski talk-show podcast.',
        'source_type': 'channel',
        'status': 'candidate',
        'up': 150,
        'down': 8,
        'net': 142,
        'rank': 1,
      });

      expect(c.slug, 'podcast-inkubator');
      expect(c.tags, ['talk-show', 'society']);
      expect(c.voditelji.length, 2);
      expect(c.sourceType, VoteSourceType.channel);
      expect(c.status, VoteCandidateStatus.candidate);
      expect(c.net, 142);
      expect(c.totalVotes, 158);
      expect(c.rank, 1);
      expect(c.qualityScore, 100);
    });

    test('živi redak s lokalnog Supabasea (rijetka polja null) se parsira', () {
      // Doslovan odgovor `round_leaderboard(p_round_id => 4, …)` s lokalne
      // instance, 8.8.2026. — kandidat bez tallyja i bez većine registry polja.
      final c = VoteCandidate.fromJson({
        'slug': 'podcast-inkubator',
        'display_name': 'Podcast Inkubator',
        'youtube_url': 'https://youtube.com/@inkubator',
        'youtube_channel_id': null,
        'avatar_url': null,
        'tags': ['talk-show', 'society'],
        'voditelji': <String>[],
        'subscribers': null,
        'episodes_estimate': null,
        'quality_score': 100,
        'tier': 1,
        'notes': null,
        'source_type': 'channel',
        'status': 'candidate',
        'up': 0,
        'down': 0,
        'net': 0,
        'rank': 1,
      });

      expect(c.up, 0);
      expect(c.down, 0);
      expect(c.net, 0);
      expect(c.totalVotes, 0);
      expect(c.rank, 1);
      expect(c.voditelji, isEmpty);
      expect(c.youtubeChannelId, isNull);
      expect(c.avatarUrl, isNull);
      expect(c.subscribers, isNull);
      expect(c.isVotable, isTrue);
      // Kolone `onboarded_channel_id` nema u TABLE ugovoru → null, ne pad.
      expect(c.onboardedChannelId, isNull);
    });

    test('živi current_round s lokalnog Supabasea', () {
      // Doslovan odgovor `current_round()`, 8.8.2026.
      final r = VoteRound.fromJson({
        'id': 4,
        'today': '2026-08-08',
        'status': 'open',
        'voters': 0,
        'ends_on': '2026-08-21',
        'days_left': 13,
        'starts_on': '2026-08-08',
        'quorum_net': 10,
        'total_votes': 0,
        'quorum_total': 25,
      });

      expect(r.id, 4);
      expect(r.isOpen, isTrue);
      expect(r.today, DateTime.utc(2026, 8, 8));
      expect(r.daysLeft, 13);
      // Kolo od 14 dana: prvi i zadnji dan su uključivi.
      expect(r.daysLeftOn(DateTime.utc(2026, 8, 8)), 13);
      expect(r.acceptsVotesOn(DateTime.utc(2026, 8, 21)), isTrue);
      expect(r.acceptsVotesOn(DateTime.utc(2026, 8, 22)), isFalse);
      expect(r.hasNoWinner, isFalse); // otvoreno kolo nije „bez pobjednika"
    });

    test('kvorum iz §7.2 traži oboje', () {
      const kolo = VoteRound(id: 7, quorumNet: 10, quorumTotal: 25);
      VoteCandidate c(int up, int down) =>
          VoteCandidate(slug: 's', displayName: 'S', up: up, down: down);

      expect(c(30, 5).meetsQuorum(kolo), isTrue); // net 25, ukupno 35
      expect(c(12, 0).meetsQuorum(kolo), isFalse); // net 12, ali ukupno 12
      expect(c(20, 15).meetsQuorum(kolo), isFalse); // ukupno 35, ali net 5
    });

    test('svi kodovi grešaka iz ugovora se prepoznaju iz `message`', () {
      // v1.1 t.7: tijelo je {"code":"P0001","message":"<kod>"} → čita se message.
      expect(VotingErrorCode.fromWire('not_verified'),
          VotingErrorCode.notVerified);
      expect(VotingErrorCode.fromWire('terms_not_accepted'),
          VotingErrorCode.termsNotAccepted);
      expect(VotingErrorCode.fromWire('already_voted_today'),
          VotingErrorCode.alreadyVotedToday);
      expect(VotingErrorCode.fromWire('candidate_not_available'),
          VotingErrorCode.candidateNotAvailable);
      expect(VotingErrorCode.fromWire('round_closed'),
          VotingErrorCode.roundClosed);
      // Postgres poruku zna umotati u prefiks — kod se svejedno prepozna.
      expect(
        VotingErrorCode.fromWire('P0001: not_verified'),
        VotingErrorCode.notVerified,
      );
      expect(VotingErrorCode.fromWire('nešto deseto'), VotingErrorCode.unknown);
      expect(VotingErrorCode.fromWire(null), VotingErrorCode.unknown);

      // SQLSTATE nikad ne nosi semantiku glasanja: 'P0001' sam po sebi ne
      // znači ništa, a 42501 (nema execute prava) je greška deploya.
      expect(VotingErrorCode.fromWire('P0001'), VotingErrorCode.unknown);
      expect(VotingErrorCode.fromWire('42501'), VotingErrorCode.unknown);
    });

    test('sort chipovi imaju vrijednosti koje RPC očekuje', () {
      expect(VoteSort.leaderboard.wire, 'leaderboard');
      expect(VoteSort.random.wire, 'random');
      expect(VoteSort.leastVotes.wire, 'least_votes');
    });
  });

  // ===========================================================================
  // Optimistički update
  // ===========================================================================

  group('optimistički update (§8.5)', () {
    final polazno = VotingState(
      verified: true,
      consented: true,
      votedToday: false,
      today: day(8),
      streak: 12,
      longestStreak: 19,
      flags: 1,
      streakAtRisk: true,
      flagsThatWillBurn: 1,
      lastVoteDay: day(6),
    );

    test('tap odmah pomakne niz, zastavicu i današnji glas', () {
      final poslije =
          polazno.applyOptimisticVote(slug: 'rebootcast', direction: 1);

      expect(poslije.votedToday, isTrue);
      expect(poslije.streak, 13);
      expect(poslije.flags, 1); // 1 potrošena za spas + 1 za dolazak
      expect(poslije.lastVoteDay, day(8));
      expect(poslije.streakAtRisk, isFalse);
      expect(poslije.flagsThatWillBurn, 0);
      expect(poslije.todayVote!.slug, 'rebootcast');
      expect(poslije.canVote, isFalse);

      // Polazno stanje ostaje netaknuto → rollback je puko vraćanje reference.
      expect(polazno.votedToday, isFalse);
      expect(polazno.streak, 12);
    });

    test('tally se pomakne samo na tapnutom kandidatu i u pravom smjeru', () {
      const c = VoteCandidate(slug: 'x', displayName: 'X', up: 10, down: 3);
      expect(c.withOptimisticVote(kVoteDirectionUp).up, 11);
      expect(c.withOptimisticVote(kVoteDirectionUp).down, 3);
      expect(c.withOptimisticVote(kVoteDirectionDown).down, 4);
      expect(c.withOptimisticVote(kVoteDirectionDown).net, 6);
      // copyWith ne smije izgubiti ostatak kandidata.
      expect(c.withOptimisticVote(kVoteDirectionUp).displayName, 'X');
    });

    test('bez poznatog serverovog dana nema optimističkog pomaka', () {
      const bezDana = VotingState(verified: true, consented: true);
      final poslije =
          bezDana.applyOptimisticVote(slug: 'rebootcast', direction: 1);
      expect(identical(poslije, bezDana), isTrue);
    });

    test('cache round-trip preživi puni JSON', () {
      final raw = VotingService.encodeCachedState(polazno, userId: 'u1');
      final vraceno = VotingService.decodeCachedState(raw, userId: 'u1')!;

      expect(vraceno.streak, 12);
      expect(vraceno.longestStreak, 19);
      expect(vraceno.flags, 1);
      expect(vraceno.today, day(8));
      expect(vraceno.lastVoteDay, day(6));
      expect(vraceno.verified, isTrue);
    });
  });
}
