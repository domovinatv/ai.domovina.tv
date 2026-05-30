/// Payout eligibility — Princip B: money gate = (ownership ∧ KYC ∧ svježina).
/// Vidi docs/channel-ownership-and-safe-payout-plan.md §3, §7.
library;

import 'channel_claim.dart';

/// Koji uvjet (ako ijedan) blokira payout. UI iz ovoga zna kamo voditi usera.
enum EligibilityBlock {
  /// Sve OK — korisnik smije registrirati wallet / postati co-signer.
  none,

  /// Nema verified claima za ovaj kanal → pokreni YouTube verifikaciju.
  notOwner,

  /// Claim postoji ali nije verified (pending/revoked/disputed).
  claimNotVerified,

  /// Vlasništvo dokazano, ali identitet (Certilia KYC) nije → vodi u eOsobnu.
  kycMissing,

  /// Verified ali stariji od 90 dana (D4) → traži re-verifikaciju.
  reverifyNeeded,
}

class PayoutEligibility {
  final EligibilityBlock block;

  const PayoutEligibility(this.block);

  bool get isEligible => block == EligibilityBlock.none;

  /// Izračunaj eligibility iz tri nezavisna signala. `now` injektabilan (D4).
  ///
  /// Redoslijed provjera je namjeran: ownership → KYC → svježina. Tako UI
  /// uvijek pokaže "prvi" korak koji fali (ne sve odjednom).
  factory PayoutEligibility.evaluate({
    required ChannelClaim? claim,
    required bool isKycVerified,
    required DateTime now,
  }) {
    if (claim == null) {
      return const PayoutEligibility(EligibilityBlock.notOwner);
    }
    if (!claim.isVerified) {
      return const PayoutEligibility(EligibilityBlock.claimNotVerified);
    }
    if (!isKycVerified) {
      return const PayoutEligibility(EligibilityBlock.kycMissing);
    }
    if (claim.needsReverify(now)) {
      return const PayoutEligibility(EligibilityBlock.reverifyNeeded);
    }
    return const PayoutEligibility(EligibilityBlock.none);
  }

  /// Korisnička poruka za trenutni blok.
  String get message => switch (block) {
        EligibilityBlock.none => 'Spremno za isplatu.',
        EligibilityBlock.notOwner =>
          'Potvrdi vlasništvo kanala (Login with YouTube).',
        EligibilityBlock.claimNotVerified =>
          'Tvoj zahtjev za vlasništvo još nije potvrđen.',
        EligibilityBlock.kycMissing =>
          'Verificiraj identitet eOsobnom (Certilia) za isplatu.',
        EligibilityBlock.reverifyNeeded =>
          'Vlasništvo treba ponovo potvrditi (starije od 90 dana).',
      };
}
