/// The gated entry points that can open the paywall. Each carries the Croatian
/// hero copy explaining why Plus unlocks that specific feature, so the paywall
/// is contextual rather than generic. Gates pass the trigger via `/subscribe`.
library;

import '../../services/locale_service.dart';

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
        UpgradeTrigger.generic => appStrings.channelTriggerGenericHeadline,
        UpgradeTrigger.sync => appStrings.channelTriggerSyncHeadline,
        UpgradeTrigger.offline => appStrings.channelTriggerOfflineHeadline,
        UpgradeTrigger.export => appStrings.channelTriggerExportHeadline,
        UpgradeTrigger.search => appStrings.channelTriggerSearchHeadline,
        UpgradeTrigger.enFirst => appStrings.channelTriggerEnFirstHeadline,
        UpgradeTrigger.magisterium =>
          appStrings.channelTriggerMagisteriumHeadline,
        UpgradeTrigger.badge => appStrings.channelTriggerBadgeHeadline,
      };

  String get subtitle => switch (this) {
        UpgradeTrigger.generic => appStrings.channelTriggerGenericSubtitle,
        UpgradeTrigger.sync => appStrings.channelTriggerSyncSubtitle,
        UpgradeTrigger.offline => appStrings.channelTriggerOfflineSubtitle,
        UpgradeTrigger.export => appStrings.channelTriggerExportSubtitle,
        UpgradeTrigger.search => appStrings.channelTriggerSearchSubtitle,
        UpgradeTrigger.enFirst => appStrings.channelTriggerEnFirstSubtitle,
        UpgradeTrigger.magisterium =>
          appStrings.channelTriggerMagisteriumSubtitle,
        UpgradeTrigger.badge => appStrings.channelTriggerBadgeSubtitle,
      };
}
