library;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../../l10n/app_localizations.dart';
import '../models/pinka_contribution_intent.dart';
import 'pinka_common.dart';

/// SEPA upute za jedan intent: iznos, EPC QR, IBAN, primatelj i opis plaćanja.
///
/// Dijele ga donacijski panel ([PinkaContributePanel]) i checkout sponzorskog
/// trenutka — ispod njega svaki host stavlja svoje (odbrojavanje holda,
/// napredak raila, upute za korporativni nalog).
class PinkaSepaQr extends StatelessWidget {
  final PinkaContributionIntent intent;

  /// Dodatak ispod opisa plaćanja (npr. „kopiraj doslovno").
  final Widget? memoNote;

  const PinkaSepaQr({super.key, required this.intent, this.memoNote});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          l.pinkaScanInBankApp,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.pinkaAmountLabel(intent.amountEur),
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        PinkaQrBox(data: intent.epcQrData),
        const SizedBox(height: 10),
        PinkaCopyRow(
          label: 'IBAN',
          value: pinkaFormatIban(intent.iban),
          copyValue: pinkaCleanIban(intent.iban),
        ),
        PinkaCopyRow(label: l.pinkaRecipient, value: intent.beneficiaryName),
        PinkaCopyRow(
          label: l.pinkaPaymentReference,
          value: intent.memo,
          multiline: true,
        ),
        ?memoNote,
      ],
    );
  }
}

/// QR na bijeloj podlozi; veličina prati širinu panela.
class PinkaQrBox extends StatelessWidget {
  final String data;

  const PinkaQrBox({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (_, c) => QrImageView(
          data: data,
          version: QrVersions.auto,
          // Raste sa širinom panela (desni stupac 400 px → ~260), ali ne ispod
          // pouzdanog skena ni preko razumne veličine na mobitelu.
          size: c.maxWidth.isFinite ? c.maxWidth.clamp(180.0, 260.0) : 220,
          errorCorrectionLevel: QrErrorCorrectLevel.M,
        ),
      ),
    );
  }
}

/// Rail API zna vratiti IBAN s proizvoljnim razmacima (npr. zadnje dvije
/// znamenke odvojene) — normaliziraj pa grupiraj po 4 za čitljiv prikaz.
String pinkaCleanIban(String iban) => iban.replaceAll(RegExp(r'\s+'), '');

String pinkaFormatIban(String iban) {
  final clean = pinkaCleanIban(iban);
  final sb = StringBuffer();
  for (var i = 0; i < clean.length; i += 4) {
    if (i > 0) sb.write(' ');
    sb.write(clean.substring(i, i + 4 > clean.length ? clean.length : i + 4));
  }
  return sb.toString();
}
