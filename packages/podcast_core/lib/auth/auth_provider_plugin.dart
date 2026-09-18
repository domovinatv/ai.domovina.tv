import 'package:flutter/widgets.dart';

/// Vanjski način prijave koji ljuska registrira u jezgru — npr. Certilia
/// (e-Osobna) u DOMOVINA.ai ljusci. Jezgra ne ovisi o SDK-u providera:
/// plugin sam odradi svoj flow i na kraju postavi Supabase sesiju (obično
/// `verifyOTP` bridgeom kao passkey), pa `onAuthStateChange` preuzme dalje.
abstract class AuthProviderPlugin {
  /// Stabilan identifikator; mora odgovarati `AuthProvider.name` vrijednosti
  /// pod kojom ga auth sheet prikazuje (`'certilia'`).
  String get id;

  /// Pokreće prijavu. [anonId] je UUID anonimnog korisnika koji jezgra želi
  /// migrirati na novi račun (plugin ga proslijedi svom backendu).
  /// Neuspjeh se javlja kao [AuthPluginFailure] s porukom za korisnika.
  Future<void> signIn(BuildContext context, {String? anonId});
}

/// Poruka za korisnika kad plugin prijava ne uspije (otkazano, mreža, bridge).
class AuthPluginFailure implements Exception {
  final String message;
  const AuthPluginFailure(this.message);
  @override
  String toString() => message;
}

/// Registar plugina po id-u. Ljuska ih preda kroz `runPodcastApp(authPlugins:)`;
/// provider bez registriranog plugina se ne nudi u auth sheetu.
class AuthPlugins {
  AuthPlugins._();

  static final Map<String, AuthProviderPlugin> _byId = {};

  static void register(AuthProviderPlugin plugin) => _byId[plugin.id] = plugin;

  static AuthProviderPlugin? byId(String id) => _byId[id];

  static bool has(String id) => _byId.containsKey(id);

  /// Samo za testove.
  static void clear() => _byId.clear();
}
