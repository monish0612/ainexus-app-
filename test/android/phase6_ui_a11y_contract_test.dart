import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Locks Phase 6 a11y / polish contracts against the live files.
void main() {
  late String reducedMotion;
  late String overlayTokens;
  late String overlayApp;
  late String bottomNav;
  late String compactHeader;
  late String expenseHeader;
  late String expenseRepo;
  late String timeframe;
  late String budgetRing;
  late String newsFab;
  late String userAvatar;
  late String expenseScreen;
  late String brandMark;
  late String fluidGauge;

  setUpAll(() {
    reducedMotion =
        File('lib/core/utils/reduced_motion.dart').readAsStringSync();
    overlayTokens = File('lib/bubble/overlay/tokens.dart').readAsStringSync();
    overlayApp = File('lib/bubble/overlay/overlay_app.dart').readAsStringSync();
    bottomNav =
        File('lib/presentation/widgets/bottom_nav.dart').readAsStringSync();
    compactHeader =
        File('lib/presentation/widgets/compact_header.dart').readAsStringSync();
    expenseHeader = File('lib/presentation/widgets/expense_home_header.dart')
        .readAsStringSync();
    expenseRepo = File('lib/data/repositories/expense_repository.dart')
        .readAsStringSync();
    timeframe =
        File('lib/presentation/screens/expense/expense_timeframe_screen.dart')
            .readAsStringSync();
    budgetRing =
        File('lib/presentation/screens/expense/widgets/budget_ring.dart')
            .readAsStringSync();
    newsFab = File('lib/presentation/widgets/news_action_fab.dart')
        .readAsStringSync();
    userAvatar =
        File('lib/presentation/widgets/user_avatar.dart').readAsStringSync();
    expenseScreen = File('lib/presentation/screens/expense/expense_screen.dart')
        .readAsStringSync();
    brandMark = File('lib/presentation/widgets/nexus_brand_mark.dart')
        .readAsStringSync();
    fluidGauge =
        File('lib/presentation/screens/cloud/stats/widgets/fluid_gauge.dart')
            .readAsStringSync();
  });

  group('6.1 text scaling', () {
    test('app chrome does not globally clamp text scale', () {
      expect(compactHeader.contains('withClampedTextScaling'), isFalse);
      expect(expenseHeader.contains('withClampedTextScaling'), isFalse);
      expect(bottomNav.contains('withClampedTextScaling'), isFalse);
    });

    test('overlay still owns its compact clamp', () {
      expect(overlayApp.contains('MediaQuery.withClampedTextScaling'), isTrue);
      expect(overlayTokens.contains('kMaxTextScale = 1.3'), isTrue);
    });

    test('headers and budget ring shrink overflowing type', () {
      expect(compactHeader.contains('FittedBox('), isTrue);
      expect(expenseHeader.contains('FittedBox('), isTrue);
      expect(budgetRing.contains('FittedBox('), isTrue);
    });
  });

  group('6.2 / 6.3 semantics and tap targets', () {
    test('bottom nav exposes selected labels', () {
      expect(bottomNav.contains('label: widget.item.label'), isTrue);
      expect(bottomNav.contains('selected: widget.isActive'), isTrue);
      expect(bottomNav.contains('width: 48'), isTrue);
      expect(bottomNav.contains('height: 48'), isTrue);
    });

    test('compact header actions are 48dp and labeled', () {
      expect(compactHeader.contains('width: 48'), isTrue);
      expect(compactHeader.contains('height: 48'), isTrue);
      expect(compactHeader.contains("label: spoken"), isTrue);
      expect(compactHeader.contains('hitSize: 48'), isTrue);
    });

    test('expense FABs and news FAB are labeled', () {
      expect(expenseScreen.contains("label: 'Ask AI'"), isTrue);
      expect(expenseScreen.contains("label: 'Add expense'"), isTrue);
      expect(newsFab.contains("label: clearOnly"), isTrue);
      expect(newsFab.contains('excludeSemantics: true'), isTrue);
      expect(userAvatar.contains("semanticLabel ?? 'Settings'"), isTrue);
      expect(userAvatar.contains('excludeSemantics: true'), isTrue);
    });
  });

  group('6.4 reduced motion', () {
    test('app helper uses disableAnimationsOf', () {
      expect(
        reducedMotion.contains('MediaQuery.disableAnimationsOf(context)'),
        isTrue,
      );
    });

    test('overlay tokens keep maybeOf for the bubble isolate', () {
      expect(
        overlayTokens.contains(
          'MediaQuery.maybeOf(context)?.disableAnimations',
        ),
        isTrue,
      );
      expect(overlayTokens.contains('disableAnimationsOf'), isFalse);
    });

    test('always-visible loops consult reducedMotion', () {
      expect(bottomNav.contains('reducedMotion(context)'), isTrue);
      expect(newsFab.contains('reducedMotion(context)'), isTrue);
      expect(expenseScreen.contains('reducedMotion(context)'), isTrue);
      expect(brandMark.contains('reducedMotion(context)'), isTrue);
      expect(budgetRing.contains('reducedMotion(context)'), isTrue);
      expect(fluidGauge.contains('reducedMotion(context)'), isTrue);
    });
  });

  group('6.5 error vs empty', () {
    test('range aggregates rethrow after logging', () {
      expect(expenseRepo.contains("rangeSummary failed"), isTrue);
      expect(
        expenseRepo.contains('return (count: 0, total: 0.0);'),
        isFalse,
      );
      expect(
        RegExp(r"rangeSummary failed[\s\S]{0,80}rethrow;")
            .hasMatch(expenseRepo),
        isTrue,
      );
      expect(
        RegExp(r"categoryBreakdown failed[\s\S]{0,80}rethrow;")
            .hasMatch(expenseRepo),
        isTrue,
      );
      expect(
        RegExp(r"timeBreakdown failed[\s\S]{0,80}rethrow;")
            .hasMatch(expenseRepo),
        isTrue,
      );
    });

    test('timeframe summary failure is a retryable hero, not fake empty', () {
      expect(timeframe.contains('_summaryFailed'), isTrue);
      expect(timeframe.contains('Could not load totals'), isTrue);
    });
  });

  group('6.6 haptics', () {
    test('does not add haptics to the hot-path bottom nav', () {
      expect(bottomNav.contains('HapticFeedback'), isFalse);
    });
  });
}
