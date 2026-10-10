import 'package:podcast_core/widgets/episode_video.dart';
import 'package:flutter_test/flutter_test.dart';

/// Titl se nikad ne reže (5.10.2026.: do tada `maxLines: 3` + ellipsis) —
/// korisnici čitaju dok slušaju. Font se smanjuje tek kad tekst ne stane.
void main() {
  const longCue =
      'Ovo je dugačak titl koji u malom playeru zauzima puno više od tri '
      'reda, jer govornik priča bez stanke i svaka riječ mora ostati vidljiva '
      'na ekranu dok je korisnik čita i sluša u isto vrijeme.';

  test('kratak titl zadrži osnovni font', () {
    expect(
      fittingSubtitleFontSize('Kratko.', 16, maxWidth: 300, maxHeight: 100),
      16,
    );
  });

  test('dugačak titl u niskom playeru smanji font da stane', () {
    final size = fittingSubtitleFontSize(
      longCue,
      16,
      maxWidth: 280,
      maxHeight: 90,
    );
    expect(size, lessThan(16));
    expect(size, greaterThanOrEqualTo(9));
  });

  test('ima li mjesta, font se ne dira ni za dugačak titl', () {
    expect(
      fittingSubtitleFontSize(longCue, 16, maxWidth: 280, maxHeight: 400),
      16,
    );
  });
}
