import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../main.dart' show log;
import '../models/person_hub.dart';

/// Klijent za javni person-hub endpoint (domovina-rag).
///
/// `GET https://mcp.domovina.ai/api/person/{slug}` — isti no-auth/CORS wrapper
/// kao `/api/search` (vidi [SearchService]). Bez autha, bez headera. Čisti
/// HTTP GET pa radi i na webu (--wasm) i na native-u.
///
/// Endpoint vraća `Cache-Control: public, max-age=300` — profil je
/// deterministički do sljedećeg ingesta.
class PersonService {
  /// Base URL person API-ja. Mijenja se ovdje ako se host promijeni.
  static const String _endpoint = 'https://mcp.domovina.ai/api/person';

  static final http.Client _client = http.Client();

  /// Dohvat profila govornika po slug-u. Vraća `null` na 404 (osoba ne
  /// postoji), grešku ili timeout (graceful) — ekran tada pokaže prazno stanje.
  static Future<PersonHub?> fetch(
    String slug, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final s = slug.trim();
    if (s.isEmpty) return null;

    // Slug se koristi DOSLOVNO — encode-amo samo path segment radi sigurnosti.
    final uri = Uri.parse('$_endpoint/${Uri.encodeComponent(s)}');

    try {
      final resp = await _client.get(uri).timeout(timeout);
      if (resp.statusCode == 404) {
        log('PersonService: 404 za "$s" (osoba ne postoji)');
        return null;
      }
      if (resp.statusCode != 200) {
        log('PersonService: HTTP ${resp.statusCode} za "$s"');
        return null;
      }
      final body =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final hub = PersonHub.fromJson(body);
      log('PersonService: "${hub.name}" — ${hub.episodeCount} epizoda / '
          '${hub.channelCount} kanala');
      return hub;
    } on TimeoutException {
      log('PersonService: timeout za "$s"');
      return null;
    } catch (e) {
      log('PersonService: greška za "$s": $e');
      return null;
    }
  }
}
