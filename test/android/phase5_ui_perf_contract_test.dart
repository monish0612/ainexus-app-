import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks Phase 5 UI-performance contracts against the live files.
void main() {
  late String bottomNav;
  late String appShell;
  late String newsScreen;
  late String newsSaved;
  late String cloudScreen;
  late String addWatch;
  late String glass;
  late String appToast;

  setUpAll(() {
    bottomNav =
        File('lib/presentation/widgets/bottom_nav.dart').readAsStringSync();
    appShell =
        File('lib/presentation/widgets/app_shell.dart').readAsStringSync();
    newsScreen =
        File('lib/presentation/screens/news/news_screen.dart').readAsStringSync();
    newsSaved = File('lib/presentation/screens/news/news_saved_page.dart')
        .readAsStringSync();
    cloudScreen = File('lib/presentation/screens/cloud/cloud_screen.dart')
        .readAsStringSync();
    addWatch = File('lib/presentation/screens/watch/add_watch_sheet.dart')
        .readAsStringSync();
    glass = File('lib/bubble/overlay/glass.dart').readAsStringSync();
    appToast =
        File('lib/presentation/widgets/app_toast.dart').readAsStringSync();
  });

  group('5.1 / 5.2 BackdropFilter', () {
    test('dark bottom nav does not pay for a zero-sigma blur', () {
      expect(RegExp(r'ImageFilter\.blur\(\s*\)').hasMatch(bottomNav), isFalse);
      expect(bottomNav.contains('if (!colors.isDark)'), isTrue);
      expect(bottomNav.contains('BackdropFilter('), isTrue);
      expect(bottomNav.contains('sigmaX: 12'), isTrue);
    });

    test('opaque summary pill no longer wraps a BackdropFilter', () {
      expect(newsScreen.contains('ui.ImageFilter.blur'), isFalse);
    });

    test('overlay glass still skips BackdropFilter when blur is 0', () {
      expect(glass.contains('if (widget.blur <= 0) return child;'), isTrue);
    });

    test('app toast still has no BackdropFilter widget', () {
      expect(appToast.contains('child: BackdropFilter('), isFalse);
    });
  });

  group('5.3 IndexedStack tickers', () {
    test('each tab is wrapped in TickerMode keyed to the current index', () {
      expect(appShell.contains('IndexedStack('), isTrue);
      expect(appShell.contains('TickerMode('), isTrue);
      expect(appShell.contains('enabled: currentTab == i'), isTrue);
    });
  });

  group('5.5 / 5.6 image memory', () {
    const cachedSites = [
      'lib/presentation/screens/news/news_screen.dart',
      'lib/presentation/screens/news/news_saved_page.dart',
      'lib/presentation/screens/news/summary_reader_screen.dart',
      'lib/presentation/screens/news/article_detail_modal.dart',
      'lib/presentation/screens/watch/widgets/watch_card.dart',
      'lib/presentation/widgets/image_zoom_viewer.dart',
      'lib/presentation/screens/cloud/cloud_screen.dart',
      'lib/presentation/screens/watch/add_watch_sheet.dart',
    ];

    test('every CachedNetworkImage site sets memCacheWidth', () {
      for (final path in cachedSites) {
        final src = File(path).readAsStringSync();
        final images = 'CachedNetworkImage('.allMatches(src).length;
        final caches = 'memCacheWidth:'.allMatches(src).length;
        expect(caches, images, reason: path);
      }
    });

    test('lib has no Image.network left', () {
      expect(cloudScreen.contains('Image.network('), isFalse);
      expect(addWatch.contains('Image.network('), isFalse);
    });
  });

  group('5.7 unbounded lists', () {
    test('news feed and saved list use builders', () {
      expect(newsScreen.contains('ListView.builder('), isTrue);
      expect(newsSaved.contains('ListView.builder('), isTrue);
    });

    test('cloud file list uses a sliver builder', () {
      expect(cloudScreen.contains('CustomScrollView('), isTrue);
      expect(cloudScreen.contains('SliverList.builder('), isTrue);
    });
  });
}
