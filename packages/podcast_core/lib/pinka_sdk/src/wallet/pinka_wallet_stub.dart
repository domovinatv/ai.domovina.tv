library;

/// Native/non-JS stub. Ugrađeni (in-app) novčanik dostupan je samo na webu.
const bool kPinkaWalletSupported = false;

/// Uvijek baca — pozivatelj mora prvo provjeriti [kPinkaWalletSupported].
Future<String> pinkaWalletConnect({required String sdkUrl}) {
  throw UnsupportedError('Ugrađeni novčanik dostupan je samo na webu.');
}

/// Uvijek baca — pozivatelj mora prvo provjeriti [kPinkaWalletSupported].
Future<String> pinkaWalletSend({
  required String to,
  required String amount,
  required String sdkUrl,
}) {
  throw UnsupportedError(
      'Slanje iz ugrađenog novčanika dostupno je samo na webu.');
}
