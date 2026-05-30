import 'package:flutter_test/flutter_test.dart';
import 'package:domovina_ai/models/channel_claim.dart';
import 'package:domovina_ai/models/channel_detail.dart';
import 'package:domovina_ai/models/owner_wallet.dart';
import 'package:domovina_ai/models/payout_eligibility.dart';

void main() {
  group('UC… channel ID parsing', () {
    test('eksplicitni valjani UC ID prolazi', () {
      final c = ChannelDetail.fromJson({
        'youtube_channel_id': 'UCabcdefghijklmnopqrstuv',
      });
      expect(c.youtubeChannelId, 'UCabcdefghijklmnopqrstuv');
    });

    test('izvuče UC ID iz /channel/ URL-a', () {
      final c = ChannelDetail.fromJson({
        'youtube_channel_url':
            'https://www.youtube.com/channel/UCabcdefghijklmnopqrstuv',
      });
      expect(c.youtubeChannelId, 'UCabcdefghijklmnopqrstuv');
    });

    test('handle/@ URL bez UC vraća null', () {
      final c = ChannelDetail.fromJson({
        'youtube_channel_url': 'https://www.youtube.com/@nekikanal',
      });
      expect(c.youtubeChannelId, isNull);
    });

    test('neispravan UC (prekratak) vraća null', () {
      final c = ChannelDetail.fromJson({'youtube_channel_id': 'UCtooshort'});
      expect(c.youtubeChannelId, isNull);
    });
  });

  group('ChannelClaim.needsReverify (D4)', () {
    ChannelClaim verifiedAt(DateTime t) => ChannelClaim(
          id: '1',
          accountId: 'a',
          youtubeChannelId: 'UCabcdefghijklmnopqrstuv',
          role: ClaimRole.primary,
          status: ClaimStatus.verified,
          verifiedAt: t,
        );

    final now = DateTime(2026, 5, 30);

    test('svjež claim (< 90 dana) ne treba reverify', () {
      expect(verifiedAt(DateTime(2026, 4, 1)).needsReverify(now), isFalse);
    });

    test('stari claim (>= 90 dana) treba reverify', () {
      expect(verifiedAt(DateTime(2026, 1, 1)).needsReverify(now), isTrue);
    });

    test('pending claim nikad ne treba reverify', () {
      final c = ChannelClaim(
        id: '1',
        accountId: 'a',
        youtubeChannelId: 'UCabcdefghijklmnopqrstuv',
        role: ClaimRole.primary,
        status: ClaimStatus.pending,
        verifiedAt: DateTime(2020, 1, 1),
      );
      expect(c.needsReverify(now), isFalse);
    });
  });

  group('PayoutEligibility.evaluate — prvi blok koji fali', () {
    final now = DateTime(2026, 5, 30);
    final verified = ChannelClaim(
      id: '1',
      accountId: 'a',
      youtubeChannelId: 'UCabcdefghijklmnopqrstuv',
      role: ClaimRole.primary,
      status: ClaimStatus.verified,
      verifiedAt: DateTime(2026, 5, 1),
    );

    test('nema claima → notOwner', () {
      final e = PayoutEligibility.evaluate(
          claim: null, isKycVerified: true, now: now);
      expect(e.block, EligibilityBlock.notOwner);
      expect(e.isEligible, isFalse);
    });

    test('pending claim → claimNotVerified', () {
      final pending = ChannelClaim(
        id: '1',
        accountId: 'a',
        youtubeChannelId: 'UCabcdefghijklmnopqrstuv',
        role: ClaimRole.primary,
        status: ClaimStatus.pending,
      );
      final e = PayoutEligibility.evaluate(
          claim: pending, isKycVerified: true, now: now);
      expect(e.block, EligibilityBlock.claimNotVerified);
    });

    test('verified ali bez KYC → kycMissing', () {
      final e = PayoutEligibility.evaluate(
          claim: verified, isKycVerified: false, now: now);
      expect(e.block, EligibilityBlock.kycMissing);
    });

    test('verified + KYC + svjež → eligible', () {
      final e = PayoutEligibility.evaluate(
          claim: verified, isKycVerified: true, now: now);
      expect(e.block, EligibilityBlock.none);
      expect(e.isEligible, isTrue);
    });

    test('verified + KYC ali star (>90d) → reverifyNeeded', () {
      final old = ChannelClaim(
        id: '1',
        accountId: 'a',
        youtubeChannelId: 'UCabcdefghijklmnopqrstuv',
        role: ClaimRole.primary,
        status: ClaimStatus.verified,
        verifiedAt: DateTime(2026, 1, 1),
      );
      final e = PayoutEligibility.evaluate(
          claim: old, isKycVerified: true, now: now);
      expect(e.block, EligibilityBlock.reverifyNeeded);
    });
  });

  group('EVM adresa validacija', () {
    test('valjana 0x adresa', () {
      expect(
          kEvmAddressPattern
              .hasMatch('0x1234567890abcdef1234567890ABCDEF12345678'),
          isTrue);
    });
    test('prekratka pada', () {
      expect(kEvmAddressPattern.hasMatch('0x1234'), isFalse);
    });
    test('bez 0x prefiksa pada', () {
      expect(
          kEvmAddressPattern
              .hasMatch('1234567890abcdef1234567890abcdef12345678'),
          isFalse);
    });
  });
}
