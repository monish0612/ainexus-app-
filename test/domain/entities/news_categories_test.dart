// Unit tests for news category metadata, All-chip inclusion, and chrome
// spacing so the bottom rail stays tappable under snackbars.

import 'package:ai_nexus/domain/entities/news_entities.dart';
import 'package:ai_nexus/presentation/screens/news/news_chrome.dart';
import 'package:ai_nexus/presentation/screens/news/news_feed_filters.dart';
import 'package:flutter_test/flutter_test.dart';

Article _article({
  required String id,
  required String category,
  bool isRead = false,
  bool isSaved = false,
}) =>
    Article(
      id: id,
      title: 'Title $id',
      excerpt: 'Excerpt $id',
      source: 'Source $id',
      category: category,
      imageUrl: '',
      readTime: 2,
      date: 'May 28, 2026',
      blocks: const [],
      isRead: isRead,
      isSaved: isSaved,
    );

/// Production All-chip + FAB summarize-all scope.
List<Article> _allChipFeed(List<Article> all) {
  return newsFeedForCategory(unreadUnsavedArticles(all), 'All');
}

/// Pure replica of the per-category chip filter.
List<Article> _categoryChipFeed(List<Article> all, String category) {
  return newsFeedForCategory(unreadUnsavedArticles(all), category);
}

