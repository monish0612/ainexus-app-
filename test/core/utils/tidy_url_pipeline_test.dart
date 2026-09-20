import 'dart:io';

import 'package:ai_nexus/core/utils/tidy_url.dart';
import 'package:ai_nexus/data/services/price_watch/store_url.dart';
import 'package:ai_nexus/data/services/price_watch/watch_policy.dart';
import 'package:ai_nexus/data/services/price_watch/watch_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('battery contract', () {
    test('TidyUrl is CPU-only — no timers, HTTP, or WorkManager', () {
      final src = File('lib/core/utils/tidy_url.dart').readAsStringSync();
      expect(src.contains("import 'dart:async'"), isFalse);
      expect(src.contains("import 'package:dio"), isFalse);
      expect(src.contains("import 'package:workmanager"), isFalse);
      expect(src.contains('Timer('), isFalse);
      expect(src.contains('HttpClient'), isFalse);
    });

    test('Watch background floor stays 15 minutes', () {
      expect(kMinIntervalMinutes, 15);
      expect(kWatchFrequency, const Duration(minutes: 15));
      expect(kWatchFrequency.inMinutes >= kMinIntervalMinutes, isTrue);
    });

    test('duplicate share tokens collapse to one job key', () {
      const video = 'dQw4w9WgXcQ';
      final keys = {
        TidyUrl.summarizeJobKey(
          'https://youtu.be/$video?si=AbCdEf',
        ),
        TidyUrl.summarizeJobKey(
          'https://www.youtube.com/watch?v=$video&feature=share',
        ),
        TidyUrl.summarizeJobKey(
          'https://m.youtube.com/watch?v=$video&pp=0gcJCdgAo7VqN5tD',
        ),
        TidyUrl.summarizeJobKey(
          'https://music.youtube.com/watch?v=$video&si=xyz',
        ),
        TidyUrl.summarizeJobKey(
          'http://youtube.com/watch?v=$video',
        ),
        TidyUrl.summarizeJobKey(
          'https://www.youtube.com/shorts/$video?si=1',
        ),
        TidyUrl.summarizeJobKey(
          'https://www.youtube.com/embed/$video',
        ),
        TidyUrl.summarizeJobKey(
          'Check this https://youtu.be/$video?si=zz please',
        ),
      };
      expect(keys, hasLength(1));
      expect(keys.single, 'youtube.com/watch?v=$video');
    });

    test('normalize is cheap on a burst of share URLs', () {
      const raw =
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc&feature=share';
      final sw = Stopwatch()..start();
      for (var i = 0; i < 2000; i++) {
        TidyUrl.normalizeForSummarize(raw);
      }
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        lessThan(500),
        reason: 'TidyUrl must stay CPU-cheap so typing/share cannot drain radio',
      );
    });
  });

  group('intelligence', () {
    test('normalize is idempotent', () {
      const dirty = 'https://youtu.be/dQw4w9WgXcQ?si=x&t=43s';
      final once = TidyUrl.normalizeForSummarize(dirty);
      expect(TidyUrl.normalizeForSummarize(once), once);
    });

    test('YouTube playback extras drop so timestamp shares collide', () {
      expect(
        TidyUrl.normalizeForSummarize(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=43s&list=PLxx',
        ),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });

    test('YouTube live and nocookie embed collapse', () {
      expect(
        TidyUrl.normalizeForSummarize(
          'https://www.youtube.com/live/dQw4w9WgXcQ?si=1',
        ),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(
        TidyUrl.normalizeForSummarize(
          'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
        ),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });

    test('youtu.be without an 11-char id is not invented as /watch', () {
      expect(
        TidyUrl.normalizeForSummarize('https://youtu.be/watch'),
        'https://youtu.be/watch',
      );
    });

    test('Amazon slug+affiliate collapses to /dp/ASIN on the same host', () {
      expect(
        TidyUrl.normalizeForSummarize(
          'https://www.amazon.in/Alchemist-Paulo-Coelho/dp/8172234988/ref=sr_1_1?tag=aff-21&th=1',
        ),
        'https://www.amazon.in/dp/8172234988',
      );
      expect(
        TidyUrl.normalizeForSummarize('https://www.amazon.com/dp/B0CXXXXXXX?psc=1'),
        'https://www.amazon.com/dp/B0CXXXXXXX',
      );
    });

    test('Flipkart pid is kept for the summarizer fetch', () {
      expect(
        TidyUrl.normalizeForSummarize(
          'https://www.flipkart.com/foo/p/itmabc123?pid=MOBXYZ&affid=partner&utm_source=share',
        ),
        'https://www.flipkart.com/foo/p/itmabc123?pid=MOBXYZ',
      );
    });

    test('default https port is stripped so :443 collides', () {
      expect(
        TidyUrl.summarizeJobKey('https://example.com:443/a'),
        TidyUrl.summarizeJobKey('https://example.com/a'),
      );
    });

    test('Google/TikTok click ids do not fork the job', () {
      expect(
        TidyUrl.summarizeJobKey(
          'https://example.com/a?srsltid=AfmBOoo&gbraid=1&ttclid=2',
        ),
        TidyUrl.summarizeJobKey('https://www.example.com/a/'),
      );
    });
  });

  group('guards — do not steal other app flows', () {
    test('SMS / expense text is not a URL field', () {
      expect(
        TidyUrl.isUrlField(
          'INR 1,200.00 spent on HDFC Bank card XX1234. Avl Bal 9,000.00',
        ),
        isFalse,
      );
      expect(
        TidyUrl.extractSharedUrl(
          'INR 1,200.00 spent on HDFC Bank card XX1234. Avl Bal 9,000.00',
        ),
        isNull,
      );
    });

    test('sentence with a URL stays a search, not a summarize field', () {
      expect(
        TidyUrl.isUrlField('please summarize https://example.com/a for me'),
        isFalse,
      );
    });

    test('javascript and data URLs are rejected', () {
      expect(TidyUrl.isValidHttpUrl('javascript:alert(1)'), isFalse);
      expect(TidyUrl.isValidHttpUrl('data:text/html,hi'), isFalse);
      expect(TidyUrl.normalizeForSummarize('javascript:alert(1)'), isEmpty);
    });

    test('nuke easter egg is not a URL', () {
      expect(TidyUrl.isUrlField('nuke'), isFalse);
      expect(TidyUrl.normalizeForSummarize('nuke'), isEmpty);
    });

    test('Watch still owns Amazon.com → amazon.in, summarizer does not', () {
      expect(
        canonicalizeWatchUrl('https://www.amazon.com/dp/B0CXXXXXXX')?.url,
        'https://www.amazon.in/dp/B0CXXXXXXX',
      );
      expect(
        TidyUrl.normalizeForSummarize('https://www.amazon.com/dp/B0CXXXXXXX'),
        'https://www.amazon.com/dp/B0CXXXXXXX',
      );
    });

    test('userinfo is not forwarded to the backend', () {
      expect(
        TidyUrl.normalizeForSummarize('https://user:secret@example.com/page'),
        'https://example.com/page',
      );
    });

    test('extractUrls caps runaway pastes', () {
      final buf = StringBuffer();
      for (var i = 0; i < 40; i++) {
        buf.write('https://n$i.example.com ');
      }
      expect(TidyUrl.extractUrls(buf.toString()), hasLength(32));
    });
  });
}
