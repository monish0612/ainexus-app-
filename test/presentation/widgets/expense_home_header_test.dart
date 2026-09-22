import 'package:ai_nexus/core/constants/app_constants.dart';
import 'package:ai_nexus/core/theme/app_colors.dart';
import 'package:ai_nexus/presentation/widgets/compact_header.dart';
import 'package:ai_nexus/presentation/widgets/expense_home_header.dart';
import 'package:ai_nexus/presentation/widgets/user_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  Widget wrap(Widget child) {
    return MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
      ),
      home: Scaffold(body: child),
    );
  }

  testWidgets('morning greeting + formatted Monish.', (tester) async {
    await tester.pumpWidget(
      wrap(
        ExpenseHomeHeader(
          name: 'Monish',
          now: DateTime(2026, 8, 21, 9),
          onAvatarTap: () {},
        ),
      ),
    );
    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Monish.'), findsOneWidget);
  });

  testWidgets('uses first name only and never double-periods', (tester) async {
    await tester.pumpWidget(
      wrap(
        ExpenseHomeHeader(
          name: 'Monish Kumar.',
          now: DateTime(2026, 8, 21, 14),
        ),
      ),
    );
    expect(find.text('Good afternoon'), findsOneWidget);
    expect(find.text('Monish.'), findsOneWidget);
    expect(find.text('Monish..'), findsNothing);
  });

  testWidgets('empty name falls back to Monish.', (tester) async {
    await tester.pumpWidget(
      wrap(
        ExpenseHomeHeader(
          name: '  ',
          now: DateTime(2026, 8, 21, 22),
        ),
      ),
    );
    expect(find.text('Good night'), findsOneWidget);
    expect(find.text('Monish.'), findsOneWidget);
  });

  testWidgets('avatar tap still opens settings callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        ExpenseHomeHeader(
          now: DateTime(2026, 8, 21, 8),
          onAvatarTap: () => taps++,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('user-avatar')));
    expect(taps, 1);
  });

  testWidgets('fallback glyph shows when no photo is set', (tester) async {
    await tester.pumpWidget(
      wrap(
        const UserAvatar(size: 40),
      ),
    );
    expect(find.text('😎'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('dots-only name still shows Monish.', (tester) async {
    await tester.pumpWidget(
      wrap(
        ExpenseHomeHeader(
          name: '...',
          now: DateTime(2026, 8, 21, 17),
        ),
      ),
    );
    expect(find.text('Good evening'), findsOneWidget);
    expect(find.text('Monish.'), findsOneWidget);
  });

  testWidgets('very long name does not overflow at 320px', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      wrap(
        ExpenseHomeHeader(
          name: 'Monishhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhhh',
          now: DateTime(2026, 8, 21, 10),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(ExpenseHomeHeader), findsOneWidget);
  });

  testWidgets('white theme header still greets without exceptions',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: const <ThemeExtension<dynamic>>[AppColors.white],
        ),
        home: Scaffold(
          body: ExpenseHomeHeader(
            name: 'Monish',
            now: DateTime(2026, 8, 21, 7),
          ),
        ),
      ),
    );
    expect(find.text('Good morning'), findsOneWidget);
    expect(find.text('Monish.'), findsOneWidget);
  });

  testWidgets('null avatar tap does not throw', (tester) async {
    await tester.pumpWidget(
      wrap(
        ExpenseHomeHeader(now: DateTime(2026, 8, 21, 8)),
      ),
    );
    await tester.tap(find.byKey(const Key('user-avatar')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy avatar hides emoji and edit badge', (tester) async {
    await tester.pumpWidget(
      wrap(
        const UserAvatar(size: 88, showEditBadge: true, busy: true),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('😎'), findsNothing);
    expect(find.byIcon(Icons.camera_alt_rounded), findsNothing);
  });

  testWidgets('edit badge shows when not busy', (tester) async {
    await tester.pumpWidget(
      wrap(
        const UserAvatar(size: 88, showEditBadge: true),
      ),
    );
    expect(find.byIcon(Icons.camera_alt_rounded), findsOneWidget);
  });

  testWidgets('empty photoPath string uses emoji fallback', (tester) async {
    await tester.pumpWidget(
      wrap(
        const UserAvatar(size: 40, photoPath: ''),
      ),
    );
    expect(find.text('😎'), findsOneWidget);
  });

  testWidgets('missing file path uses emoji fallback', (tester) async {
    await tester.pumpWidget(
      wrap(
        const UserAvatar(size: 40, photoPath: r'C:\missing\nope.jpg'),
      ),
    );
    expect(find.text('😎'), findsOneWidget);
  });

  testWidgets('News CompactHeader keeps title and 52px height', (tester) async {
    await tester.pumpWidget(
      wrap(
        const CompactHeader(title: 'News'),
      ),
    );
    expect(find.text('News'), findsOneWidget);
    expect(find.text('😎'), findsOneWidget);
    final box = tester.renderObject<RenderBox>(find.byType(CompactHeader));
    expect(box.size.height, AppConstants.headerHeight);
  });

  testWidgets('CompactHeader title still fits at 2x text scale',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
        ),
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2.0),
            ),
            child: child!,
          );
        },
        home: const Scaffold(
          body: CompactHeader(title: 'News'),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final box = tester.renderObject<RenderBox>(find.byType(CompactHeader));
    expect(box.size.height, AppConstants.headerHeight);
  });

  testWidgets('watch entry is hidden until onWatchTap is set', (tester) async {
    await tester.pumpWidget(
      wrap(
        ExpenseHomeHeader(
          now: DateTime(2026, 8, 21, 9),
          onAvatarTap: () {},
        ),
      ),
    );
    expect(find.byKey(const Key('watch-entry')), findsNothing);
  });

  testWidgets('watch entry fires callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        ExpenseHomeHeader(
          now: DateTime(2026, 8, 21, 9),
          onWatchTap: () => taps++,
          watchBadge: 2,
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('watch-entry')));
    expect(taps, 1);
    final watch = tester.getSize(find.byKey(const Key('watch-entry')));
    expect(watch.width, greaterThanOrEqualTo(48));
    expect(watch.height, greaterThanOrEqualTo(48));
  });

  testWidgets('avatar hitSize is 48 while the face stays 32', (tester) async {
    await tester.pumpWidget(
      wrap(
        UserAvatar(size: 32, hitSize: 48, onTap: () {}),
      ),
    );
    final box = tester.getSize(find.byKey(const Key('user-avatar')));
    expect(box.width, 48);
    expect(box.height, 48);
  });

  testWidgets('tappable avatar is labeled Settings', (tester) async {
    final handle = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        wrap(
          UserAvatar(size: 32, hitSize: 48, onTap: () {}),
        ),
      );
      expect(
        tester.getSemantics(find.byKey(const Key('user-avatar'))).label,
        contains('Settings'),
      );
    } finally {
      handle.dispose();
    }
  });
}