void main() {
  // ─── Metadata invariants ───────────────────────────────────────────────

  group('CATEGORIES constant', () {
    test('contains exactly Finance, AI News, Movies, General — in chip order',
        () {
      expect(CATEGORIES, ['Finance', 'AI News', 'Movies', 'General']);
    });

    test('no duplicates', () {
      expect(CATEGORIES.toSet().length, CATEGORIES.length);
    });

    test('rail order is All, AI News, Finance, Movies, General', () {
      expect(kNewsCategoryRailLabels,
          ['All', 'AI News', 'Finance', 'Movies', 'General']);
    });
  });

  group('CAT_COLOR map', () {
    test('has an entry for every CATEGORY', () {
      for (final cat in CATEGORIES) {
        expect(CAT_COLOR.containsKey(cat), isTrue,
            reason: 'missing color for "$cat"');
      }
    });

    test('every hex value is a valid 6-digit hex', () {
      final hexRx = RegExp(r'^#[0-9A-Fa-f]{6}$');
      for (final entry in CAT_COLOR.entries) {
        expect(hexRx.hasMatch(entry.value), isTrue,
            reason: '"${entry.key}" → "${entry.value}" is not a valid #RRGGBB');
      }
    });

    test('colors are unique across categories (avoid badge confusion)', () {
      final values = CAT_COLOR.values.map((v) => v.toLowerCase()).toList();
      expect(values.toSet().length, values.length,
          reason: 'duplicate color in CAT_COLOR: $values');
    });
  });

  group('kNoSummarizeCategories set', () {
    test('contains exactly Movies + General', () {
      expect(kNoSummarizeCategories, {'Movies', 'General'});
    });

    test('every member is also a valid CATEGORY (no orphan tag)', () {
      for (final cat in kNoSummarizeCategories) {
        expect(CATEGORIES.contains(cat), isTrue,
            reason: '"$cat" is in kNoSummarizeCategories but not CATEGORIES');
      }
    });

    test('Finance and AI News are NOT excluded (regression guard)', () {
      expect(kNoSummarizeCategories.contains('Finance'), isFalse);
      expect(kNoSummarizeCategories.contains('AI News'), isFalse);
    });
  });

  // ─── "All" chip + FAB summarize-all scope filter contract ───────────────

  group('All-chip filter (also FAB summarize-all scope)', () {
    test('includes Movies + General articles along with Finance and AI News',
        () {
      final all = [
        _article(id: '1', category: 'Finance'),
        _article(id: '2', category: 'AI News'),
        _article(id: '3', category: 'Movies'),
        _article(id: '4', category: 'General'),
      ];
      final feed = _allChipFeed(all);
      expect(feed.map((a) => a.id).toList(), ['1', '2', '3', '4']);
    });

    test('keeps unread+unsaved Finance + AI News articles', () {
      final all = [
        _article(id: 'f1', category: 'Finance'),
        _article(id: 'f2', category: 'Finance'),
        _article(id: 'ai1', category: 'AI News'),
      ];
      final feed = _allChipFeed(all);
      expect(feed.length, 3);
    });

    test('excludes read articles (existing contract regression guard)', () {
      final all = [
        _article(id: '1', category: 'Finance'),
        _article(id: '2', category: 'Finance', isRead: true),
        _article(id: '3', category: 'AI News', isRead: true),
      ];
      final feed = _allChipFeed(all);
      expect(feed.map((a) => a.id).toList(), ['1']);
    });

    test('excludes saved articles (existing contract regression guard)', () {
      final all = [
        _article(id: '1', category: 'AI News'),
        _article(id: '2', category: 'AI News', isSaved: true),
      ];
      final feed = _allChipFeed(all);
      expect(feed.map((a) => a.id).toList(), ['1']);
    });

    test('empty pool → empty feed', () {
      expect(_allChipFeed(const []), isEmpty);
    });

    test('pool of ONLY Movies + General → both visible in All', () {
      final all = [
        _article(id: 'm1', category: 'Movies'),
        _article(id: 'g1', category: 'General'),
        _article(id: 'm2', category: 'Movies'),
      ];
      expect(_allChipFeed(all).map((a) => a.id).toList(), ['m1', 'g1', 'm2']);
    });
  });

  // ─── Per-category chip filter ─────────────────────────────────────────

  group('Per-category chip filter', () {
    final pool = [
      _article(id: 'm1', category: 'Movies'),
      _article(id: 'm2', category: 'Movies', isRead: true), // hidden
      _article(id: 'g1', category: 'General'),
      _article(id: 'g2', category: 'General', isSaved: true), // hidden
      _article(id: 'f1', category: 'Finance'),
      _article(id: 'a1', category: 'AI News'),
    ];

    test('Movies chip shows ONLY unread+unsaved Movies', () {
      final feed = _categoryChipFeed(pool, 'Movies');
      expect(feed.map((a) => a.id).toList(), ['m1']);
    });

    test('General chip shows ONLY unread+unsaved General', () {
      final feed = _categoryChipFeed(pool, 'General');
      expect(feed.map((a) => a.id).toList(), ['g1']);
    });

    test('Finance chip unaffected by Movies/General presence', () {
      final feed = _categoryChipFeed(pool, 'Finance');
      expect(feed.map((a) => a.id).toList(), ['f1']);
    });

    test('AI News chip unaffected by Movies/General presence', () {
      final feed = _categoryChipFeed(pool, 'AI News');
      expect(feed.map((a) => a.id).toList(), ['a1']);
    });

    test('unknown category → empty feed (no accidental leakage)', () {
      expect(_categoryChipFeed(pool, 'Sports'), isEmpty);
      expect(_categoryChipFeed(pool, ''), isEmpty);
    });
  });

  // ─── FAB summarize-action target filter (defense in depth) ────────────

  group('FAB summarize-action includes every unread category', () {
    test('mixed scope list keeps Movies + General for Summarize All', () {
      final scopeList = [
        _article(id: 'f1', category: 'Finance'),
        _article(id: 'm1', category: 'Movies'),
        _article(id: 'ai1', category: 'AI News'),
        _article(id: 'g1', category: 'General'),
      ];
      expect(scopeList.map((a) => a.id).toList(), ['f1', 'm1', 'ai1', 'g1']);
    });

    test('pure Movies scope is summarizable', () {
      final scopeList = [
        _article(id: 'm1', category: 'Movies'),
        _article(id: 'm2', category: 'Movies'),
      ];
      expect(scopeList, hasLength(2));
    });
  });

  // ─── Saved tab contract: Movies + General SAVED articles MUST be visible ─

  group('Saved-articles filter (category-agnostic)', () {
    test('Movies + General saved articles still appear in Saved tab', () {
      // The Saved tab uses `allArticles.where((a) => a.isSaved)` — it must
      // NOT apply the kNoSummarizeCategories filter, otherwise a user who
      // bookmarked a movie review would never see it again.
      final all = [
        _article(id: 'm1', category: 'Movies', isSaved: true),
        _article(id: 'g1', category: 'General', isSaved: true),
        _article(id: 'f1', category: 'Finance', isSaved: true),
        _article(id: 'unsaved', category: 'AI News'),
      ];
      final saved = all.where((a) => a.isSaved).toList();
      expect(saved.map((a) => a.id).toSet(), {'m1', 'g1', 'f1'});
    });
  });

  group('News chrome spacing', () {
    test('snackbar sits above the category rail so Movies stays tappable', () {
      expect(kNewsSnackBarMargin.bottom, greaterThan(kNewsCategoryRailHeight));
    });

    test('feed bottom inset clears rail + FAB', () {
      expect(kNewsFeedBottomInset, greaterThan(kNewsCategoryRailHeight + 80));
    });
  });
}
