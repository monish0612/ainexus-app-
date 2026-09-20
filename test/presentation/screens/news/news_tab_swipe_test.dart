// Guards swipe-to-delete vs category switching:
//
//   • Horizontal swipe on a feed card must DELETE the article.
//   • There is no TabBarView / horizontal pager for Saved or categories —
//     Saved is a header route; categories are a bottom rail (tap only).

import 'dart:io';

import 'package:ai_nexus/presentation/widgets/swipe_to_delete.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('News feed has no horizontal pager; swipe-delete stays on cards', () {
    final src = File('lib/presentation/screens/news/news_screen.dart')
        .readAsStringSync();
    expect(src.contains('TabBarView'), isFalse,
        reason: 'TabBarView would steal card swipes');
    expect(src.contains('NewsCategoryRail'), isTrue);
    expect(src.contains('SwipeToDelete('), isTrue);
    expect(src.contains("headline: 'Delete this article?'"), isTrue,
        reason: 'swipe must ask before deleting');
    expect(src.contains('NewsSavedPage.open'), isTrue);
    expect(src.contains('RefreshIndicator('), isTrue,
        reason: 'pull-to-refresh stays as a secondary fetch option');
    expect(src.contains('_handleRefresh'), isTrue);
    expect(src.contains('AlwaysScrollableScrollPhysics'), isTrue);
    final saved =
        File('lib/presentation/screens/news/news_saved_page.dart')
            .readAsStringSync();
    expect(saved.contains('RefreshIndicator('), isTrue);
    expect(saved.contains('_handleRefresh'), isTrue);
  });

  testWidgets(
      'locked TabBarView does not open Saved when the user swipes a card',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var deleted = 0;
    late TabController tabs;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) {
              tabs = DefaultTabController.of(context);
              return Column(
                children: [
                  const TabBar(tabs: [Tab(text: 'For You'), Tab(text: 'Saved')]),
                  Expanded(
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        Center(
                          child: SizedBox(
                            width: 360,
                            height: 88,
                            child: SwipeToDelete(
                              confirm: false,
                              onDelete: () => deleted++,
                              child: const ColoredBox(
                                color: Color(0xFF334155),
                                child: Center(child: Text('Finance card')),
                              ),
                            ),
                          ),
                        ),
                        const Center(child: Text('Saved pane')),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Finance card'), findsOneWidget);
    expect(find.text('Saved pane'), findsNothing);
    expect(tabs.index, 0);

    await tester.drag(find.text('Finance card'), const Offset(280, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(deleted, 1, reason: 'swipe must delete, same as Movies / General');
    expect(tabs.index, 0, reason: 'must stay on For You, not jump to Saved');
    expect(find.text('Finance card'), findsOneWidget);
    expect(find.text('Saved pane'), findsNothing);
  });

  test('swipe-delete calls deleteArticle, never toggleSaved', () {
    final src = File('lib/presentation/screens/news/news_screen.dart')
        .readAsStringSync();
    final start = src.indexOf('Future<void> _deleteArticle');
    expect(start, greaterThanOrEqualTo(0));
    final body = src.substring(start, start + 1200);
    expect(body.contains('.deleteArticle(id)'), isTrue);
    expect(body.contains('toggleSaved'), isFalse);
    expect(src.contains('onSwipeDelete: _deleteArticle'), isTrue);
    expect(
      'SwipeToDelete('.allMatches(src).length,
      greaterThanOrEqualTo(2),
      reason: 'featured card AND list rows must both swipe-delete',
    );
  });

  testWidgets(
      'unlocked TabBarView would jump to Saved — that is the bug we locked',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late TabController tabs;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) {
              tabs = DefaultTabController.of(context);
              return const Column(
                children: [
                  TabBar(tabs: [Tab(text: 'For You'), Tab(text: 'Saved')]),
                  Expanded(
                    child: TabBarView(
                      children: [
                        Center(child: Text('For You pane')),
                        Center(child: Text('Saved pane')),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tabs.index, 0);

    await tester.drag(find.text('For You pane'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(tabs.index, 1, reason: 'default TabBarView pages to Saved');
    expect(find.text('Saved pane'), findsOneWidget);
  });

  testWidgets('short swipe does not delete and does not open Saved',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var deleted = 0;
    late TabController tabs;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) {
              tabs = DefaultTabController.of(context);
              return Column(
                children: [
                  const TabBar(tabs: [Tab(text: 'For You'), Tab(text: 'Saved')]),
                  Expanded(
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        Center(
                          child: SizedBox(
                            width: 360,
                            height: 88,
                            child: SwipeToDelete(
                              confirm: false,
                              onDelete: () => deleted++,
                              child: const ColoredBox(
                                color: Color(0xFF334155),
                                child: Center(child: Text('AI News card')),
                              ),
                            ),
                          ),
                        ),
                        const Center(child: Text('Saved pane')),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('AI News card'), const Offset(40, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(deleted, 0);
    expect(tabs.index, 0);
    expect(find.text('Saved pane'), findsNothing);
  });

  testWidgets('right-to-left swipe also deletes and stays on For You',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var deleted = 0;
    late TabController tabs;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) {
              tabs = DefaultTabController.of(context);
              return Column(
                children: [
                  const TabBar(tabs: [Tab(text: 'For You'), Tab(text: 'Saved')]),
                  Expanded(
                    child: TabBarView(
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        Center(
                          child: SizedBox(
                            width: 360,
                            height: 280,
                            child: SwipeToDelete(
                              confirm: false,
                              onDelete: () => deleted++,
                              borderRadius: 24,
                              contentHeight: 280,
                              child: const ColoredBox(
                                color: Color(0xFF334155),
                                child: Center(child: Text('All featured')),
                              ),
                            ),
                          ),
                        ),
                        const Center(child: Text('Saved pane')),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('All featured'), const Offset(-280, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(deleted, 1);
    expect(tabs.index, 0);
  });

  testWidgets('vertical drag does not open Saved', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    late TabController tabs;
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Builder(
            builder: (context) {
              tabs = DefaultTabController.of(context);
              return const Column(
                children: [
                  TabBar(tabs: [Tab(text: 'For You'), Tab(text: 'Saved')]),
                  Expanded(
                    child: TabBarView(
                      physics: NeverScrollableScrollPhysics(),
                      children: [
                        Center(child: Text('For You pane')),
                        Center(child: Text('Saved pane')),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.text('For You pane'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tabs.index, 0);
  });

  testWidgets('tapping the Saved tab still works when paging is locked',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(tabs: [Tab(text: 'For You'), Tab(text: 'Saved')]),
              Expanded(
                child: TabBarView(
                  physics: NeverScrollableScrollPhysics(),
                  children: [
                    Center(child: Text('For You pane')),
                    Center(child: Text('Saved pane')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Saved'));
    await tester.pumpAndSettle();

    expect(find.text('Saved pane'), findsOneWidget);
    expect(find.text('For You pane'), findsNothing);

    await tester.tap(find.text('For You'));
    await tester.pumpAndSettle();
    expect(find.text('For You pane'), findsOneWidget);
  });
}
