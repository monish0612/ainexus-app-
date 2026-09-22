import 'package:ai_nexus/core/utils/reduced_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('follows MediaQuery.disableAnimations', (tester) async {
    late bool still;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            still = reducedMotion(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(still, isTrue);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: false),
        child: Builder(
          builder: (context) {
            still = reducedMotion(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(still, isFalse);
  });

  testWidgets('default MediaQuery is not reduced motion', (tester) async {
    late bool still;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Builder(
          builder: (context) {
            still = reducedMotion(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(still, isFalse);
  });

  testWidgets('accessibleNavigation alone is enough to reduce motion',
      (tester) async {
    late bool still;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(accessibleNavigation: true),
        child: Builder(
          builder: (context) {
            still = reducedMotion(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(still, isTrue,
        reason: 'a screen reader driving the UI wants surfaces to hold still');
  });

  testWidgets('motionDuration collapses to zero only when reduced',
      (tester) async {
    const full = Duration(milliseconds: 250);
    late Duration reduced;
    late Duration normal;
    await tester.pumpWidget(
      Column(
        textDirection: TextDirection.ltr,
        children: <Widget>[
          MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: Builder(builder: (context) {
              reduced = motionDuration(context, full);
              return const SizedBox.shrink();
            }),
          ),
          MediaQuery(
            data: const MediaQueryData(),
            child: Builder(builder: (context) {
              normal = motionDuration(context, full);
              return const SizedBox.shrink();
            }),
          ),
        ],
      ),
    );
    expect(reduced, Duration.zero);
    expect(normal, full);
  });

  testWidgets('fadeScaleTransition drops the scale under reduced motion',
      (tester) async {
    Widget probe({required bool disableAnimations}) => MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Builder(
              builder: (context) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: fadeScaleTransition(context),
                child: const SizedBox(key: ValueKey('a')),
              ),
            ),
          ),
        );

    await tester.pumpWidget(probe(disableAnimations: false));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(ScaleTransition), findsWidgets);

    await tester.pumpWidget(probe(disableAnimations: true));
    await tester.pump(const Duration(milliseconds: 100));
    // Same fade, same duration — only the scale is gone.
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(ScaleTransition), findsNothing);
  });
}
