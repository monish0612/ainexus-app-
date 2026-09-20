import 'package:flutter/material.dart';

import 'watch_screen.dart';

/// Named route for the Watch list. One on the stack — share, notifications,
/// Cloud, and Expense all reuse it instead of stacking another copy.
abstract final class WatchRoutes {
  static const watch = 'watch';
}

enum WatchNavStep { reuse, pop, push }

/// Pure stack policy. [names] is bottom → top (NavigatorObserver order).
///
/// - No Watch → push once.
/// - Watch is the only Watch and it's on top → reuse (deliver pending URL).
/// - Watch is buried under a sheet/clone → pop until the first Watch remains.
WatchNavStep nextWatchStep(List<String?> names) {
  final watchAt = <int>[];
  for (var i = 0; i < names.length; i++) {
    if (names[i] == WatchRoutes.watch) watchAt.add(i);
  }
  if (watchAt.isEmpty) return WatchNavStep.push;
  if (names.isNotEmpty &&
      names.last == WatchRoutes.watch &&
      watchAt.length == 1) {
    return WatchNavStep.reuse;
  }
  return WatchNavStep.pop;
}

/// Tracks the root navigator so share / notification can reuse Watch even
/// when the caller is AppShell (under the pushed route).
class WatchRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> stack = <Route<dynamic>>[];

  List<String?> get names =>
      stack.map((r) => r.settings.name).toList(growable: false);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    stack.add(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    stack.remove(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    stack.remove(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) {
      final i = stack.indexOf(oldRoute);
      if (i >= 0) {
        if (newRoute != null) {
          stack[i] = newRoute;
        } else {
          stack.removeAt(i);
        }
        return;
      }
    }
    if (newRoute != null) stack.add(newRoute);
  }

  void reset() => stack.clear();
}

/// Opens Watch as a **single** full-screen route on the existing Android task.
class WatchNavigator {
  WatchNavigator._();

  static final observer = WatchRouteObserver();

  /// Overridable so tests can push a stub page instead of the real screen.
  @visibleForTesting
  static WidgetBuilder pageBuilder = (_) => const WatchScreen();

  static Route<void> watchRoute() {
    return MaterialPageRoute<void>(
      settings: const RouteSettings(name: WatchRoutes.watch),
      builder: pageBuilder,
    );
  }

  static void open(BuildContext context) {
    final nav = Navigator.of(context, rootNavigator: true);
    var guard = 0;
    while (guard++ < 24) {
      switch (nextWatchStep(observer.names)) {
        case WatchNavStep.reuse:
          return;
        case WatchNavStep.push:
          nav.push<void>(watchRoute());
          return;
        case WatchNavStep.pop:
          if (!nav.canPop()) {
            nav.push<void>(watchRoute());
            return;
          }
          nav.pop();
      }
    }
  }
}
