/// M3 — Inline prompt nakon prvog dodavanja favorita: "Spremam lokalno.
/// Sinkroniziraj na sve uređaje?". Snackbar s "Sinkroniziraj" akcijom.
library;

import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/onboarding_state.dart';
import '../ui/auth_sheet.dart';

const _momentId = 'm3';

Future<void> maybeShowM3OnFavorite(BuildContext context) async {
  if (await OnboardingState.instance.hasSeen(_momentId)) return;
  if (!AuthService.instance.isAnonymous) return;
  await OnboardingState.instance.markSeen(_momentId);
  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Row(
        children: [
          Icon(Icons.favorite, color: Color(0xFFFF0000), size: 20),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Spremljeno na ovaj uređaj. Sinkroniziraj favorite na sve uređaje?',
            ),
          ),
        ],
      ),
      duration: const Duration(seconds: 6),
      behavior: SnackBarBehavior.floating,
      action: SnackBarAction(
        label: 'SINKRONIZIRAJ',
        onPressed: () {
          showAuthSheet(context, origin: AuthSheetOrigin.moment3);
        },
      ),
    ),
  );
}
