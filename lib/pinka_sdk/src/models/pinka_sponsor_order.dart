library;

/// Body grane `sponsor` u `pinka-contribute` — kupnja sponzorskog trenutka.
///
/// Ugovor: `domovina-api/docs/sponzorski-trenuci-ugovor.md` §5. Iznos se NE
/// šalje (server ga računa iz cijena trenutaka), a kupnja nikad nije anonimna
/// (DSA čl. 26): [brand] postaje javno ime platitelja.
class PinkaSponsorOrder {
  final String brand;
  final String? tagline;
  final String? linkUrl;

  /// Put u bucketu `sponsor-logos` (`<uid>/<id>.<ext>`), vidi
  /// [PinkaClient.uploadSponsorLogo].
  final String? logoPath;
  final bool termsAccepted;
  final PinkaSponsorBuyer buyer;

  const PinkaSponsorOrder({
    required this.brand,
    required this.termsAccepted,
    required this.buyer,
    this.tagline,
    this.linkUrl,
    this.logoPath,
  });

  Map<String, dynamic> toJson() => {
    'brand': brand.trim(),
    if (_has(tagline)) 'tagline': tagline!.trim(),
    if (_has(linkUrl)) 'link_url': linkUrl!.trim(),
    if (_has(logoPath)) 'logo_path': logoPath,
    'terms_accepted': termsAccepted,
    'buyer': buyer.toJson(),
  };
}

/// Podaci tvrtke za račun. Ne pojavljuju se ni u jednom javnom viewu.
class PinkaSponsorBuyer {
  final String company;
  final String? oib;
  final String? vatId;
  final String email;
  final String? street;
  final String? city;
  final String? postalCode;

  /// ISO alpha-2; server zadaje `HR` kad izostane.
  final String? country;

  /// PO broj — ide na račun.
  final String? reference;

  const PinkaSponsorBuyer({
    required this.company,
    required this.email,
    this.oib,
    this.vatId,
    this.street,
    this.city,
    this.postalCode,
    this.country,
    this.reference,
  });

  Map<String, dynamic> toJson() {
    final address = {
      if (_has(street)) 'street': street!.trim(),
      if (_has(city)) 'city': city!.trim(),
      if (_has(postalCode)) 'postal_code': postalCode!.trim(),
      if (_has(country)) 'country': country!.trim().toUpperCase(),
    };
    return {
      'company': company.trim(),
      if (_has(oib)) 'oib': oib!.trim(),
      if (_has(vatId)) 'vat_id': vatId!.replaceAll(' ', '').toUpperCase(),
      'email': email.trim(),
      if (address.isNotEmpty) 'address': address,
      if (_has(reference)) 'reference': reference!.trim(),
    };
  }
}

bool _has(String? s) => s != null && s.trim().isNotEmpty;

/// Odbijena narudžba. [code] je prefiks greške do prve dvotočke
/// (`invalid_sponsor`, `too_many_holds`, …), a [detail] ostatak
/// (`buyer_oib` kod `invalid_sponsor:buyer_oib`). Sudar oko trenutka ide kao
/// zaseban [PinkaSlotTaken], jer ga UI rješava drukčije (natrag na kartu).
class PinkaSponsorRejected implements Exception {
  final String code;
  final String? detail;
  final int? status;

  const PinkaSponsorRejected(this.code, {this.detail, this.status});

  @override
  String toString() =>
      'PinkaSponsorRejected($code${detail == null ? '' : ':$detail'})';
}

/// HR OIB (ISO 7064 MOD 11,10) — ista provjera koju radi server, da forma
/// grešku javi prije mreže.
bool isValidOib(String raw) {
  final s = raw.trim();
  if (!RegExp(r'^\d{11}$').hasMatch(s)) return false;
  var a = 10;
  for (var i = 0; i < 10; i++) {
    a = (a + int.parse(s[i])) % 10;
    if (a == 0) a = 10;
    a = (a * 2) % 11;
  }
  var check = 11 - a;
  if (check == 10) check = 0;
  return check == int.parse(s[10]);
}
