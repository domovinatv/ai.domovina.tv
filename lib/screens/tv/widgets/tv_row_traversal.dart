import 'package:flutter/material.dart';

/// D-pad traversal koji GORE/DOLJE uvijek pomiče na susjedni **redak**, a ne na
/// „najbliži čvor u smjeru".
///
/// Zašto: Flutterov ugrađeni directional traversal prvo traži kandidate koji se
/// vodoravno preklapaju s trenutnim čvorom, a tek ako ih nema pada na udaljenost.
/// Na TV home ekranu to znači da se rail s malo kartica **preskoči**: lane
/// „Osobe" ima dvije kartice uz lijevi rub, pa DOLJE s kartice u sredini
/// „Najnovijih epizoda" preleti preko njega ravno u mrežu kanala. Korisnik lane
/// nikad ne vidi ako ne dođe s lijevog stupca — a to je jedina površina na kojoj
/// osoba-kao-kanal postoji na TV-u.
///
/// Pravilo ove politike:
/// - **LIJEVO/DESNO** → nepromijenjeno, ide na `ReadingOrderTraversalPolicy`
///   (kretanje unutar raila / reda mreže mora ostati točno kakvo je bilo).
/// - **GORE/DOLJE** → svi fokusabilni čvorovi se grupiraju u retke po okomitom
///   preklapanju, pa se skače na susjedni redak i u njemu bira vodoravno
///   najbliža kartica (preklapanje stupca ima prednost pred pukom udaljenošću
///   središta). Nema li susjednog retka, intent se ne obrađuje i fokus ostaje —
///   isto ponašanje kao dosad na rubovima ekrana.
///
/// Scroll se NE radi ovdje: `TvFocusable` na dobivanju fokusa sam zove
/// `Scrollable.ensureVisible(alignment: 0.5)`, pa bi drugi poziv samo tukao
/// istu animaciju.
class TvRowTraversalPolicy extends ReadingOrderTraversalPolicy {
  @override
  bool inDirection(FocusNode currentNode, TraversalDirection direction) {
    if (direction == TraversalDirection.left ||
        direction == TraversalDirection.right) {
      return super.inDirection(currentNode, direction);
    }

    final scope = currentNode.nearestScope;
    if (scope == null) return super.inDirection(currentNode, direction);

    final candidates = scope.traversalDescendants
        .where((n) =>
            n.canRequestFocus &&
            !n.skipTraversal &&
            n.rect.width > 0 &&
            n.rect.height > 0)
        .toList(growable: false);
    if (candidates.length < 2) {
      return super.inDirection(currentNode, direction);
    }

    final rows = groupIntoRows(candidates);
    final index = rows.indexWhere((row) => row.contains(currentNode));
    // Fokus je izvan poznatih redaka (npr. čvor bez layouta) — pusti default.
    if (index < 0) return super.inDirection(currentNode, direction);

    final targetIndex =
        direction == TraversalDirection.down ? index + 1 : index - 1;
    if (targetIndex < 0 || targetIndex >= rows.length) return false;

    nearestInRow(rows[targetIndex], currentNode.rect).requestFocus();
    return true;
  }

  /// Grupiraj čvorove u retke: novi redak počinje čim čvor kreće ISPOD dna
  /// dosadašnjeg retka (bez okomitog preklapanja). Kartice u istom railu dijele
  /// `top` i visinu pa se grupiraju same; redovi `Wrap` mreže kanala su
  /// razdvojeni `runSpacing`-om pa se ne spajaju.
  @visibleForTesting
  static List<List<FocusNode>> groupIntoRows(List<FocusNode> nodes) {
    final sorted = [...nodes]..sort((a, b) {
        final byTop = a.rect.top.compareTo(b.rect.top);
        return byTop != 0 ? byTop : a.rect.left.compareTo(b.rect.left);
      });

    final rows = <List<FocusNode>>[];
    var rowBottom = double.negativeInfinity;
    for (final node in sorted) {
      if (rows.isEmpty || node.rect.top >= rowBottom) {
        rows.add(<FocusNode>[node]);
        rowBottom = node.rect.bottom;
      } else {
        rows.last.add(node);
        if (node.rect.bottom > rowBottom) rowBottom = node.rect.bottom;
      }
    }
    return rows;
  }

  /// Vodoravno najbliži čvor u ciljanom retku. Kandidati koji se preklapaju s
  /// trenutnim stupcem uvijek pobjeđuju (zadrži stupac pri kretanju gore/dolje);
  /// među njima odlučuje udaljenost središta.
  @visibleForTesting
  static FocusNode nearestInRow(List<FocusNode> row, Rect from) {
    var best = row.first;
    var bestScore = double.infinity;
    for (final node in row) {
      final r = node.rect;
      final gap = r.left > from.right
          ? r.left - from.right
          : (from.left > r.right ? from.left - r.right : 0.0);
      final score = gap * 1000 + (r.center.dx - from.center.dx).abs();
      if (score < bestScore) {
        bestScore = score;
        best = node;
      }
    }
    return best;
  }
}
