library;

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web implementacija in-app DOMOVINA wallet senda.
///
/// Učita `wallet.domovina.ai/sdk.js` (mounta skriveni iframe pod RP-ID
/// `domovina.ai`), zatim pozove `window.Domovina.send({to, amount})` koji
/// odradi Face ID / passkey ceremoniju i vrati tx hash. Pinka onda verificira
/// taj tx preko `pinka-onchain-confirm` edge fn-a.
const bool kPinkaWalletSupported = true;

@JS('Domovina')
external _DomovinaSdk? get _domovina;

extension type _DomovinaSdk._(JSObject _) implements JSObject {
  external JSPromise<_SendResult> send(_SendArgs args);
}

extension type _SendArgs._(JSObject _) implements JSObject {
  external factory _SendArgs({required String to, required String amount});
}

extension type _SendResult._(JSObject _) implements JSObject {
  external String get txHash;
}

Future<void>? _loader;

Future<void> _loadSdk(String src) {
  if (_domovina != null) return Future<void>.value();
  return _loader ??= () {
    final completer = Completer<void>();
    final script =
        web.document.createElement('script') as web.HTMLScriptElement
          ..src = src
          ..async = true;
    script.addEventListener(
      'load',
      ((web.Event _) {
        if (!completer.isCompleted) completer.complete();
      }).toJS,
    );
    script.addEventListener(
      'error',
      ((web.Event _) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('wallet_sdk_load_failed'));
        }
      }).toJS,
    );
    web.document.head!.appendChild(script);
    return completer.future;
  }();
}

/// Pošalji [amount] EURe (decimalni string, npr. "5.00") na adresu [to].
/// Vraća tx hash; baca ako SDK ne učita ili korisnik otkaže.
Future<String> pinkaWalletSend({
  required String to,
  required String amount,
  required String sdkUrl,
}) async {
  await _loadSdk(sdkUrl);
  final sdk = _domovina;
  if (sdk == null) throw StateError('wallet_sdk_unavailable');
  final res = await sdk.send(_SendArgs(to: to, amount: amount)).toDart;
  return res.txHash;
}
