/// Zašto tap na 👍/👎 nije prošao (`razlogBlokadeGlasa`).
///
/// Prijavljeno 25.8.2026.: nakon danas danog glasa tap na 👍 samo otvori detalj
/// sheet, bez ijedne poruke — jedini trag je rečenica u zaglavlju na vrhu, koju
/// korisnik na dnu liste od 218 kandidata ne vidi. Uzrok: `IconButton` s
/// `onPressed: null` nema gesture recognizer, pa tap propadne na `InkWell`
/// retka. Gumbi su sada tapabilni i objašnjavaju razlog; ovaj test drži da se
/// razlozi ne pomiješaju.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/l10n/app_localizations.dart';
import 'package:domovina_ai/l10n/app_localizations_hr.dart';
import 'package:domovina_ai/models/vote_candidate.dart';
import 'package:domovina_ai/models/vote_round.dart';
import 'package:domovina_ai/screens/voting/voting_screen.dart';

final AppLocalizations l = AppLocalizationsHr();

VoteCandidate kandidat({VoteCandidateStatus status = VoteCandidateStatus.candidate}) =>
    VoteCandidate(slug: 'abbacast', displayName: 'AbbaCast', status: status);

void main() {
  final danas = DateTime.utc(2026, 8, 25);

  test('kandidat ispao iz igre → to ima prednost pred svime', () {
    final poruka = razlogBlokadeGlasa(
      l: l,
      kandidat: kandidat(status: VoteCandidateStatus.onboarded),
      round: null,
      today: danas,
    );
    expect(poruka, l.votingErrorCandidateGone);
  });

  test('zatvoreno kolo → poruka o kolu, ne o potrošenom glasu', () {
    final zatvoreno = VoteRound(
      id: 2,
      status: VoteRoundStatus.closed,
      startsOn: DateTime.utc(2026, 8, 22),
      endsOn: DateTime.utc(2026, 8, 24),
    );
    final poruka = razlogBlokadeGlasa(
      l: l,
      kandidat: kandidat(),
      round: zatvoreno,
      today: danas,
    );
    expect(poruka, l.votingErrorRoundClosed);
  });

  test('inače: glas potrošen + kad se vratiti', () {
    final poruka = razlogBlokadeGlasa(
      l: l,
      kandidat: kandidat(),
      round: null,
      today: danas,
    );
    expect(poruka, contains(l.votingAlreadyVoted));
    expect(poruka, contains(l.votingComeBackTomorrow),
        reason: 'korisnik mora doznati KAD smije ponovno, ne samo da ne smije');
  });
}
