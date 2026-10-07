/// Grube teme epizode za sigurnost branda u izlogu sponzorskih trenutaka
/// (plan §3: „brand bira sam" — oznaka teme i filtar „ne prikazuj me uz…").
///
/// **Privremeno rješenje.** Ugovor v1 nema kategoriju epizode, a channel
/// listing nosi samo slobodne `topics` („demokracija i izbori", „katolički
/// susreti za samce"). Ovdje je zato eksplicitan popis korijena riječi nad
/// temama i naslovom. Nijedna epizoda se NE isključuje iz ponude; klasifikator
/// samo predlaže oznaku, a izlog uz nju uvijek prikazuje i stvarne teme, pa
/// brand vidi o čemu se razgovara i kad korijen promaši. Pravo mjesto za ovo
/// je kolona u `slots`/kampanji (ugovor v2) — tada ovaj fajl nestaje.
library;

enum SponsorTopic {
  faith,
  politics,
  business;

  /// Korijeni, mala slova, bez dijakritika (uspoređuje se nad
  /// [_fold]-anim tekstom). Kratki korijeni namjerno imaju granicu riječi da
  /// „izbor" ne uhvati „izborni" u kontekstu vjere i sl.
  List<RegExp> get _patterns => switch (this) {
    faith => [
      RegExp(r'katolic'),
      RegExp(r'\bvjer'),
      RegExp(r'crkv'),
      RegExp(r'duhovn'),
      RegExp(r'biblij'),
      RegExp(r'franj'),
      RegExp(r'\bmolit'),
      RegExp(r'svecen'),
    ],
    politics => [
      RegExp(r'politi'),
      RegExp(r'strank'),
      RegExp(r'\bizbor'),
      RegExp(r'birac'),
      RegExp(r'sabor'),
      RegExp(r'demokrac'),
      RegExp(r'lobiranj'),
    ],
    business => [
      RegExp(r'start-?up'),
      RegExp(r'poduzet'),
      RegExp(r'trzist'),
      RegExp(r'bank'),
      RegExp(r'financ'),
      RegExp(r'programir'),
      RegExp(r'blockchain'),
      RegExp(r'\bai\b'),
      RegExp(r'umjetna inteligencija'),
      RegExp(r'aplikacij'),
      RegExp(r'ekonom'),
    ],
  };

  /// Teme koje se prepoznaju u [topics] i [title].
  static Set<SponsorTopic> classify({
    required List<String> topics,
    String? title,
  }) {
    final text = _fold([...topics, ?title].join(' | '));
    return {
      for (final t in SponsorTopic.values)
        if (t._patterns.any((p) => p.hasMatch(text))) t,
    };
  }
}

String _fold(String s) {
  const from = 'čćšžđČĆŠŽĐ';
  const to = 'ccszdccszd';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString();
}
