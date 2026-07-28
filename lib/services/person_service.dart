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

  /// Indeks svih osoba koje se prikazuju kao virtualni kanal (§4.1 plana
  /// `docs/plans/virtualni-kanali.md`). Endpoint stiže s F2 — dotad vraća 404
  /// i [loadIndex] daje `null` (feature ostaje nevidljiv, ništa ne puca).
  static const String _indexEndpoint = 'https://mcp.domovina.ai/api/persons';

  static final http.Client _client = http.Client();

  /// Dohvat indeksa osoba. Vraća `null` kad indeks nije dostupan (404 na
  /// starom backendu, HTTP greška, timeout, neispravan JSON) — pozivatelj
  /// tada radi kao da osoba-kao-kanal ne postoji.
  ///
  /// Endpoint vraća `Cache-Control: public, max-age=900`; app-level cache je
  /// [PersonIndexCache], ne CDN `?v=` bucket (odluka O1).
  static Future<PersonIndex?> loadIndex({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final uri = Uri.parse(_indexEndpoint);
    try {
      final resp = await _client.get(uri).timeout(timeout);
      if (resp.statusCode == 404) {
        log('PersonService: /api/persons 404 — backend još nema person index');
        return null;
      }
      if (resp.statusCode != 200) {
        log('PersonService: /api/persons HTTP ${resp.statusCode}');
        return null;
      }
      final body =
          jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
      final index = PersonIndex.fromJson(body);
      log('PersonService: index — ${index.persons.length} osoba, '
          '${index.virtualChannels.length} virtualnih kanala');
      return index;
    } on TimeoutException {
      log('PersonService: timeout na /api/persons');
      return null;
    } catch (e) {
      log('PersonService: greška na /api/persons: $e');
      return null;
    }
  }

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
