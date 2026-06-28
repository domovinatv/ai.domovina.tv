/// The gated entry points that can open the paywall. Each carries the Croatian
/// hero copy explaining why Plus unlocks that specific feature, so the paywall
/// is contextual rather than generic. Gates pass the trigger via `/subscribe`.
library;

enum UpgradeTrigger {
  generic,
  sync,
  offline,
  export,
  search,
  enFirst,
  magisterium,
  badge,
}

extension UpgradeTriggerCopy on UpgradeTrigger {
  /// Stable slug used in the `/subscribe?from=` query param.
  String get slug => name;

  static UpgradeTrigger fromSlug(String? slug) {
    for (final t in UpgradeTrigger.values) {
      if (t.name == slug) return t;
    }
    return UpgradeTrigger.generic;
  }

  String get headline => switch (this) {
        UpgradeTrigger.generic => 'Postani DOMOVINA Plus',
        UpgradeTrigger.sync => 'Sinkroniziraj na svim uređajima',
        UpgradeTrigger.offline => 'Slušaj i bez interneta',
        UpgradeTrigger.export => 'Izvezi transkripte i sažetke',
        UpgradeTrigger.search => 'Pretraga bez ograničenja',
        UpgradeTrigger.enFirst => 'Engleski uvijek prvi',
        UpgradeTrigger.magisterium => 'Puna Magisterium AI analiza',
        UpgradeTrigger.badge => 'Postani podupiratelj arhive',
      };

  String get subtitle => switch (this) {
        UpgradeTrigger.generic =>
          'Podrži hrvatsku arhivu i otključaj sve pogodnosti.',
        UpgradeTrigger.sync =>
          'Tvoji favoriti i mjesto gdje si stao prate te s telefona na web i natrag.',
        UpgradeTrigger.offline =>
          'Preuzmi epizode i poslušaj ih u avionu, autu ili dok putuješ.',
        UpgradeTrigger.export =>
          'Spremi transkript, sažetak ili članak kao PDF, Markdown ili DOCX.',
        UpgradeTrigger.search =>
          'Neograničena semantička pretraga i veći broj rezultata.',
        UpgradeTrigger.enFirst =>
          'Engleski prijevodi prikazani odmah, prije općeg objavljivanja.',
        UpgradeTrigger.magisterium =>
          'Detaljni Magisterium AI pregled i vidljivost izvora i upita.',
        UpgradeTrigger.badge =>
          'Bedž podupiratelja i tvoje ime na zidu zahvale.',
      };
}
