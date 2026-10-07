/// Ugovor `SponsoredMoment` / `SponsorOffer` / `SponsorOrderStatus` ↔
/// `domovina-api` (`docs/sponzorski-trenuci-ugovor.md`, v1 od 7.10.2026.).
///
/// Fixture su **stvarni odgovori lokalnog backenda** nad migracijama
/// `20261007120000_sponzorski_trenuci.sql` + seed, uhvaćeni 7.10.2026.:
///
///   test/fixtures/sponsored_moments_live.json
///     ← GET /rest/v1/public_live_moments?order=youtube_id,start_sec
///   test/fixtures/sponsor_offers_live.json
///     ← GET /rest/v1/public_sponsor_moments?youtube_id=in.(KvIhy5SESYs,fO7iltytw0I)
///   test/fixtures/sponsor_order_status_live.json
///     ← POST /rest/v1/rpc/sponsor_order_status (paid / underpaid / pending)
///
/// Isti razlog kao `person_backend_contract_test.dart`: producent ne
/// verificira potrošača. Preimenovana kolona bi se u `tryParse` tiho
/// pretvorila u null i traka „Sponzorirano" bi nestala bez ijedne iznimke —
/// zato se ovdje provjeravaju VRIJEDNOSTI, ne samo da parsiranje ne baca.
/// Kad se fixture regenerira, brojke ispod se mijenjaju s njim.
library;

import 'dart:convert';
import 'dart:io';

import 'package:domovina_ai/models/sponsor_offer.dart';
import 'package:domovina_ai/models/sponsored_moment.dart';
import 'package:flutter_test/flutter_test.dart';

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

void main() {
  group('public_live_moments → SponsoredMoment', () {
    final rows = _fixture('sponsored_moments_live.json')! as List;
    final all = SponsoredMoments.fromRows(rows);

    test('svaki red je stigao i parsiran', () {
      expect(rows, hasLength(2));
      expect(all.moments, hasLength(2));
    });

    test('vrijednosti, ne samo oblik', () {
      final m = all.moments.firstWhere((m) => m.youtubeId == 'fO7iltytw0I');
      expect(m.slotKey, 'fO7iltytw0I@44');
      expect(m.start, 44);
      expect(m.end, 180);
      expect(m.brand, 'Primjer d.o.o.');
      expect(m.tagline, 'Jedna rečenica.');
      expect(m.linkUrl, 'https://primjer.hr');
      expect(m.linkHost, 'primjer.hr');
      expect(m.logoUrl, isNull);
      expect(m.liveFrom, DateTime.parse('2026-10-07T13:54:27.499365+00:00'));
      expect(m.liveUntil, DateTime.parse('2026-11-06T13:54:27.499365+00:00'));
    });

    test('tagline s HTML-om ostaje doslovni tekst (nikad se ne renderira)', () {
      final m = all.moments.firstWhere((m) => m.youtubeId == 'KvIhy5SESYs');
      expect(m.tagline, 'Rečenica <b>bez</b> HTML-a.');
    });

    test('view nikad ne nosi podatke kupca ni iznos', () {
      for (final r in rows.cast<Map>()) {
        for (final k in r.keys) {
          expect(k, isNot(startsWith('buyer')));
          expect(k, isNot(contains('amount')));
          expect(k, isNot(contains('email')));
        }
      }
    });

    test('isLiveAt prati [live_from, live_until)', () {
      final m = all.moments.first;
      expect(m.isLiveAt(m.liveFrom!), isTrue);
      expect(m.isLiveAt(m.liveUntil!), isFalse);
      expect(m.isLiveAt(m.liveFrom!.subtract(const Duration(seconds: 1))),
          isFalse);
    });
  });

  group('public_sponsor_moments → SponsorOffer', () {
    final rows = _fixture('sponsor_offers_live.json')! as List;
    final offers = SponsorOffer.listFromRows(rows);

    test('nijedan red nije izgubljen', () {
      expect(offers, hasLength(rows.length));
      expect(offers, hasLength(22));
    });

    test('prodani trenutak nosi live_until, slobodan ne', () {
      final sold = offers.firstWhere((o) => o.slotKey == 'fO7iltytw0I@44');
      expect(sold.state, SponsorSlotState.sold);
      expect(sold.liveUntil, isNotNull);
      final free = offers.firstWhere((o) => o.state == SponsorSlotState.free);
      expect(free.liveUntil, isNull);
      expect(free.state.isBuyable, isTrue);
    });

    test('zona, cijena i trajanje stižu iz baze', () {
      final o = offers.firstWhere((o) => o.slotKey == 'fO7iltytw0I@44');
      expect(o.campaignId, '7e5a0f3e-2f1d-4c9b-9a51-0d0b1a5e7101');
      expect(o.start, 44);
      expect(o.end, 180);
      expect(o.title, isNotNull);
      expect(o.zone, isNot(SponsorZone.other));
      expect(o.priceCents, greaterThan(0));
      expect(o.runDays, greaterThan(0));
    });

    test('svi ARB ključevi zona iz baze su poznati', () {
      for (final r in rows.cast<Map>()) {
        expect(
          SponsorZone.parse(r['zone_label_key']),
          isNot(SponsorZone.other),
          reason: 'nepoznat zone_label_key ${r['zone_label_key']}',
        );
      }
    });

    test('svako stanje iz baze je poznato', () {
      for (final o in offers) {
        expect(o.state, isNot(SponsorSlotState.unknown));
      }
    });
  });

  group('rpc/sponsor_order_status → SponsorOrderStatus', () {
    final f = _fixture('sponsor_order_status_live.json')! as Map;

    test('plaćeno i dodijeljeno = uživo', () {
      final s = SponsorOrderStatus.tryParse(f['paid'])!;
      expect(s.state, SponsorOrderState.paid);
      expect(s.underpaid, isFalse);
      expect(s.amountCents, 8000);
      expect(s.amountReceivedCents, 8000);
      expect(s.slots, hasLength(1));
      expect(s.slots.first.slotKey, 'fO7iltytw0I@44');
      expect(s.slots.first.state, SponsorSlotState.sold);
      expect(s.slots.first.liveUntil, isNotNull);
      expect(s.invoiceState, 'skipped');
      expect(s.isAssigned, isTrue);
      final until = s.slots.first.liveUntil!;
      expect(s.isLiveAt(until.subtract(const Duration(days: 1))), isTrue);
      // Nakon isteka zakupa `state` ostaje `paid`, ali oglas nije uživo.
      expect(s.isLiveAt(until), isFalse);
    });

    test('manjak uplate: failed + underpaid, nije uživo', () {
      final s = SponsorOrderStatus.tryParse(f['underpaid'])!;
      expect(s.state, SponsorOrderState.failed);
      expect(s.underpaid, isTrue);
      expect(s.slots, isEmpty);
      expect(s.isAssigned, isFalse);
      expect(s.isLiveAt(DateTime(2026, 10, 8)), isFalse);
      expect(s.state.isFinal, isTrue);
    });

    test('pending nije završno stanje', () {
      final s = SponsorOrderStatus.tryParse(f['pending'])!;
      expect(s.state, SponsorOrderState.pending);
      expect(s.state.isFinal, isFalse);
      expect(s.slots.single.state, SponsorSlotState.free);
    });
  });
}
