/// Hrvatska zastavica crtana kroz [CustomPaint] — ikona „zastavice" iz streak
/// mehanike glasanja (`docs/plans/2026-08-08-glasanje-o-kanalima.md` §6.1).
///
/// **Zašto crtamo, a ne emoji i ne asset:**
/// * 🇭🇷 je par regional-indicator znakova — Windows Chrome nema glif za njih i
///   umjesto zastavice iscrta dva slova („HR"). Isti problem ima i dio Androida.
/// * PNG asset bi tražio izmjenu `pubspec.yaml`, a `flutter_svg` puca na webu
///   (CLAUDE.md). `CustomPaint` je jedina putanja bez zajedničke točke i bez
///   web zamke — usput je i rezolucijski neovisan.
///
/// Boje su brand tokeni (`AppTheme.croRed` / `AppTheme.croBlue`) — isti izvor
/// kao logo, pa se zastavica i brand ne raziđu.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Omjer stranica državne zastavice (1:2).
const double kZastavicaAspect = 2.0;

/// Hrvatska zastavica: trobojnica + pojednostavljena šahovnica.
///
/// [ispunjena] `false` crta prazno mjesto (obris + prigušene pruge) — mjesto
/// zastavice koja je potrošena ili je korisnik još nema.
class HrvatskaZastavica extends StatelessWidget {
  /// Visina zastavice u dp; širina je `visina * 2`.
  final double visina;

  final bool ispunjena;

  /// Semantički opis (npr. „1 od 2 zastavice"). Bez njega je widget dekoracija
  /// i čitač ekrana ga preskače — tekst uz zastavicu ionako nosi značenje.
  final String? semantickiOpis;

  const HrvatskaZastavica({
    super.key,
    this.visina = 14,
    this.ispunjena = true,
    this.semantickiOpis,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final painter = _ZastavicaPainter(
      ispunjena: ispunjena,
      prigusena: cs.onSurfaceVariant.withValues(alpha: 0.30),
      obrub: cs.outlineVariant,
    );
    final slika = CustomPaint(
      size: Size(visina * kZastavicaAspect, visina),
      painter: painter,
      isComplex: false,
    );
    if (semantickiOpis == null) {
      return ExcludeSemantics(child: slika);
    }
    return Semantics(label: semantickiOpis, image: true, child: slika);
  }
}

class _ZastavicaPainter extends CustomPainter {
  final bool ispunjena;
  final Color prigusena;
  final Color obrub;

  const _ZastavicaPainter({
    required this.ispunjena,
    required this.prigusena,
    required this.obrub,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final traka = h / 3;
    final radius = Radius.circular(h * 0.10);
    final okvir = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      radius,
    );

    canvas.save();
    canvas.clipRRect(okvir);

    final crvena = ispunjena ? AppTheme.croRed : prigusena;
    final bijela = ispunjena ? Colors.white : prigusena.withValues(alpha: 0.12);
    final plava = ispunjena ? AppTheme.croBlue : prigusena;

    final p = Paint()..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, traka), p..color = crvena);
    canvas.drawRect(Rect.fromLTWH(0, traka, w, traka), p..color = bijela);
    canvas.drawRect(Rect.fromLTWH(0, traka * 2, w, h - traka * 2),
        p..color = plava);

    // Šahovnica — 5×5 polja u središtu. Državni grb ima 13×5 polja i krunu;
    // na 14 dp visine ništa od toga nije čitljivo, pa crtamo prepoznatljiv
    // uzorak umjesto nečitljive kaše.
    final grbStr = h * 0.56;
    final lijevo = (w - grbStr) / 2;
    final gore = (h - grbStr) / 2;
    final polje = grbStr / 5;

    canvas.drawRect(
      Rect.fromLTWH(lijevo, gore, grbStr, grbStr),
      p..color = ispunjena ? Colors.white : prigusena.withValues(alpha: 0.20),
    );

    p.color = ispunjena ? AppTheme.croRed : prigusena.withValues(alpha: 0.55);
    for (var red = 0; red < 5; red++) {
      for (var stupac = 0; stupac < 5; stupac++) {
        if ((red + stupac).isEven) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            lijevo + stupac * polje,
            gore + red * polje,
            polje,
            polje,
          ),
          p,
        );
      }
    }

    canvas.restore();

    canvas.drawRRect(
      okvir.deflate(0.25),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = ispunjena ? obrub : obrub.withValues(alpha: 0.8),
    );
  }

  @override
  bool shouldRepaint(_ZastavicaPainter old) =>
      old.ispunjena != ispunjena ||
      old.prigusena != prigusena ||
      old.obrub != obrub;
}
