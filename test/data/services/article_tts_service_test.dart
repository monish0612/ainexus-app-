import 'package:ai_nexus/data/services/article_tts_service.dart';
import 'package:ai_nexus/domain/entities/news_entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ArticleTtsService — robustness when engine is unavailable', () {
    test('construction + speak/pause/resume/stop never throw with no engine',
        () async {
      // In the test host there is no native TTS engine, so init resolves to
      // "unavailable". The service must degrade gracefully (no unhandled
      // exception bubbling out of the tap callback) — this is the regression.
      final svc = ArticleTtsService();
      await expectLater(svc.speak('Hello world.'), completes);
      await expectLater(svc.pause(), completes);
      await expectLater(svc.resume(), completes);
      await expectLater(svc.stop(), completes);
      // State stays idle since playback never started.
      expect(svc.stateNotifier.value, TtsState.idle);
      expect(svc.isAvailable, isFalse);
      svc.dispose();
    });

    test('speak with empty text is a no-op', () async {
      final svc = ArticleTtsService();
      await expectLater(svc.speak(''), completes);
      expect(svc.stateNotifier.value, TtsState.idle);
      svc.dispose();
    });
  });

  group('extractSpeakableText', () {
    test('prefers summaryMarkdown with markdown stripped', () {
      const article = Article(
        id: 'a1',
        title: 'T',
        excerpt: 'fallback excerpt',
        source: 'src',
        category: 'AI News',
        imageUrl: '',
        readTime: 2,
        date: '2024-01-01',
        blocks: [],
        summaryMarkdown: '# Heading\n\n**Bold** and a [link](https://x.com) '
            'plus ![img](https://x.com/i.png) and `code`.',
      );
      final text = ArticleTtsService.extractSpeakableText(article);
      expect(text, isNot(contains('#')));
      expect(text, isNot(contains('**')));
      expect(text, isNot(contains('](')));
      expect(text, isNot(contains('![')));
      expect(text, contains('Heading'));
      expect(text, contains('Bold'));
      expect(text, contains('link'));
    });

    test('falls back to excerpt when there is no body content', () {
      const article = Article(
        id: 'a2',
        title: 'T',
        excerpt: 'the excerpt',
        source: 'src',
        category: 'AI News',
        imageUrl: '',
        readTime: 1,
        date: '2024-01-01',
        blocks: [],
      );
      expect(ArticleTtsService.extractSpeakableText(article), 'the excerpt');
    });
  });
}
