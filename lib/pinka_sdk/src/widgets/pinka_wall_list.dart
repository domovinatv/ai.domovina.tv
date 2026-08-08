library;

import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../../../../l10n/app_localizations.dart';
import '../models/pinka_link_preview.dart';
import '../models/pinka_public_contribution.dart';
import '../util/pinka_money.dart';
import 'pinka_common.dart';

/// Razmak između pločica zida (i vodoravno i okomito).
const double kPinkaWallSpacing = 10;

/// Niska pločica (1 jedinica) — doprinos BEZ link previewa.
///
/// Kalibrirano na sadržaj: 28 px paddinga + redak imena/iznosa (20) + redak
/// poruke (4 + 16) = 68, uz rezervu za veći sistemski font. Većina doprinosa
/// na zidu nema ni poruku ni poveznicu, pa svaki višak visine ovdje izgleda
/// kao prazna kutija — zato je pločica niska, a sadržaj okomito centriran.
const double kPinkaWallShortTile = 84;

/// Visoka pločica (2 jedinice) — doprinos S link previewom.
///
/// **Mora** biti točno `2 * kPinkaWallShortTile + kPinkaWallSpacing`: samo tada
/// dvije niske pločice u stupcu poravnaju dno s jednom visokom, pa staggered
/// raspored nema rupa. Ako mijenjaš visine, drži ovaj odnos.
const double kPinkaWallTallTile =
    2 * kPinkaWallShortTile + kPinkaWallSpacing; // 178

/// Ciljna širina kartice — broj stupaca je `(maxWidth / ovo).floor()`.
const double kPinkaWallTargetCardWidth = 340;

/// "Zid podrške" — javni doprinosi, kronološki (najnoviji prvi), u staggered
/// mreži s **točno dvije dopuštene visine** kartice (niska bez preview-a,
/// visoka s preview-om). Visine su fiksne konstante pa je sav tekst clampan
/// (`maxLines` + elipsa); puni tekst i opis preview-a žive u detaljnom sheetu
/// koji se otvara tapom na karticu.
///
/// Novi unosi (u [flashIds]) dobiju kratku fade/slide "arrive" animaciju.
/// Bez vlastitog scrolla (host scrolla) — tri pozivna mjesta ovise o tome.
class PinkaWallList extends StatelessWidget {
  final List<PinkaPublicContribution> contributions;
  final Set<String> flashIds;

  const PinkaWallList({
    super.key,
    required this.contributions,
    this.flashIds = const {},
  });

