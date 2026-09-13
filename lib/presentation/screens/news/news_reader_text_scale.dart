import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_colors.dart';

/// SharedPreferences key for the article-reader text size. Local-only — this
/// is a reading comfort preference, not a synced account setting.
const String kNewsReaderTextScalePrefKey = 'news_reader_text_scale';

const Key kNewsReaderTextDecreaseKey = ValueKey('news_reader_text_decrease');
const Key kNewsReaderTextIncreaseKey = ValueKey('news_reader_text_increase');
const Key kNewsReaderTextSizeBarKey = ValueKey('news_reader_text_size_bar');

/// Discrete reading sizes. Headings stay larger than body because we scale
/// via [TextScaler] instead of rewriting each font size.
const List<double> kNewsReaderTextScaleSteps = <double>[
  0.85,
  1.00,
  1.15,
  1.30,
  1.45,
  1.60,
  1.70,
];

const double kNewsReaderTextScaleMin = 0.85;
const double kNewsReaderTextScaleMax = 1.70;
const double kNewsReaderTextScaleDefault = 1.00;

/// Combines system accessibility scaling with the reader's A−/A+ preference,
/// then clamps so a 320px phone cannot explode into overflow.
TextScaler newsReaderTextScaler({
  required TextScaler system,
  required double readerScale,
}) {
  final sys = system.scale(1.0).clamp(1.0, 1.2);
  final combined = (sys * readerScale).clamp(
    kNewsReaderTextScaleMin,
    kNewsReaderTextScaleMax,
  );
  return TextScaler.linear(combined);
}

double clampNewsReaderTextScale(double value) =>
    value.clamp(kNewsReaderTextScaleMin, kNewsReaderTextScaleMax).toDouble();

double snapNewsReaderTextScale(double value) {
  final clamped = clampNewsReaderTextScale(value);
  var best = kNewsReaderTextScaleSteps.first;
  var bestDist = (clamped - best).abs();
  for (final step in kNewsReaderTextScaleSteps) {
    final dist = (clamped - step).abs();
    if (dist < bestDist) {
      best = step;
      bestDist = dist;
    }
  }
  return best;
}

class NewsReaderTextScale extends StateNotifier<double> {
  NewsReaderTextScale({double? initial, bool hydrate = true})
      : super(snapNewsReaderTextScale(initial ?? kNewsReaderTextScaleDefault)) {
    if (hydrate && initial == null) {
      _hydrate();
    }
  }

  bool get canDecrease => state > kNewsReaderTextScaleMin + 0.001;
  bool get canIncrease => state < kNewsReaderTextScaleMax - 0.001;

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getDouble(kNewsReaderTextScalePrefKey);
      if (stored == null || !mounted) return;
      final next = snapNewsReaderTextScale(stored);
      if (next != state) state = next;
    } catch (_) {
      // Tests without a prefs mock, or a transient plugin miss — stay default.
    }
  }

  Future<void> increase() => _move(1);
  Future<void> decrease() => _move(-1);

  Future<void> _move(int delta) async {
    final idx = _stepIndex(state);
    final nextIdx = (idx + delta).clamp(0, kNewsReaderTextScaleSteps.length - 1);
    final next = kNewsReaderTextScaleSteps[nextIdx];
    if (next == state) return;
    state = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(kNewsReaderTextScalePrefKey, next);
    } catch (_) {
      // Preference write is best-effort; the in-memory scale still applies.
    }
  }

  int _stepIndex(double value) {
    final snapped = snapNewsReaderTextScale(value);
    final idx = kNewsReaderTextScaleSteps.indexOf(snapped);
    return idx < 0 ? 1 : idx;
  }
}

final newsReaderTextScaleProvider =
    StateNotifierProvider<NewsReaderTextScale, double>((ref) {
  return NewsReaderTextScale();
});

/// Applies the reader text scale to [child] only. Chrome (TTS, bottom bar,
/// FAB) must stay outside this widget so controls never reflow or overflow.
class ArticleReaderProse extends ConsumerWidget {
  const ArticleReaderProse({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(newsReaderTextScaleProvider);
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(
        textScaler: newsReaderTextScaler(
          system: mq.textScaler,
          readerScale: scale,
        ),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(overflow: TextOverflow.clip),
        child: child,
      ),
    );
  }
}

/// Keeps chrome (pills, chips, A−/A+) at a fixed size so labels never
/// overflow when article body type is enlarged.
class UnscaledReaderChrome extends StatelessWidget {
  const UnscaledReaderChrome({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: child,
    );
  }
}

enum ArticleReaderTextSizeVariant { onMedia, onSurface }

/// Compact A− / A+ control. [onMedia] sits on the hero image; [onSurface]
/// sits in the sticky header after scroll.
class ArticleReaderTextSizeBar extends ConsumerWidget {
  const ArticleReaderTextSizeBar({
    super.key,
    required this.variant,
    this.barKey = kNewsReaderTextSizeBarKey,
    this.decreaseKey = kNewsReaderTextDecreaseKey,
    this.increaseKey = kNewsReaderTextIncreaseKey,
  });

  final ArticleReaderTextSizeVariant variant;

  /// Defaults keep the news-reader tests stable. Search results pass their
  /// own keys so both surfaces can be on a stack without colliding.
  final Key barKey;
  final Key decreaseKey;
  final Key increaseKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(newsReaderTextScaleProvider);
    final notifier = ref.read(newsReaderTextScaleProvider.notifier);
    final colors = Theme.of(context).extension<AppColors>();
    final onMedia = variant == ArticleReaderTextSizeVariant.onMedia;

    final Color fg;
    final Color muted;
    final Color fill;
    final Color stroke;
    if (onMedia || colors == null) {
      fg = Colors.white;
      muted = Colors.white70;
      fill = const Color(0x99000000);
      stroke = const Color(0x40FFFFFF);
    } else {
      fg = colors.text;
      muted = colors.text3;
      fill = colors.bg2;
      stroke = colors.border;
    }

    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.noScaling,
      ),
      child: Material(
        key: barKey,
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: stroke),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _TextSizeBtn(
                    key: decreaseKey,
                    label: 'A−',
                    fontSize: 13,
                    tooltip: 'Decrease text size',
                    enabled: scale > kNewsReaderTextScaleMin + 0.001,
                    color: fg,
                    disabledColor: muted,
                    onTap: notifier.decrease,
                  ),
                  SizedBox(
                    width: 1,
                    height: 16,
                    child: ColoredBox(color: stroke),
                  ),
                  _TextSizeBtn(
                    key: increaseKey,
                    label: 'A+',
                    fontSize: 16,
                    tooltip: 'Increase text size',
                    enabled: scale < kNewsReaderTextScaleMax - 0.001,
                    color: fg,
                    disabledColor: muted,
                    onTap: notifier.increase,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TextSizeBtn extends StatelessWidget {
  const _TextSizeBtn({
    super.key,
    required this.label,
    required this.fontSize,
    required this.tooltip,
    required this.enabled,
    required this.color,
    required this.disabledColor,
    required this.onTap,
  });

  final String label;
  final double fontSize;
  final String tooltip;
  final bool enabled;
  final Color color;
  final Color disabledColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
          child: IgnorePointer(
            ignoring: !enabled,
            child: InkWell(
              onTap: enabled
                  ? () {
                      HapticFeedback.selectionClick();
                      onTap();
                    }
                  : null,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w800,
                    height: 1,
                    color: enabled ? color : disabledColor,
                  ),
                ),
              ),
            ),
          ),
      ),
    );
  }
}
