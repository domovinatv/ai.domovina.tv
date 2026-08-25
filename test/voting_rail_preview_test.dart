/// Izvadak ljestvice za home rail (`VotingService.ensurePreviewLoaded`).
///
/// Rail „Izborni dan" je jedina ulazna točka glasanja koju vidi korisnik BEZ
/// potvrde e-Osobnom, pa mora vrijediti dvoje:
///
/// 1. **Ne dira stanje ekrana `/glasanje`.** Preview traži 10 redaka, ljestvica
///    100 — da dijele isto polje, prvi bi dohvat pobijedio i drugi ekran bi
///    ostao na krivom broju kandidata.
/// 2. **Pad je nijem.** Rail bez mreže samo ostane skriven; ne smije ostaviti
///    `lastError` koji bi `/glasanje` naslikao porukom o grešci.
///
/// Bez inicijaliziranog Supabasea `_rpc` odmah baca `unavailable`, što je
/// upravo scenarij iz točke 2.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:domovina_ai/models/vote_candidate.dart';
import 'package:domovina_ai/services/voting_service.dart';

void main() {
  final service = VotingService.instance;

  test('preview pada nijemo — bez lastError i bez praznog ekrana ljestvice',
      () async {
    await service.ensurePreviewLoaded(limit: 10);

    expect(service.previewCandidates, isEmpty);
    expect(service.lastError, isNull,
        reason: 'pad raila ne smije obojati /glasanje porukom o grešci');
  });

  test('preview je odvojen od ljestvice', () async {
    await service.ensurePreviewLoaded(limit: 3);

    expect(service.sort, VoteSort.leaderboard,
        reason: 'preview ne smije preslagati sort koji je korisnik odabrao');
    expect(service.tags, isEmpty,
        reason: 'preview ne gradi popis tema — to radi puni dohvat');
    expect(service.tag, isNull,
        reason: 'preview ne smije obrisati odabrani tag filter');
    expect(service.query, isNull,
        reason: 'preview ne smije obrisati korisnikovu pretragu');
  });

  test('ensurePreviewLoaded je idempotentan — dijeli isti Future', () {
    final a = service.ensurePreviewLoaded();
    final b = service.ensurePreviewLoaded();
    expect(identical(a, b), isTrue);
  });
}
