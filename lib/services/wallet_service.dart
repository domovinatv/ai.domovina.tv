/// Wallet registracija — vlasnik registrira EOA adresu koja će postati Safe
/// co-signer. CRUD nad domovina_ai.owner_wallets (RLS: samo vlasnik).
/// Vidi docs/channel-ownership-and-safe-payout-plan.md §5, §8.
library;

import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log;
import '../models/owner_wallet.dart';
import 'locale_service.dart';

class WalletFailure implements Exception {
  final String message;
  const WalletFailure(this.message);
  @override
  String toString() => message;
}

class WalletService {
  static final WalletService instance = WalletService._();
  WalletService._();

  /// Registriraj wallet adresu trenutnog usera. Idempotentno (unique
  /// account_id+address). Validira format prije slanja.
  Future<OwnerWallet> register(String address) async {
    final normalized = address.trim();
    if (!kEvmAddressPattern.hasMatch(normalized)) {
      throw WalletFailure(appStrings.serviceWalletInvalidAddress);
    }
    final client = sb.Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw WalletFailure(appStrings.serviceWalletNotSignedIn);
    }
    try {
      final row = await client
          .schema('domovina_ai')
          .from('owner_wallets')
          .upsert({
            'account_id': user.id,
            'address': normalized,
          }, onConflict: 'account_id,address')
          .select()
          .single();
      return OwnerWallet.fromJson(row);
    } catch (e) {
      log('wallet register failed: $e');
      throw WalletFailure(appStrings.serviceWalletSaveFailed);
    }
  }

  /// Sve registrirane adrese trenutnog usera.
  Future<List<OwnerWallet>> myWallets() async {
    final client = sb.Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null || user.isAnonymous) return const [];
    try {
      final rows = await client
          .schema('domovina_ai')
          .from('owner_wallets')
          .select()
          .eq('account_id', user.id)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((r) => OwnerWallet.fromJson((r as Map).cast<String, dynamic>()))
          .toList();
    } catch (e) {
      log('myWallets failed: $e');
      return const [];
    }
  }

  /// Ukloni registriranu adresu.
  Future<void> remove(String walletId) async {
    final client = sb.Supabase.instance.client;
    try {
      await client
          .schema('domovina_ai')
          .from('owner_wallets')
          .delete()
          .eq('id', walletId);
    } catch (e) {
      log('wallet remove failed: $e');
      throw WalletFailure(appStrings.serviceWalletRemoveFailed);
    }
  }
}
