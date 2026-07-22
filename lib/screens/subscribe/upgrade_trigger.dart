/// The gated entry points that can open the paywall. Each carries the Croatian
/// hero copy explaining why Plus unlocks that specific feature, so the paywall
/// is contextual rather than generic. Gates pass the trigger via `/subscribe`.
library;

import '../../l10n/app_localizations.dart';

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

  String headline(AppLocalizations l) => switch (this) {
        UpgradeTrigger.generic => l.channelTriggerGenericHeadline,
        UpgradeTrigger.sync => l.channelTriggerSyncHeadline,
        UpgradeTrigger.offline => l.channelTriggerOfflineHeadline,
        UpgradeTrigger.export => l.channelTriggerExportHeadline,
        UpgradeTrigger.search => l.channelTriggerSearchHeadline,
        UpgradeTrigger.enFirst => l.channelTriggerEnFirstHeadline,
        UpgradeTrigger.magisterium => l.channelTriggerMagisteriumHeadline,
        UpgradeTrigger.badge => l.channelTriggerBadgeHeadline,
      };

  String subtitle(AppLocalizations l) => switch (this) {
        UpgradeTrigger.generic => l.channelTriggerGenericSubtitle,
        UpgradeTrigger.sync => l.channelTriggerSyncSubtitle,
        UpgradeTrigger.offline => l.channelTriggerOfflineSubtitle,
        UpgradeTrigger.export => l.channelTriggerExportSubtitle,
        UpgradeTrigger.search => l.channelTriggerSearchSubtitle,
        UpgradeTrigger.enFirst => l.channelTriggerEnFirstSubtitle,
        UpgradeTrigger.magisterium => l.channelTriggerMagisteriumSubtitle,
        UpgradeTrigger.badge => l.channelTriggerBadgeSubtitle,
      };
}
