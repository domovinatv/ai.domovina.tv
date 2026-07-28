import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Avatar osobe u **kanal-formi**: postavljena slika ako postoji, inače
/// monogram (inicijali na navy gradijentu).
///
/// Gradijent je namjerno IDENTIČAN `_avatarPlaceholder`-u kartice kanala
/// (`lib/screens/home/channel_card.dart`) — osoba se u katalogu i na profilu
/// mora čitati kao ravnopravan kanal, a kanali bez cover-a već izgledaju ovako
/// (odluka O5 u `docs/plans/virtualni-kanali.md`). Zato ovdje NEMA rima ni
/// kruga: kartica kanala ih nema.
///
/// Osoba **nema cover** — to je značajka, ne rupa (O5), pa ovaj widget nikad ne
/// crta banner, samo kvadrat.
class PersonMonogram extends StatelessWidget {
  /// Puno ime — iz njega se izvode inicijali kad slike nema.
  final String name;

  /// Ručno postavljena slika osobe; `null`/prazno → monogram. Pucanje mreže
  /// također pada na monogram, pa avatar nikad ne ostane prazan kvadrat.
  final String? avatarUrl;

  final double size;

  /// Zaobljenje kvadrata. `size / 2` daje krug (koristi ga uski/mobilni hero).
  final double radius;

  const PersonMonogram({
    super.key,
    required this.name,
    this.avatarUrl,
    this.size = 96,
    this.radius = 14,
  });

  /// Inicijali imena — najviše dva slova ("Marijana Šarolić Robić" → "MR").
  /// Pandan `PersonSummary.initials`; ovdje kao statička funkcija jer widget
  /// prima i `PersonHub` (koji taj getter nema) i goli string.
  static String initialsOf(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) =>
            w.isNotEmpty && RegExp(r'^\p{L}', unicode: true).hasMatch(w))
        .toList(growable: false);
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl?.trim();
    final monogram = _monogram();
    if (url == null || url.isEmpty) return monogram;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(
        url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (ctx, e, s) => monogram,
      ),
    );
  }

  Widget _monogram() {
    final initials = initialsOf(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.croBlue,
            AppTheme.croBlue.withValues(alpha: 0.75),
          ],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      // Bez inicijala (ime je prazno ili samo interpunkcija) pada na istu
      // ikonu kojom kartica kanala popunjava prazan avatar.
      child: initials.isEmpty
          ? Icon(Icons.person,
              size: size * 0.4, color: Colors.white.withValues(alpha: 0.9))
          : Text(
              initials,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: size * 0.34,
                letterSpacing: 0.5,
              ),
            ),
    );
  }
}
