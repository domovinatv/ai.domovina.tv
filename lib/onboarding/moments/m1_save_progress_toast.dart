/// M1 — First episode toast: "Tvoj napredak se sprema na ovaj uređaj".
/// Pokaže se jednom (per user), 4 sekunde, dismissible.
library;

import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../services/onboarding_state.dart';

const _momentId = 'm1';

Future<void> maybeShowM1(BuildContext context) async {
  if (await OnboardingState.instance.hasSeen(_momentId)) return;
  await OnboardingState.instance.markSeen(_momentId);
  if (!context.mounted) return;

  final l = AppLocalizations.of(context);
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          const Icon(Icons.devices, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              l.authM1Toast,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      duration: const Duration(seconds: 4),
      backgroundColor: const Color(0xFF002F6C),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: l.commonOk,
        textColor: Colors.white,
        onPressed: () {},
      ),
    ),
  );
}
