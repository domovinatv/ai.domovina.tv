import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/locale_service.dart';

/// HR/EN prebacivač UI JEZIKA u home app baru — uz ikonu teme.
/// Vidljiv svima, uključujući neautentificirane korisnike; odabir se sprema
/// lokalno (LocaleController, default hrvatski). MaterialApp sluša
/// LocaleController (vidi main.dart) pa se cijela aplikacija rebuilda na promjenu.
///
/// Imena jezika su endonimi ("Hrvatski"/"English") — NAMJERNO neprevedena, da ih
/// korisnik prepozna neovisno o trenutno aktivnom jeziku (standardni UX).
///
/// NB: ovo je jezik chrome-a (gumbi/naslovi/poruke), ODVOJEN od per-epizoda
/// jezika SADRŽAJA (widgets/language_toggle_chip.dart → CDN članak/Magisterium).
class LanguageToggleButton extends StatelessWidget {
  const LanguageToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: LocaleController.instance,
      builder: (context, _) {
        final current = LocaleController.instance.locale.languageCode;
        final l = AppLocalizations.of(context);
        return PopupMenuButton<String>(
          tooltip: l.authSectionLanguage,
          icon: const Icon(Icons.translate, size: 20),
          initialValue: current,
          onSelected: (code) =>
              LocaleController.instance.setLocale(Locale(code)),
          itemBuilder: (context) => [
            _item('hr', 'Hrvatski', current),
            _item('en', 'English', current),
          ],
        );
      },
    );
  }

  PopupMenuItem<String> _item(String code, String label, String current) {
    return PopupMenuItem<String>(
      value: code,
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child:
                code == current ? const Icon(Icons.check, size: 18) : null,
          ),
          Text(label),
        ],
      ),
    );
  }
}
