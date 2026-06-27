library;

/// Native/non-JS stub. DOMOVINA in-app wallet je dostupan samo na webu.
const bool kPinkaWalletSupported = false;

/// Uvijek baca — pozivatelj mora prvo provjeriti [kPinkaWalletSupported].
Future<String> pinkaWalletConnect({required String sdkUrl}) {
  throw UnsupportedError('DOMOVINA wallet je dostupan samo na webu.');
}

/// Uvijek baca — pozivatelj mora prvo provjeriti [kPinkaWalletSupported].
Future<String> pinkaWalletSend({
  required String to,
  required String amount,
  required String sdkUrl,
}) {
  throw UnsupportedError('DOMOVINA wallet send je dostupan samo na webu.');
}
