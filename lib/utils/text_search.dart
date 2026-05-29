/// Tekstualne normalizacije za lokalnu (offline) pretragu.
///
/// Hrvatski search MORA biti dijakritik-neosjetljiv: "Zizek" treba naći
/// "Žižek", "cuspajz" treba naći "Čušpajž". Flutter/`fuzzy` ne radi to sam,
/// pa normaliziramo i upit i ključeve prije usporedbe.
library;

/// Mapa hrvatskih (i čestih stranih) dijakritika na ASCII ekvivalente.
const Map<String, String> _foldMap = {
  'č': 'c', 'ć': 'c', 'ç': 'c',
  'š': 's', 'ś': 's',
  'ž': 'z', 'ź': 'z',
  'đ': 'd', // dž se prirodno fold-a kroz d + z
  'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
  'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
  'ñ': 'n',
};

/// Lowercase + fold dijakritika → usporedivi ASCII oblik.
String foldText(String input) {
  final lower = input.toLowerCase();
  final buf = StringBuffer();
  for (final ch in lower.split('')) {
    buf.write(_foldMap[ch] ?? ch);
  }
  return buf.toString();
}

/// Deterministički lokalni match scorer. Vraća score > 0 ako se SVI tokeni
/// upita pojavljuju u (foldanom) tekstu; viši = bolji (prefiks/cijela riječ
/// vrijede više). 0 = nema matcha.
///
/// Token-AND semantika je predvidljivija od fuzzy-ja za kratke upite i ne
/// vraća slučajne false-positive rezultate.
double localMatchScore(String query, String haystack) {
  final q = foldText(query).trim();
  if (q.isEmpty) return 0;
  final hay = foldText(haystack);
  if (hay.isEmpty) return 0;

  final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
  double total = 0;
  for (final token in tokens) {
    final idx = hay.indexOf(token);
    if (idx < 0) return 0; // svaki token mora biti prisutan (AND)
    // Bonus: match na granici riječi (početak ili nakon razmaka) vrijedi više.
    final atWordStart = idx == 0 || hay[idx - 1] == ' ';
    total += atWordStart ? 2.0 : 1.0;
    // Bonus za duže tokene (specifičniji upit).
    total += token.length / 20.0;
  }
  return total;
}
