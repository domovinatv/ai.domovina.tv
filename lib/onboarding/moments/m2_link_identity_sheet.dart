/// M2 — Nakon 30s slušanja: bottom sheet "Spremi napredak na sve uređaje".
/// Pokaže se jednom (per user, samo za anonymous).
library;

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/onboarding_state.dart';
import '../ui/auth_sheet.dart';

const _momentId = 'm2';

Future<void> maybeShowM2(BuildContext context) async {
  if (await OnboardingState.instance.hasSeen(_momentId)) return;
  if (!AuthService.instance.isAnonymous) return;
  if (!context.mounted) return;

  await OnboardingState.instance.markSeen(_momentId);

  // Mali delay da ne smetuje pri samoj reprodukciji
  await Future.delayed(const Duration(milliseconds: 200));
  if (!context.mounted) return;

  await showAuthSheet(
    context,
    origin: AuthSheetOrigin.moment2,
  );
}
