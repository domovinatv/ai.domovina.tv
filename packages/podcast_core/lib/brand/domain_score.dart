import 'app_brand.dart';

/// Domenska ocjena (Magisterium) iz JSON-a korpusa, ili `null` kad je brend
/// nema (`flags.domainScore == false`). Korpus je dijeljen, pa JSON kanala i
/// osoba nosi ocjenu i za brendove koji je ne prikazuju; filtrira se na
/// ulazu u model, da je nijedan ekran ne vidi.
int? domainScoreFromJson(Object? value) =>
    AppBrand.config.flags.domainScore ? (value as num?)?.round() : null;
