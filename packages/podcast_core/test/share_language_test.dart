import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:podcast_core/models/channel_detail.dart';
import 'package:podcast_core/services/channel_cache.dart';
import 'package:podcast_core/services/episode_language.dart';
import 'package:podcast_core/services/share_language.dart';
import 'package:podcast_core/services/share_links.dart';

/// Ugovor jezika share linka na karticama IZVAN episode ekrana.
///
/// Dva uvjeta moraju vrijediti istovremeno da bi link bio engleski: korisnik je
/// izabrao engleski I za tu epizodu znamo da prijevod postoji. Drugi uvjet je
/// bitan jer `/v/<id>/en` za neprevedenu epizodu tehnički radi (padne na HR) —
/// pa bi bez njega link obećavao engleski i otvarao hrvatski.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChannelVideo video(String id, {bool? articleEn}) => ChannelVideo(
        id: id,
        title: 'Naslov',
        date: '2026-09-15',
        pipeline: articleEn == null
            ? null
            : VideoPipeline(
                hasTranscript: true,
                hasDiarized: true,
                hasSummary: true,
                hasArticle: true,
                hasMagisterium: false,
                hasArticleEn: articleEn,
              ),
      );

  void seed(List<ChannelVideo> videos) {
    channelCache.seedForTest(ChannelDetail(
      version: '1.0',
      id: 'kanal',
      name: 'Kanal',
      youtubeChannelUrl: 'https://youtube.com/@kanal',
      videoCount: videos.length,
      totalDurationSeconds: 0,
      videos: videos,
    ));
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PreferredEpisodeLanguage.instance.resetForTest();
    channelCache.resetForTest();
  });

  test('bez korisnikova izbora ostaje hrvatski', () {
    seed([video('a1', articleEn: true)]);
    expect(shareLanguageForVideo('a1'), EpisodeLanguage.hr);
  });

  test('korisnik na HR — engleski se ne nudi ni kad prijevod postoji',
      () async {
    await PreferredEpisodeLanguage.instance.remember(EpisodeLanguage.hr);
    seed([video('a1', articleEn: true)]);
    expect(shareLanguageForVideo('a1'), EpisodeLanguage.hr);
  });

  test('korisnik na EN + zastavica podignuta → engleski link', () async {
    await PreferredEpisodeLanguage.instance.remember(EpisodeLanguage.en);
    seed([video('a1', articleEn: true)]);
    expect(shareLanguageForVideo('a1'), EpisodeLanguage.en);
    expect(
      episodeShareUrl('a1', lang: shareLanguageForVideo('a1')),
      'https://domovina.ai/v/a1/en',
    );
  });

  test('korisnik na EN, ali zastavica spuštena → hrvatski '
      '(link ne smije obećati prijevod kojeg nema)', () async {
    await PreferredEpisodeLanguage.instance.remember(EpisodeLanguage.en);
    seed([video('a1', articleEn: false)]);
    expect(shareLanguageForVideo('a1'), EpisodeLanguage.hr);
  });

  test('epizoda nije u cacheu → hrvatski, ne pretpostavljamo', () async {
    await PreferredEpisodeLanguage.instance.remember(EpisodeLanguage.en);
    expect(shareLanguageForVideo('nepoznat'), EpisodeLanguage.hr);
  });

  test('video bez pipeline bloka → hrvatski', () async {
    await PreferredEpisodeLanguage.instance.remember(EpisodeLanguage.en);
    seed([video('a1')]);
    expect(shareLanguageForVideo('a1'), EpisodeLanguage.hr);
  });

  group('VideoPipeline.hasArticleEn', () {
    test('čita has_article_en', () {
      final p = VideoPipeline.fromJson({'has_article_en': true});
      expect(p.hasArticleEn, isTrue);
    });

    test('prihvaća i stariji sinonim has_translation_en', () {
      final p = VideoPipeline.fromJson({'has_translation_en': true});
      expect(p.hasArticleEn, isTrue);
    });

    test('izostanak polja NIJE tvrdnja da prijevoda nema — samo ne nudimo EN',
        () {
      final p = VideoPipeline.fromJson({'has_article': true});
      expect(p.hasArticleEn, isFalse);
    });
  });

  group('PreferredEpisodeLanguage', () {
    test('savePreferredLanguage osvježava singleton — inače bi share link do '
        'restarta nudio stari jezik', () async {
      expect(PreferredEpisodeLanguage.instance.value, isNull);
      await savePreferredLanguage(EpisodeLanguage.en);
      expect(PreferredEpisodeLanguage.instance.value, EpisodeLanguage.en);
      await savePreferredLanguage(EpisodeLanguage.hr);
      expect(PreferredEpisodeLanguage.instance.value, EpisodeLanguage.hr);
    });

    test('null (nije birao) i hr (izabrao) se ne stapaju', () async {
      expect(PreferredEpisodeLanguage.instance.value, isNull);
      await PreferredEpisodeLanguage.instance.remember(EpisodeLanguage.hr);
      expect(PreferredEpisodeLanguage.instance.value, EpisodeLanguage.hr);
    });

    test('javlja listenerima na promjenu', () async {
      var notified = 0;
      void listener() => notified++;
      PreferredEpisodeLanguage.instance.addListener(listener);
      addTearDown(
          () => PreferredEpisodeLanguage.instance.removeListener(listener));
      await PreferredEpisodeLanguage.instance.remember(EpisodeLanguage.en);
      expect(notified, 1);
      // Ista vrijednost ponovno — bez nepotrebnog rebuilda.
      await PreferredEpisodeLanguage.instance.remember(EpisodeLanguage.en);
      expect(notified, 1);
    });
  });
}
