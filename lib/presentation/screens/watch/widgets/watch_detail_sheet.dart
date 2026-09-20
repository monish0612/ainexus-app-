import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../data/services/price_watch/history_series.dart';
import '../../../../data/services/price_watch/price_models.dart';
import '../../../../data/services/price_watch/price_parse.dart';
import '../watch_providers.dart';
import 'price_history_chart.dart';

class WatchDetailSheet extends ConsumerStatefulWidget {
  const WatchDetailSheet({super.key, required this.itemId});

  final String itemId;

  @override
  ConsumerState<WatchDetailSheet> createState() => _WatchDetailSheetState();
}

class _WatchDetailSheetState extends ConsumerState<WatchDetailSheet> {
  WatchPricePoint? _selected;
  bool _checking = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final items = ref.watch(watchItemsProvider).valueOrNull ?? [];
    WatchItem? found;
    for (final p in items) {
      if (p.id == widget.itemId) {
        found = p;
        break;
      }
    }
    final item = found;
    if (item == null) return const SizedBox.shrink();

    final history = ref.watch(watchHistoryProvider(item.id));
    final range = ref.watch(watchChartRangeProvider(item.id));
    final pts = history.valueOrNull ?? const <WatchPricePoint>[];
    final series = HistorySeries.of(pts, range: range);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: colors.border),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.text5,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.store.label.toUpperCase(),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: colors.text,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatInr(item.currentPrice),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: colors.text,
                    ),
                  ),
                ],
              ),
              if (_selected != null) ...[
                const SizedBox(height: 8),
                Text(
                  '${formatInr(_selected!.price)} · ${formatRelativeTime(_selected!.checkedAt.toLocal())}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: colors.text3,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _StatsRow(series: series, colors: colors),
              const SizedBox(height: 12),
              _RangeChips(
                itemId: item.id,
                points: pts,
                selected: range,
                colors: colors,
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: PriceHistoryChart(
                  key: ValueKey('${item.id}-${range.label}-${series.identity}'),
                  series: series,
                  targetPrice: item.targetPrice,
                  basePrice: item.basePrice,
                  onSelectPoint: (p) => setState(() => _selected = p),
                ),
              ),
              if (item.targetPrice != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Target ${formatInr(item.targetPrice!)} · added at ${formatInr(item.basePrice)}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: colors.text4,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _checking ? null : () => _check(item),
                    child: Text(_checking ? 'Checking…' : 'Check now'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      ref.read(watchFacadeProvider).setPaused(item, !item.isPaused);
                    },
                    child: Text(item.isPaused ? 'Resume' : 'Pause'),
                  ),
                  OutlinedButton(
                    onPressed: () {
                      launchUrl(
                        Uri.parse(item.canonicalUrl),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: const Text('Open'),
                  ),
                ],
              ),
              if (item.lastCheckError != null) ...[
                const SizedBox(height: 10),
                Text(
                  item.lastCheckError!,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _check(WatchItem item) async {
    setState(() => _checking = true);
    try {
      final r = await ref.read(watchFacadeProvider).checkNow(item);
      if (!r.ok || r.pending || r.reasons.isEmpty || r.price == null) return;
      WatchItem fresh = item;
      for (final p in ref.read(watchItemsProvider).valueOrNull ?? []) {
        if (p.id == item.id) {
          fresh = p;
          break;
        }
      }
      await ref.read(watchNotifierProvider).showChange(
            item: fresh,
            oldPrice: r.oldPrice ?? item.currentPrice,
            newPrice: r.price!,
            reasons: r.reasons,
          );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.series, required this.colors});

  final HistorySeries series;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    String fmt(double? n) => n == null ? '—' : formatInr(n);
    return Row(
      children: [
        _stat('MIN', fmt(series.min), colors),
        _stat('AVG', fmt(series.avg), colors),
        _stat('MAX', fmt(series.max), colors),
      ],
    );
  }

  Widget _stat(String label, String value, AppColors colors) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colors.text4,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _RangeChips extends ConsumerWidget {
  const _RangeChips({
    required this.itemId,
    required this.points,
    required this.selected,
    required this.colors,
  });

  final String itemId;
  final List<WatchPricePoint> points;
  final HistoryRange selected;
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        for (final range in HistoryRange.values) ...[
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _chip(context, ref, range),
          ),
        ],
      ],
    );
  }

  Widget _chip(BuildContext context, WidgetRef ref, HistoryRange range) {
    final enabled = HistorySeries.rangeEnabled(points, range);
    final on = selected == range;
    return GestureDetector(
      onTap: !enabled
          ? null
          : () {
              HapticFeedback.selectionClick();
              ref.read(watchChartRangeProvider(itemId).notifier).state = range;
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: on ? colors.bg3 : colors.bg2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: on ? colors.border : colors.border2),
        ),
        child: Text(
          range.label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            color: enabled ? (on ? colors.text : colors.text3) : colors.text5,
          ),
        ),
      ),
    );
  }
}
