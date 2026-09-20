import 'package:ai_nexus/core/utils/tidy_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('extractUrls', () {
    test('finds a single URL', () {
      expect(
        TidyUrl.extractUrls('Check this: https://example.com/page'),
        ['https://example.com/page'],
      );
    });

    test('finds multiple URLs', () {
      expect(
        TidyUrl.extractUrls(
          'See https://one.com and also https://two.com/path',
        ),
        ['https://one.com', 'https://two.com/path'],
      );
    });

    test('strips trailing punctuation', () {
      expect(
        TidyUrl.extractUrls(
          'Check https://a.com/x, then (https://b.com/y). Done.',
        ),
        ['https://a.com/x', 'https://b.com/y'],
      );
    });

    test('keeps trailing bang when it is part of the path', () {
      expect(
        TidyUrl.extractUrls('Read https://en.wikipedia.org/wiki/Yahoo!'),
        ['https://en.wikipedia.org/wiki/Yahoo!'],
      );
    });

    test('strips trailing bang when it is punctuation', () {
      expect(
        TidyUrl.extractUrls('Go to https://example.com! It is awesome.'),
        ['https://example.com'],
      );
    });

    test('returns empty when no URL', () {
      expect(TidyUrl.extractUrls('no links here'), isEmpty);
    });

    test('deduplicates', () {
      expect(
        TidyUrl.extractUrls('https://a.com/x\nhttps://a.com/x'),
        ['https://a.com/x'],
      );
    });

    test('extracts from quotes and brackets', () {
      expect(
        TidyUrl.extractUrls(
          '(https://example.com/page) or \'https://example.com\' '
          'link and "https://example.org"',
        ),
        [
          'https://example.com/page',
          'https://example.com',
          'https://example.org',
        ],
      );
    });

    test('preserves punctuation inside query', () {
      expect(
        TidyUrl.extractUrls(
          'Look at https://example.com/page?query=hello.world,foo!#section,1. '
          'And this: https://example.com/api?a=1,2,3.',
        ),
        [
          'https://example.com/page?query=hello.world,foo!#section,1',
          'https://example.com/api?a=1,2,3',
        ],
      );
    });

    test('extracts urls glued to preceding text', () {
      expect(
        TidyUrl.extractUrls(
          'visit:https://example.com or link=https://example.org/path',
        ),
        ['https://example.com', 'https://example.org/path'],
      );
    });
  });

  group('extractSharedUrl', () {
    test('returns first URL from mixed text', () {
      expect(
        TidyUrl.extractSharedUrl('hey check https://youtu.be/abc123 please'),
        'https://youtu.be/abc123',
      );
    });

    test('accepts a bare domain', () {
      expect(TidyUrl.extractSharedUrl(' example.com '), 'example.com');
    });

    test('rejects trailing punctuation on a bare domain', () {
      expect(TidyUrl.extractSharedUrl('bad.example,'), isNull);
    });

    test('rejects free text', () {
      expect(TidyUrl.extractSharedUrl('just a sentence'), isNull);
    });
  });

  group('cleanUrl', () {
    test('strips utm and tracking params', () {
      expect(
        TidyUrl.cleanUrl(
          'https://example.com/page?utm_source=x&id=5&fbclid=abc',
        ),
        'https://example.com/page?id=5',
      );
    });

    test('strips YouTube si token', () {
      expect(
        TidyUrl.cleanUrl('https://youtu.be/dQw4w9WgXcQ?si=AbCdEf'),
        'https://youtu.be/dQw4w9WgXcQ',
      );
    });

    test('strips YouTube feature=share', () {
      expect(
        TidyUrl.cleanUrl(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc123&feature=share',
        ),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });

    test('YouTube Music watch is cleaned but host stays until summarize', () {
      expect(
        TidyUrl.cleanUrl('https://music.youtube.com/watch?v=abc&si=xyz'),
        'https://music.youtube.com/watch?v=abc',
      );
    });

    test('strips Reddit tracking params', () {
      expect(
        TidyUrl.cleanUrl(
          'https://www.reddit.com/r/HowToMen/comments/123/post'
          '?rdt=54321&sh=abcdef&context=3',
        ),
        'https://www.reddit.com/r/HowToMen/comments/123/post',
      );
    });

    test('adds https and lowercases host', () {
      expect(
        TidyUrl.cleanUrl('HTTPS://EXAMPLE.com/Path'),
        'https://example.com/Path',
      );
    });

    test('strips trailing slash', () {
      expect(
        TidyUrl.cleanUrl('https://example.com/a/'),
        'https://example.com/a',
      );
    });

    test('keeps SPA hash routes', () {
      expect(
        TidyUrl.cleanUrl('https://example.com/#/settings/profile'),
        'https://example.com#/settings/profile',
      );
      expect(
        TidyUrl.cleanUrl('https://example.com/#!/photos'),
        'https://example.com#!/photos',
      );
    });

    test('drops plain anchors', () {
      expect(
        TidyUrl.cleanUrl('https://example.com/page#section-2'),
        'https://example.com/page',
      );
    });

    test('drops query when only tracking remains', () {
      expect(
        TidyUrl.cleanUrl(
          'https://example.com/page?utm_source=x&utm_medium=y',
        ),
        'https://example.com/page',
      );
    });

    test('preserves explicit port', () {
      expect(
        TidyUrl.cleanUrl('https://example.com:8443/api'),
        'https://example.com:8443/api',
      );
    });

    test('unparseable input falls back to scheme-prefixed raw', () {
      expect(TidyUrl.cleanUrl('not a url'), 'https://not a url');
    });
  });

  group('dedupeKey', () {
    test('collapses https www and tracking', () {
      expect(
        TidyUrl.dedupeKey('http://www.example.com/a/'),
        'example.com/a',
      );
      expect(
        TidyUrl.dedupeKey('https://example.com/a?utm_campaign=x'),
        'example.com/a',
      );
    });

    test('collapses YouTube share variants', () {
      expect(
        TidyUrl.dedupeKey(
          'https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=abc',
        ),
        TidyUrl.dedupeKey('https://youtube.com/watch?v=dQw4w9WgXcQ'),
      );
    });

    test('different pages stay distinct', () {
      expect(
        TidyUrl.dedupeKey('https://example.com/a'),
        isNot(TidyUrl.dedupeKey('https://example.com/b')),
      );
    });
  });

  group('isValidHttpUrl', () {
    test('accepts real hosts', () {
      expect(TidyUrl.isValidHttpUrl('https://example.com'), isTrue);
      expect(TidyUrl.isValidHttpUrl('example.com'), isTrue);
    });

    test('rejects free text', () {
      expect(TidyUrl.isValidHttpUrl('hello'), isFalse);
      expect(TidyUrl.isValidHttpUrl('just some text'), isFalse);
      expect(TidyUrl.isValidHttpUrl('hello world.com'), isFalse);
    });
  });

  group('isUrlField', () {
    test('whole field url', () {
      expect(TidyUrl.isUrlField('https://example.com/a'), isTrue);
      expect(TidyUrl.isUrlField('youtu.be/abc'), isTrue);
    });

    test('url plus wrapping punctuation', () {
      expect(TidyUrl.isUrlField('https://example.com.'), isTrue);
    });

    test('sentence with a url is not a url field', () {
      expect(
        TidyUrl.isUrlField('summarize this https://example.com please'),
        isFalse,
      );
    });
  });

  group('normalizeForSummarize', () {
    test('extracts and cleans share text', () {
      expect(
        TidyUrl.normalizeForSummarize(
          'Check this https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=xyz',
        ),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
    });

    test('collapses youtu.be and YouTube Music onto youtube.com/watch', () {
      expect(
        TidyUrl.normalizeForSummarize(
          'https://youtu.be/dQw4w9WgXcQ?si=AbCdEf',
        ),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(
        TidyUrl.normalizeForSummarize(
          'https://music.youtube.com/watch?v=dQw4w9WgXcQ&si=xyz',
        ),
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      );
      expect(
        TidyUrl.dedupeKey(
          TidyUrl.normalizeForSummarize(
            'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
          ),
        ),
        TidyUrl.dedupeKey(
          TidyUrl.normalizeForSummarize(
            'https://www.youtube.com/watch?v=dQw4w9WgXcQ&si=1',
          ),
        ),
      );
    });
  });

  group('placeholderTitle', () {
    test('strips scheme and www', () {
      expect(
        TidyUrl.placeholderTitle('https://www.example.com/page/'),
        'example.com/page',
      );
    });
  });

  group('hostMatches', () {
    test('matches subdomains and ignores path text', () {
      expect(
        TidyUrl.hostMatches('https://m.youtube.com/watch?v=1', ['youtube.com']),
        isTrue,
      );
      expect(
        TidyUrl.hostMatches(
          'https://example.com/youtube.com?q=youtu.be',
          ['youtube.com', 'youtu.be'],
        ),
        isFalse,
      );
      expect(TidyUrl.hostOf('not a url'), '');
    });
  });
}