  @override
  Widget build(BuildContext context) {
    // e2e/a11y sidro (flt-semantics-identifier u a11y DOM-u) — popis
    // podržavatelja; vidi komentar uz pinka-grid-wall u campaign screenu.
    return Semantics(
      identifier: 'pinka-wall-list',
      container: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final columns = (w.isFinite && w > 0)
              ? (w / kPinkaWallTargetCardWidth).floor().clamp(1, 4)
              : 1;
          return StaggeredGrid.count(
            crossAxisCount: columns,
            mainAxisSpacing: kPinkaWallSpacing,
            crossAxisSpacing: kPinkaWallSpacing,
            children: [
              for (final c in contributions)
                StaggeredGridTile.extent(
                  crossAxisCellCount: 1,
                  mainAxisExtent: _hasPreview(c)
                      ? kPinkaWallTallTile
                      : kPinkaWallShortTile,
                  child: _WallEntry(
                    contribution: c,
                    flash: flashIds.contains(c.id),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

bool _hasPreview(PinkaPublicContribution c) =>
    c.linkPreview != null && c.linkPreview!.hasContent;

/// Host bez `www.` — izvor preview-a u kartici (i fallback kad OG nema
/// `siteName`).
String _hostOf(String url) {
  final h = Uri.tryParse(url)?.host ?? '';
  return h.startsWith('www.') ? h.substring(4) : h;
}

/// Tekst poruke bez URL-a koji je izvor preview-a.
///
/// Bez ovoga se isti URL vidi dvaput: jednom kao (linkificirani) tekst poruke,
/// odmah ispod kao preview kartica. Mičemo i URL-ove s istim hostom, jer
/// preview URL zna biti razriješen redirect pa ne odgovara doslovno onome što
/// je donator upisao. Vraća `null` kad od poruke ne ostane ništa.
String? _messageWithoutPreviewUrl(PinkaPublicContribution c) {
  final raw = c.message?.trim();
  if (raw == null || raw.isEmpty) return null;
  final previewUrl = _hasPreview(c) ? c.linkPreview!.url : null;
  if (previewUrl == null) return raw;

  final previewHost = _hostOf(previewUrl);
  final stripped = raw.replaceAllMapped(
    RegExp(r'https?:\/\/[^\s]+'),
    (m) {
      final token = m.group(0)!;
      final same = token == previewUrl ||
          (previewHost.isNotEmpty && _hostOf(token) == previewHost);
      return same ? ' ' : token;
    },
  ).replaceAll(RegExp(r'\s+'), ' ').trim();

  return stripped.isEmpty ? null : stripped;
}

class _WallEntry extends StatelessWidget {
  final PinkaPublicContribution contribution;
  final bool flash;

  const _WallEntry({required this.contribution, required this.flash});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = contribution;
    final preview = _hasPreview(c) ? c.linkPreview! : null;
    final message = _messageWithoutPreviewUrl(c);

    final header = Row(
      children: [
        Expanded(
          child: Text(
            c.displayNameOrAnon(l),
            style:
                theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${fmtEur(c.amountCents)} €',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.tertiary,
          ),
        ),
      ],
    );

    final messageLine = message == null
        ? const <Widget>[]
        : <Widget>[
            const SizedBox(height: 4),
            // Namjerno OBIČAN Text, ne PinkaLinkify: cijela kartica je tap meta
            // za detaljni sheet, pa bi linkovi unutar nje otimali tap. Linkovi
            // (i puni tekst, bez clampa) žive u sheetu.
            Text(
              message,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ];

    // Ima li kartica išta skriveno? Doprinos bez poruke i bez preview-a je
    // cijeli vidljiv u pločici — takva kartica nije tap meta (sheet bi ponovio
    // isto) i ne nosi tooltip (inače hover po zidu vrišti "Prikaži cijelu
    // poruku" nad karticama koje je nemaju).
    final hasDetails = message != null || preview != null;

    // Dvije putanje jer je visina pločice fiksna, a sadržaj nije:
    // - VISOKA: preview je `Expanded` pa popuni ostatak pločice. Bez toga
    //   preview s jednoretčanim naslovom ostavi trećinu kartice praznom.
    //   Fiksni dio (ime + poruka) je uvijek ≪ pločice, pa overflow nije moguć.
    // - NISKA: sadržaj je okomito centriran (inače "ime + iznos" visi na vrhu
    //   prazne kutije), a OverflowBox je zaštita za velike sistemske fontove —
    //   višak se tada ODREŽE (Material clipBehavior) umjesto da baci overflow.
    // stretch svugdje: bez njega se preview steže na širinu svog teksta i
    // "pluta" u kartici fiksne širine.
    final body = Padding(
      padding: const EdgeInsets.all(14),
      child: preview != null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                ...messageLine,
                const SizedBox(height: 8),
                Expanded(child: _LinkPreviewCard(preview: preview)),
              ],
            )
          : OverflowBox(
              alignment: Alignment.centerLeft,
              minHeight: 0,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [header, ...messageLine],
              ),
            ),
    );

    final card = Material(
      color: flash
          ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.45)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: flash
              ? theme.colorScheme.tertiary.withValues(alpha: 0.5)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasDetails
          ? InkWell(
              onTap: () => showPinkaWallDetailsSheet(context, c),
              child: body,
            )
          : body,
    );

    final tappable = hasDetails
        ? Semantics(
            button: true,
            label: l.pinkaWallCardDetails,
            child: Tooltip(message: l.pinkaWallCardDetails, child: card),
          )
        : card;

    if (!flash) return tappable;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOut,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child),
      ),
      child: tappable,
    );
  }
}

/// Detaljni prikaz jednog doprinosa — ovdje ide sve što kartica mora clampati:
/// puni (linkificirani) tekst poruke, opis preview-a i gumb za otvaranje
/// poveznice.
Future<void> showPinkaWallDetailsSheet(
  BuildContext context,
  PinkaPublicContribution c,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _WallDetailsSheet(contribution: c),
  );
}

class _WallDetailsSheet extends StatelessWidget {
  final PinkaPublicContribution contribution;

  const _WallDetailsSheet({required this.contribution});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final c = contribution;
    final preview = _hasPreview(c) ? c.linkPreview! : null;
    final message = _messageWithoutPreviewUrl(c);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          // Rubni razmak IDE UNUTAR scrollabla (CLAUDE.md).
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.displayNameOrAnon(l),
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${fmtEur(c.amountCents)} €',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.tertiary,
                    ),
                  ),
                ],
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                PinkaLinkify(
                  text: message,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              if (preview != null) ...[
                const SizedBox(height: 16),
                _LinkPreviewCard(preview: preview, detailed: true),
                const SizedBox(height: 12),
                FilledButton.tonalIcon(
                  onPressed: () => pinkaLaunch(preview.url),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(l.pinkaWallOpenLink),
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.commonClose),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkPreviewCard extends StatelessWidget {
  final PinkaLinkPreview preview;

  /// U kartici zida (false) preview je samo prikaz — tap pripada kartici i
  /// otvara detaljni sheet. U sheetu (true) prikazuje i opis.
  final bool detailed;

  const _LinkPreviewCard({required this.preview, this.detailed = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final p = preview;
    final host = _hostOf(p.url);
    final source = (p.siteName?.trim().isNotEmpty ?? false)
        ? p.siteName!.trim()
        : (host.isNotEmpty ? host : l.pinkaLink);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$source ↗',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          if (p.title?.isNotEmpty ?? false) ...[
            const SizedBox(height: 2),
            Text(
              p.title!,
              maxLines: detailed ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          if (detailed && (p.description?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 4),
            Text(
              p.description!,
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
