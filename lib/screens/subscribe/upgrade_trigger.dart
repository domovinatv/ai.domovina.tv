/// The gated entry points that can open the paywall. Each carries the hero copy
/// explaining why Plus unlocks that specific feature, so the paywall is
/// contextual rather than generic. Gates pass the trigger via `/subscribe`.
///
/// Only triggers backed by a feature that actually exists today may live here —
/// a contextual headline is a purchase claim, and `/subscribe?from=<slug>` is a
/// publicly reachable URL. Triggers for planned features (offline, export, …)
/// were removed 2026-07-31; those links now fall back to [generic].
library;

import '../../l10n/app_localizations.dart';

enum UpgradeTrigger {
  generic,
  search,
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
        UpgradeTrigger.search => l.channelTriggerSearchHeadline,
        UpgradeTrigger.badge => l.channelTriggerBadgeHeadline,
      };

  String subtitle(AppLocalizations l) => switch (this) {
        UpgradeTrigger.generic => l.channelTriggerGenericSubtitle,
        UpgradeTrigger.search => l.channelTriggerSearchSubtitle,
        UpgradeTrigger.badge => l.channelTriggerBadgeSubtitle,
      };
}
