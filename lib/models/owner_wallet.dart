/// Model za domovina_ai.owner_wallets — EOA wallet adresa vlasnika koja
/// postaje Safe co-signer. Vidi docs/channel-ownership-and-safe-payout-plan.md §5.
library;

/// Validira EVM adresu (0x + 40 hex znakova). Ne radi EIP-55 checksum
/// provjeru — to je odgovornost backend/on-chain sloja.
final RegExp kEvmAddressPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');

class OwnerWallet {
  final String id;
  final String accountId;
  final String address;

  /// Postavljeno kad korisnik dokaže kontrolu adrese (npr. SIWE potpis).
  final DateTime? verifiedAt;

  const OwnerWallet({
    required this.id,
    required this.accountId,
    required this.address,
    this.verifiedAt,
  });

  bool get isVerified => verifiedAt != null;

  factory OwnerWallet.fromJson(Map<String, dynamic> json) {
    final v = json['verified_at'] as String?;
    return OwnerWallet(
      id: json['id'] as String? ?? '',
      accountId: json['account_id'] as String? ?? '',
      address: json['address'] as String? ?? '',
      verifiedAt: v == null ? null : DateTime.tryParse(v),
    );
  }
}
