import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/core/utils/reduced_motion.dart';
import 'package:ai_nexus/presentation/widgets/bottom_nav.dart';
import 'package:ai_nexus/presentation/widgets/compact_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';

ThemeData _theme(AppColors colors) => ThemeData(
      brightness: colors.isDark ? Brightness.dark : Brightness.light,
      extensions: <ThemeExtension<dynamic>>[colors],
    );

Widget _wrap({
  required AppColors colors,
  required Widget child,
  bool disableAnimations = false,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return MaterialApp(
    theme: _theme(colors),
    builder: (context, appChild) {
      final mq = MediaQuery.of(context);
      return MediaQuery(
        data: mq.copyWith(
          disableAnimations: disableAnimations,
          textScaler: textScaler,
        ),
        child: appChild!,
      );
    },
    home: Scaffold(
      backgroundColor: colors.bg,
      body: child,
    ),
  );
}

void main() {
  testWidgets('bottom nav buttons are labeled and 48dp', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _wrap(
          colors: AppColors.dark,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: BottomNav(currentIndex: 0, onTap: _onNav),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Expense'), findsOneWidget);
      expect(find.bySemanticsLabel('News'), findsOneWidget);
      expect(find.bySemanticsLabel('Tutor'), findsOneWidget);
      expect(find.bySemanticsLabel('Cloud'), findsOneWidget);

      final expense = tester.getSize(find.bySemanticsLabel('Expense'));
      expect(expense.width, greaterThanOrEqualTo(48));
      expect(expense.height, greaterThanOrEqualTo(48));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      handle.dispose();
    }
  });

  testWidgets('light nav still meets tap-target and label guidelines',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _wrap(
          colors: AppColors.white,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: BottomNav(currentIndex: 1, onTap: _onNav),
          ),
        ),
      );

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    } finally {
      handle.dispose();
    }
  });

  testWidgets('reduced motion freezes nav press scale', (tester) async {
    await tester.pumpWidget(
      _wrap(
        colors: AppColors.dark,
        disableAnimations: true,
        child: Builder(
          builder: (context) {
            expect(reducedMotion(context), isTrue);
            return BottomNav(currentIndex: 0, onTap: _onNav);
          },
        ),
      ),
    );

    final stopped = tester
        .widgetList<ScaleTransition>(
          find.descendant(
            of: find.byType(BottomNav),
            matching: find.byType(ScaleTransition),
          ),
        )
        .where((s) => s.scale is AlwaysStoppedAnimation<double>);
    expect(stopped.length, 4);
  });

  testWidgets('compact header stays 52px at 2x text and keeps 48dp hits',
      (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        _wrap(
          colors: AppColors.dark,
          textScaler: const TextScaler.linear(2.0),
          child: CompactHeader(
            title: 'News',
            actionIcon: LucideIcons.bookmark,
            actionTooltip: 'Saved',
            onActionTap: _onTap,
            onAvatarTap: _onTap,
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      final header = tester.getSize(find.byType(CompactHeader));
      expect(header.height, 52);

      final saved = tester.getSize(find.byTooltip('Saved'));
      expect(saved.width, greaterThanOrEqualTo(48));
      expect(saved.height, greaterThanOrEqualTo(48));

      final avatar = tester.getSize(find.byKey(const Key('user-avatar')));
      expect(avatar.width, greaterThanOrEqualTo(48));
      expect(avatar.height, greaterThanOrEqualTo(48));

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    } finally {
      handle.dispose();
    }
  });
}

void _onNav(int _) {}

void _onTap() {}
