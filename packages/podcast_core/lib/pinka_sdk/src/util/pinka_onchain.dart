library;

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Client-side read-only on-chain pozivi (javni Gnosis RPC, bez ključa).
///
/// Živi EURe saldo campaign Safe-a: kumulativno "prikupljeno" (off-chain
/// ledger) samo raste, a vlasnik slobodno troši iz svog Safe-a — bez live
/// salda prikaz bi se dao napuhati jeftinim uplati-isplati ciklusima. Zato
/// verify kartica uz kumulativ pokazuje i stvarno trenutno stanje s lanca.

/// `balanceOf(address)` selektor (ERC-20).
const _balanceOfSelector = '0x70a08231';

/// Dohvati EURe saldo [address] u centima (EURe ima 18 decimala; 1 cent =
/// 1e16 wei, zaokruženo prema dolje). Vraća `null` na bilo koju grešku —
/// prikaz se tada jednostavno izostavi.
Future<int?> fetchEureBalanceCents({
  required String rpcUrl,
  required String eureAddress,
  required String address,
}) async {
  try {
    final addr = address.toLowerCase().replaceFirst('0x', '');
    final res = await http
        .post(
          Uri.parse(rpcUrl),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'eth_call',
            'params': [
              {
                'to': eureAddress,
                'data': '$_balanceOfSelector${addr.padLeft(64, '0')}',
              },
              'latest',
            ],
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final hex = (jsonDecode(res.body) as Map)['result'] as String?;
    if (hex == null || !hex.startsWith('0x')) return null;
    final wei = BigInt.parse(hex.substring(2), radix: 16);
    return (wei ~/ BigInt.from(10).pow(16)).toInt();
  } catch (_) {
    return null;
  }
}
