library;

/// In-app DOMOVINA wallet bridge — uvjetni import.
///
/// On-chain EURe send iz korisnikova DOMOVINA novčanika (`wallet.domovina.ai`
/// iframe + WebAuthn passkey) je **web-only**: na native platformama nema
/// `window.Domovina`, pa se koristi stub koji baca [UnsupportedError]. UI uvijek
/// nudi i EIP-681 QR fallback (skeniraj vanjskim novčanikom), pa je in-app send
/// samo "convenience" put.
///
/// Gate je `dart.library.js_interop` (NE `dart.library.html`) zbog `--wasm`
/// builda — vidi memory `feedback_wasm_conditional_imports`.
export 'pinka_wallet_stub.dart'
    if (dart.library.js_interop) 'pinka_wallet_web.dart';
