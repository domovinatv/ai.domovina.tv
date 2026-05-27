import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';

import '../main.dart' show log;

/// Detects whether the app is running on an Android TV (Leanback) device.
///
/// Resolves once at startup via a MethodChannel that queries
/// `PackageManager.hasSystemFeature(FEATURE_LEANBACK)` on the native side.
/// Cached in [isTv] (sync getter) so router/theme branching stays cheap.
///
/// Dev override: `--dart-define=FORCE_TV=true` forces TV layout even on
/// desktop/mobile/web builds — handy for iterating on TV UI without a real
/// device. The override is honoured before any platform check so it works in
/// Chrome / Mac / iOS simulators.
class TvMode {
  TvMode._();

  static const _channel = MethodChannel('ai.domovina/tv_mode');
  static const _forceTv =
      bool.fromEnvironment('FORCE_TV', defaultValue: false);

  static bool _isTv = false;
  static bool _initialized = false;

  /// True when the app should render TV (10-foot) UI.
  static bool get isTv => _isTv;

  /// Must be called from main() before runApp(). Idempotent.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    if (_forceTv) {
      _isTv = true;
      log('TvMode: FORCE_TV override active');
      return;
    }

    // Only Android phones/tablets/TVs hit the native channel. Web, iOS,
    // macOS, etc. are never TV.
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _isTv = false;
      return;
    }

    try {
      final result = await _channel.invokeMethod<bool>('isLeanback');
      _isTv = result ?? false;
      log('TvMode: leanback=$_isTv');
    } catch (e) {
      log('TvMode: channel error — $e (assuming non-TV)');
      _isTv = false;
    }
  }
}
