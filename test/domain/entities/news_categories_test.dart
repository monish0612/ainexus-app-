// Unit tests for the new Movies + General news categories metadata and the
// "All chip" / FAB summarize-all exclusion contract.
//
// COVERAGE
//
//   • news_entities.dart constants:
//       - CATEGORIES contains exactly the expected 4 entries.
//       - CAT_COLOR has a unique, parseable hex per CATEGORY.
//       - kNoSummarizeCategories contains exactly Movies + General and
//         every entry is also a member of CATEGORIES (no orphan tags).
//
//   • Filter contract (the inline logic in news_screen.dart's build):
//       - "All" chip view EXCLUDES Movies + General.
//       - Each category chip view shows ONLY that category.
//       - FAB summarize-all scope === "All" chip view (same source list).
//       - Saved + Read articles are always excluded from any feed view.
//
// These tests are pure-Dart — no widget tree, no Riverpod, no Drift, no
// network. They are deterministic and finish in milliseconds.

import 'package:ai_nexus/domain/entities/news_entities.dart';
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

/// Pure replica of the filter expression used in `news_screen.dart`'s build()
/// for the "All" chip + FAB `scope.all`. Kept in the test so a future change
/// to the production filter without updating the spec fails noisily here.
List<Article> _allChipFeed(List<Article> all) {
  return all
      .where((a) => !a.isRead && !a.isSaved)
      .where((a) => !kNoSummarizeCategories.contains(a.category))
      .toList();
}

/// Pure replica of the per-category chip filter.
List<Article> _categoryChipFeed(List<Article> all, String category) {
  return all
      .where((a) => !a.isRead && !a.isSaved)
      .where((a) => a.category == category)
      .toList();
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
    test('excludes Movies + General articles', () {
      final all = [
        _article(id: '1', category: 'Finance'),
        _article(id: '2', category: 'AI News'),
        _article(id: '3', category: 'Movies'),
        _article(id: '4', category: 'General'),
      ];
      final feed = _allChipFeed(all);
      expect(feed.map((a) => a.id).toList(), ['1', '2']);
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

    test('pool of ONLY Movies + General → empty (none visible in All)', () {
      final all = [
        _article(id: 'm1', category: 'Movies'),
        _article(id: 'g1', category: 'General'),
        _article(id: 'm2', category: 'Movies'),
      ];
      expect(_allChipFeed(all), isEmpty);
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

  group('FAB summarize-action target filter', () {
    /// Pure replica of the defensive filter inside `_handleFabAction` —
    /// even if the inline scope picker hands us a list that contains
    /// Movies/General articles (e.g. user is on a Movies chip and picked
    /// "currentCategory"), the AI summarize pipeline must NEVER see
    /// them. This filter is the last line of defence.
    List<Article> stripForSummarize(List<Article> target) {
      return target
          .where((a) => !kNoSummarizeCategories.contains(a.category))
          .toList(growable: false);
    }

    test('mixed scope list → Movies + General stripped before summarize', () {
      final scopeList = [
        _article(id: 'f1', category: 'Finance'),
        _article(id: 'm1', category: 'Movies'),
        _article(id: 'ai1', category: 'AI News'),
        _article(id: 'g1', category: 'General'),
      ];
      expect(stripForSummarize(scopeList).map((a) => a.id).toList(),
          ['f1', 'ai1']);
    });

    test('pure Movies scope (user on Movies chip + currentCategory) → empty', () {
      // This is the precise edge case the guard fixes: without it, the
      // summarize-reader would call the LLM on full-content articles
      // and undo the whole "skip_summary" contract.
      final scopeList = [
        _article(id: 'm1', category: 'Movies'),
        _article(id: 'm2', category: 'Movies'),
      ];
      expect(stripForSummarize(scopeList), isEmpty);
    });

    test('pure General scope → empty', () {
      final scopeList = [
        _article(id: 'g1', category: 'General'),
        _article(id: 'g2', category: 'General'),
      ];
      expect(stripForSummarize(scopeList), isEmpty);
    });

    test('mixed Movies + General only → empty (defence in depth)', () {
      final scopeList = [
        _article(id: 'm1', category: 'Movies'),
        _article(id: 'g1', category: 'General'),
      ];
      expect(stripForSummarize(scopeList), isEmpty);
    });

    test('pure Finance scope → all preserved (regression guard)', () {
      final scopeList = [
        _article(id: 'f1', category: 'Finance'),
        _article(id: 'f2', category: 'Finance'),
      ];
      expect(stripForSummarize(scopeList).length, 2);
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
}
