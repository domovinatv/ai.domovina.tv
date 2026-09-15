import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';

/// Wrapa [child] i otvara mali "share" context menu na **desktop desni-klik**
/// (`onSecondaryTapDown`) i **mobitel long-press** (`onLongPressStart`), oba na
/// poziciji gesta. Zajednički za kartice kanala i epizoda.
///
/// Zasad jedna stavka — "Kopiraj poveznicu" (kopira [url] u međuspremnik +
/// snackbar potvrda). Menu se lako proširuje dodatnim `PopupMenuItem`-ima.
///
/// NB (Flutter web): browser po defaultu prikaže svoj native context menu na
/// desni klik pa bi zasjenio ovaj. Gasi se globalno u `main.dart`
/// (`BrowserContextMenu.disableContextMenu()`); bez toga se ovaj menu ne vidi.
class ShareContextMenu extends StatelessWidget {
  /// Poveznica koja se kopira (npr. `https://domovina.ai/c/<slug>` ili
  /// `https://domovina.ai/v/<id>`).
  ///
  /// Gradi se u trenutku KLIKA, ne u buildu: jezik share linka ovisi o
  /// preferenciji koja se može promijeniti dok kartica stoji živa ispod u
  /// navigacijskom stogu (`push` drži ekran ispod montiranim — vidi CLAUDE.md
  /// „Routing i navigacijski stog"). Da se URL računao u buildu, kartica bi do
  /// idućeg rebuilda kopirala jezik koji korisnik više ne koristi.
  final String Function() url;

  /// Opcionalna specifična snackbar poruka; default `commonLinkCopied`.
  final String? copiedMessage;

  final Widget child;

  /// [url] je fiksan string koji se ne mijenja kroz život widgeta
  /// (npr. poveznica kanala ili osobe).
  ShareContextMenu({
    super.key,
    required String url,
    required this.child,
    this.copiedMessage,
  }) : url = (() => url);

  /// [urlBuilder] se zove pri svakom kopiranju — za poveznice čiji sadržaj
  /// ovisi o stanju koje se mijenja (jezik, pozicija playera).
  const ShareContextMenu.lazy({
    super.key,
    required String Function() urlBuilder,
    required this.child,
    this.copiedMessage,
  }) : url = urlBuilder;

  Future<void> _show(BuildContext context, Offset globalPosition) async {
    final l = AppLocalizations.of(context);
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.link, size: 18),
              const SizedBox(width: 10),
              Text(l.commonCopyLink),
            ],
          ),
        ),
      ],
    );
    if (selected == 'copy' && context.mounted) _copy(context);
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: url()));
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(copiedMessage ?? l.commonLinkCopied),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapDown: (d) => _show(context, d.globalPosition),
      onLongPressStart: (d) => _show(context, d.globalPosition),
      child: child,
    );
  }
}
