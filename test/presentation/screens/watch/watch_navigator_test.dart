import 'package:ai_nexus/presentation/screens/watch/watch_navigator.dart';
import 'package:ai_nexus/presentation/screens/watch/watch_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('nextWatchStep', () {
    test('pushes when Watch is absent', () {
      expect(nextWatchStep(const ['/']), WatchNavStep.push);
      expect(nextWatchStep(const []), WatchNavStep.push);
      expect(nextWatchStep(const ['/', null]), WatchNavStep.push);
    });

    test('reuses a single Watch on top', () {
      expect(nextWatchStep(const ['/', 'watch']), WatchNavStep.reuse);
      expect(nextWatchStep(const ['watch']), WatchNavStep.reuse);
    });

    test('pops a sheet sitting on Watch', () {
      expect(nextWatchStep(const ['/', 'watch', null]), WatchNavStep.pop);
    });

    test('pops a duplicate Watch clone', () {
      expect(nextWatchStep(const ['/', 'watch', 'watch']), WatchNavStep.pop);
    });

    test('pops dictionary/rephrase sitting on Watch', () {
      expect(
        nextWatchStep(const ['/', 'watch', 'rephrase']),
        WatchNavStep.pop,
      );
    });
  });

  group('WatchNavigator.open', () {
    setUp(() {
      WatchNavigator.observer.reset();
      WatchNavigator.pageBuilder =
          (_) => const Scaffold(body: Text('WATCH_PAGE'));
    });

    tearDown(() {
      WatchNavigator.observer.reset();
      WatchNavigator.pageBuilder = (_) => const WatchScreen();
    });

    testWidgets('share / cloud / expense reuse one Watch route', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [WatchNavigator.observer],
          home: const Scaffold(body: Text('HOME')),
        ),
      );

      WatchNavigator.open(navKey.currentContext!);
      await tester.pumpAndSettle();
      expect(find.text('WATCH_PAGE'), findsOneWidget);

      WatchNavigator.open(navKey.currentContext!);
      await tester.pumpAndSettle();
      expect(find.text('WATCH_PAGE'), findsOneWidget);

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
      expect(find.text('WATCH_PAGE'), findsNothing);
    });

    testWidgets('pops an overlay then reuses Watch', (tester) async {
      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          navigatorObservers: [WatchNavigator.observer],
          home: const Scaffold(body: Text('HOME')),
        ),
      );

      WatchNavigator.open(navKey.currentContext!);
      await tester.pumpAndSettle();

      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('SHEET')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SHEET'), findsOneWidget);

      WatchNavigator.open(navKey.currentContext!);
      await tester.pumpAndSettle();
      expect(find.text('WATCH_PAGE'), findsOneWidget);
      expect(find.text('SHEET'), findsNothing);

      navKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('HOME'), findsOneWidget);
    });
  });
}
