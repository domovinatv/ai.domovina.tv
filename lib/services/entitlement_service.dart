/// Single source of truth for the `domovina_plus` entitlement, read on EVERY
/// platform. Exposes one boolean the whole app gates on: [isPlus].
///
/// Authoritative signal: the user's `domovina_ai.subscriptions` row (written
/// only by the RevenueCat webhook via the service role). This row survives
/// reinstalls, works cross-device, and covers web purchases — so it is the
/// universal source. We subscribe to it via Supabase realtime (best-effort) and
/// also expose [refresh] for explicit re-fetch (after a purchase, on resume).
///
/// Mobile-only optimistic signal: [RevenueCatService.optimisticPlus] flips true
/// the instant a sandbox/store purchase completes, unlocking the UI while the
/// webhook→Supabase round-trip catches up. `isPlus = supabase || optimistic`.
///
/// Gate strictly on the entitlement — never on a product id.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../main.dart' show log;
import 'revenue_cat_service.dart';

class EntitlementService {
  static final EntitlementService instance = EntitlementService._();
  EntitlementService._();

  /// The single boolean every feature gate reads.
  final ValueNotifier<bool> isPlus = ValueNotifier<bool>(false);

  bool _supabasePlus = false;
  bool _optimisticPlus = false;
  bool _initialized = false;

  StreamSubscription<List<Map<String, dynamic>>>? _rowSub;
  String? _userId;

  /// Call once from main() after AuthService.init().
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Fold in the mobile optimistic SDK unlock (always false on web/TV).
    RevenueCatService.instance.optimisticPlus.addListener(() {
      _optimisticPlus = RevenueCatService.instance.optimisticPlus.value;
      _recompute();
    });

    try {
      final client = sb.Supabase.instance.client;
      _bindUser(client.auth.currentUser?.id);
      // App-lifetime singleton — no dispose; subscription lives for the session.
      client.auth.onAuthStateChange.listen((data) {
        _bindUser(data.session?.user.id);
      });
    } catch (e) {
      log('EntitlementService.init: Supabase unavailable — $e');
    }
  }

  void _bindUser(String? userId) {
    if (userId == _userId) return;
    _userId = userId;
    _rowSub?.cancel();
    _rowSub = null;
    _supabasePlus = false;
    _recompute();
    if (userId == null) return;

    // Realtime subscription to our own row (RLS-scoped). Best-effort: if
    // realtime isn't enabled for this table the stream simply won't emit —
    // refresh() (after purchase / on resume) still keeps state fresh.
    try {
      _rowSub = sb.Supabase.instance.client
          .schema('domovina_ai')
          .from('subscriptions')
          .stream(primaryKey: ['user_id'])
          .eq('user_id', userId)
          .listen(
            (rows) {
              _supabasePlus = rows.isNotEmpty && _rowIsActive(rows.first);
              log('EntitlementService: realtime plus=$_supabasePlus');
              _recompute();
            },
            onError: (e) => log('EntitlementService realtime error: $e'),
          );
    } catch (e) {
      log('EntitlementService: realtime unavailable — $e');
    }

    // Always do an immediate one-shot fetch (covers no-realtime backends).
    refresh();
  }

  /// One-shot authoritative re-fetch of the current user's entitlement row.
  /// Safe to call anytime (after a purchase, on app resume).
  Future<void> refresh() async {
    final userId = _userId;
    if (userId == null) return;
    try {
      final row = await sb.Supabase.instance.client
          .schema('domovina_ai')
          .from('subscriptions')
          .select()
          .eq('user_id', userId)
          .maybeSingle();
      _supabasePlus = row != null && _rowIsActive(row);
      log('EntitlementService: refresh plus=$_supabasePlus');
      _recompute();
    } catch (e) {
      log('EntitlementService.refresh failed: $e');
    }
  }

  bool _rowIsActive(Map<String, dynamic> row) =>
      row['status'] == 'active' &&
      row['entitlement'] == kDomovinaPlusEntitlement;

  void _recompute() {
    final next = _supabasePlus || _optimisticPlus;
    if (next != isPlus.value) {
      isPlus.value = next;
      log('EntitlementService: isPlus=$next');
    }
  }
}
