import 'brand_config.dart';
import 'domovina_brand.dart';

/// Aktivni brend procesa. Postavlja ga `runPodcastApp(brand)` prije prvog
/// framea; jezgra ga čita kroz [config]. Zadano je [domovinaBrand] da
/// postojeći testovi i alati rade bez eksplicitne inicijalizacije.
class AppBrand {
  AppBrand._();

  static BrandConfig _config = domovinaBrand;

  static BrandConfig get config => _config;

  /// Jednom, na startu. Testovi smiju pozvati više puta (npr. da provjere
  /// drugi brend), aplikacija ne.
  static void init(BrandConfig brand) => _config = brand;
}
