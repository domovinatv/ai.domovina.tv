library;

/// Odgovor `pinka-onchain-confirm` — stanje verifikacije EURe tx-a po hashu.
/// Caller polla dok `mined` ne postane true; `credited > 0` znači da je barem
/// jedan Transfer na campaign Safe pripisan doprinosu.
class PinkaOnchainConfirm {
  /// Tx još nije u bloku (caller nastavlja poll).
  final bool mined;

  /// Broj pripisanih (kreditiranih) Transfer logova u ovom tx-u.
  final int credited;

  /// Tx je revertan na lancu.
  final bool reverted;

  const PinkaOnchainConfirm({
    required this.mined,
    required this.credited,
    this.reverted = false,
  });

  bool get isCredited => credited > 0;

  factory PinkaOnchainConfirm.fromJson(Map<String, dynamic> json) {
    return PinkaOnchainConfirm(
      mined: json['mined'] as bool? ?? false,
      credited: (json['credited'] as int?) ?? 0,
      reverted: json['reverted'] as bool? ?? false,
    );
  }
}
