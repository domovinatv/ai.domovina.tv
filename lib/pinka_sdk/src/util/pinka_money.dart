library;

/// EUR iz cent-integera (hr-locale: zarez kao decimalni separator, bez
/// nepotrebnih decimala za okrugle iznose). `500 → "5"`, `1250 → "12,50"`.
String fmtEur(int cents) {
  final eur = cents / 100;
  final whole = eur.truncateToDouble() == eur;
  return eur.toStringAsFixed(whole ? 0 : 2).replaceAll('.', ',');
}

/// Korisnički unos ("12,50" ili "12.50") → centi; `null` ako nevaljano/≤0.
int? parseEurToCents(String raw) {
  final n = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (n == null || n <= 0) return null;
  return (n * 100).round();
}
