import 'package:flutter/material.dart';

import 'stat_detail_screen.dart';
import 'stat_metric.dart';

/// Shared-element wrapper around a gauge. Unique [StatMetric.heroTag] per
/// series so two CPU rings (NAS and VPS) cannot collide in flight.
class TappableStatGauge extends StatelessWidget {
  const TappableStatGauge({
    super.key,
    required this.metric,
    required this.child,
    this.enabled = true,
  });

  final StatMetric metric;
  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hero = Hero(
      tag: metric.heroTag,
      child: Material(
        type: MaterialType.transparency,
        child: child,
      ),
    );
    if (!enabled) return hero;
    return Semantics(
      button: true,
      label: 'Open live ${metric.title} chart',
      child: GestureDetector(
        onTap: () => openStatDetail(context, metric),
        behavior: HitTestBehavior.opaque,
        child: hero,
      ),
    );
  }
}

void openStatDetail(BuildContext context, StatMetric metric) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => StatDetailScreen(metric: metric),
    ),
  );
}
