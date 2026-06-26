import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/di/injection.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/services/ai_categorize_service.dart' show keywordRules;
import '../../../../core/services/nuke_report.dart';
import '../../settings/settings_controller.dart';
import '../expense_timeframe_screen.dart';
import '../salary_screen.dart';
import '../widgets/nuke_easter_egg.dart';

/// Opens the AI expense-search ask sheet. The user types a plain-English
/// question; Gemini (via backend) distils it into a structured query that we
/// run against the local DB and render in the editable results screen.
Future<void> showExpenseAiAskSheet(
  BuildContext context, {
  String? initialQuestion,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ExpenseAiAskSheet(initialQuestion: initialQuestion),
  );
}

const _suggestions = <String>[
  "Today's expenses",
  'Highest expense',
  'Visualize last month',
  'Anything related to my car',
  'My salary this month',
  'Did I get a hike?',
  'Spending by category',
  'Last trip cost',
];

// AI gradient palette — matches the app's premium summarize aesthetic.
const _gradA = Color(0xFF6366F1); // indigo
const _gradB = Color(0xFFA855F7); // purple
const _gradC = Color(0xFF22D3EE); // cyan

class _ExpenseAiAskSheet extends ConsumerStatefulWidget {
  const _ExpenseAiAskSheet({this.initialQuestion});

  /// When provided (e.g. tapping a recommendation chip), the sheet opens with
  /// this question pre-filled and submits it automatically.
  final String? initialQuestion;

  @override
  ConsumerState<_ExpenseAiAskSheet> createState() => _ExpenseAiAskSheetState();
}

class _ExpenseAiAskSheetState extends ConsumerState<_ExpenseAiAskSheet> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
    final preset = widget.initialQuestion?.trim();
    if (preset != null && preset.isNotEmpty) {
      _ctrl.text = preset;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _submit(preset);
      });
    }
  }

  void _onTextChanged() {
    final hasText = _ctrl.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit([String? preset]) async {
    final question = (preset ?? _ctrl.text).trim();
    if (question.isEmpty || _loading) return;

    // ── Easter egg: typing "nuke" triggers a full from-scratch reset ──
    // (all expenses + budget + salary, local + cloud). Intercepted before the
    // AI round-trip so it never leaves the device as a search query.
    if (question.toLowerCase() == 'nuke') {
      await _handleNuke();
      return;
    }

    HapticFeedback.selectionClick();
    if (preset != null) _ctrl.text = preset;
    setState(() => _loading = true);

    final service = ref.read(expenseAiSearchServiceProvider);
    final liteModel = ref.read(settingsProvider).liteModel;
    final spec = await service.query(
      question,
      categories: keywordRules.keys.toList(),
      liteModel: liteModel,
    );
    if (!mounted) return;

    // Salary/income questions route to the dedicated salary stats screen, which
    // holds the real numbers (the AI never sees or invents them).
    if (spec != null && spec.isSalaryTopic) {
      Navigator.of(context).pop();
      await showSalaryScreen(
        context,
        aiAnswer: spec.answer.isEmpty ? null : spec.answer,
      );
      return;
    }

    // Build the editable results timeframe — either from the AI spec or, if the
    // AI is unavailable, a graceful keyword-search fallback so results still show.
    final timeframe = spec == null
        ? ExpenseTimeframe(
            label: question.length > 28 ? '${question.substring(0, 28)}…' : question,
            startIso: null,
            seedSearch: question,
            aiAnswer: 'Showing keyword matches for "$question" '
                '(AI is offline — refine with the search box).',
            aiInsight: true,
            aiQuestion: question,
          )
        : ExpenseTimeframe(
            label: spec.title,
            startIso: spec.startIso,
            endIso: spec.endIso,
            seedSearch: spec.search,
            seedSearchTerms: spec.searchTerms,
            seedCategory: spec.category,
            sort: spec.sort,
            aiAnswer: spec.answer.isEmpty ? null : spec.answer,
            chart: spec.chart,
            aiInsight: true,
            aiQuestion: question,
          );

    Navigator.of(context).pop();
    await showExpenseTimeframeScreen(context, timeframe);
  }

  /// Runs the "nuke" easter egg: confirm → wipe expenses/budget/salary
  /// (local + cloud, with retry) → close the sheet → surface the wipeout toast
  /// on the screen beneath. The underlying [ExpenseNukeService] handles all the
  /// robustness (parallel clears, exponential-backoff retry, verify, automatic
  /// replay on next launch, Telegram flow logs).
  Future<void> _handleNuke() async {
    _ctrl.clear();
    _focus.unfocus();

    final confirmed = await NukeEasterEgg.confirm(context, NukeScope.expense);
    if (!mounted) return;
    if (!confirmed) {
      _focus.requestFocus();
      return;
    }

    setState(() => _loading = true);
    final report = await ref.read(expenseNukeServiceProvider).nuke();
    if (!mounted) return;
    setState(() => _loading = false);

    // Capture the (still-mounted) navigator before popping so the result
    // window opens on the screen we return to, not the dismissed sheet.
    final navigator = Navigator.of(context);
    navigator.pop();
    await NukeEasterEgg.showReport(navigator.context, report);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border(
            top: BorderSide(color: _gradB.withValues(alpha: 0.22)),
          ),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _gradA.withValues(alpha: colors.isDark ? 0.10 : 0.05),
              colors.bg1,
            ],
            stops: const [0.0, 0.4],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.text4,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              child: Row(
                children: [
                  const _AiOrb(size: 40),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShaderMask(
                          shaderCallback: (r) => const LinearGradient(
                            colors: [_gradC, _gradB],
                          ).createShader(r),
                          child: Text(
                            'Ask AI',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          'Search your expenses in plain English',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: colors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
              child: _GlowInputBar(
                colors: colors,
                controller: _ctrl,
                focus: _focus,
                loading: _loading,
                onSubmit: () => _submit(),
              ),
            ),
            // Sleek, single-row suggestion rail. It collapses the moment the
            // user starts typing so the sheet stays clean and uncluttered.
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(sizeFactor: anim, child: child),
                ),
                child: _hasText
                    ? const SizedBox(width: double.infinity)
                    : _SuggestionRail(
                        colors: colors,
                        loading: _loading,
                        onPick: _submit,
                      ),
              ),
            ),
            SizedBox(height: 16 + MediaQuery.paddingOf(context).bottom),
          ],
        ),
      ),
    );
  }
}

/// A single horizontally-scrolling rail of suggestion pills with soft fade
/// edges. Shows only a few at a time — scroll for more — instead of dumping
/// every suggestion at once.
class _SuggestionRail extends StatelessWidget {
  const _SuggestionRail({
    required this.colors,
    required this.loading,
    required this.onPick,
  });

  final AppColors colors;
  final bool loading;
  final void Function(String) onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Icon(LucideIcons.wand2, size: 13, color: colors.text3),
              const SizedBox(width: 6),
              Text(
                'TRY ASKING',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                  color: colors.text3,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 38,
          child: ShaderMask(
            shaderCallback: (rect) => const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.transparent,
                Colors.white,
                Colors.white,
                Colors.transparent,
              ],
              stops: [0.0, 0.04, 0.94, 1.0],
            ).createShader(rect),
            blendMode: BlendMode.dstIn,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, i) => _SuggestionChip(
                colors: colors,
                label: _suggestions[i],
                onTap: loading ? null : () => onPick(_suggestions[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The futuristic input field: a rounded glass field wrapped in an animated,
/// slowly-rotating gradient ring. The ring is subtle when idle and ignites
/// (brighter, wider glow) the instant the field is focused.
class _GlowInputBar extends StatefulWidget {
  const _GlowInputBar({
    required this.colors,
    required this.controller,
    required this.focus,
    required this.loading,
    required this.onSubmit,
  });

  final AppColors colors;
  final TextEditingController controller;
  final FocusNode focus;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  State<_GlowInputBar> createState() => _GlowInputBarState();
}

class _GlowInputBarState extends State<_GlowInputBar>
    with TickerProviderStateMixin {
  late final AnimationController _rotate;
  late final AnimationController _focusCtrl;
  late final Animation<double> _focusAnim;

  @override
  void initState() {
    super.initState();
    _rotate = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _focusCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _focusAnim = CurvedAnimation(parent: _focusCtrl, curve: Curves.easeOutCubic);
    widget.focus.addListener(_onFocus);
    // Field autofocuses on open, so light it up from the start.
    _focusCtrl.value = 1;
  }

  void _onFocus() {
    if (widget.focus.hasFocus) {
      _focusCtrl.forward();
    } else {
      _focusCtrl.reverse();
    }
  }

  @override
  void dispose() {
    widget.focus.removeListener(_onFocus);
    _rotate.dispose();
    _focusCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return AnimatedBuilder(
      animation: Listenable.merge([_rotate, _focusAnim]),
      builder: (context, child) {
        final glow = _focusAnim.value;
        return CustomPaint(
          painter: _GlowRingPainter(
            rotation: _rotate.value,
            intensity: glow,
            radius: 18,
          ),
          child: Padding(
            padding: const EdgeInsets.all(2.5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.bg1,
                borderRadius: BorderRadius.circular(15.5),
              ),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 6, 4),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focus,
                autofocus: true,
                enabled: !widget.loading,
                minLines: 1,
                maxLines: 3,
                cursorColor: _gradB,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => widget.onSubmit(),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: colors.text,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  hintText: 'how much did I spend on food today?',
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 13.5,
                    color: colors.text4,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _SendButton(
              loading: widget.loading,
              rotate: _rotate,
              onTap: widget.loading ? null : widget.onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}

/// Gradient send button with a faint rotating sheen that mirrors the ring.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.loading,
    required this.rotate,
    required this.onTap,
  });

  final bool loading;
  final Animation<double> rotate;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: loading
              ? null
              : const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_gradC, _gradB],
                ),
          color: loading ? Theme.of(context).extension<AppColors>()!.bg3 : null,
          borderRadius: BorderRadius.circular(13),
          boxShadow: loading
              ? null
              : [
                  BoxShadow(
                    color: _gradB.withValues(alpha: 0.45),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(_gradB),
                ),
              )
            : const Icon(LucideIcons.arrowUp, size: 20, color: Colors.white),
      ),
    );
  }
}

/// Paints a rounded-rect ring filled with a rotating sweep gradient, plus an
/// outer blurred glow whose strength scales with [intensity] (focus).
class _GlowRingPainter extends CustomPainter {
  _GlowRingPainter({
    required this.rotation,
    required this.intensity,
    required this.radius,
  });

  final double rotation;
  final double intensity;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect =
        RRect.fromRectAndRadius(rect.deflate(1.25), Radius.circular(radius));

    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      transform: GradientRotation(rotation * 2 * math.pi),
      colors: const [_gradA, _gradB, _gradC, _gradA],
      stops: const [0.0, 0.35, 0.7, 1.0],
    ).createShader(rect);

    // Outer glow — only meaningful while focused.
    if (intensity > 0.01) {
      final glow = Paint()
        ..shader = shader
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 + intensity * 2.5
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 + intensity * 7);
      canvas.saveLayer(rect, Paint()..color = Colors.white.withValues(alpha: 0.35 + intensity * 0.4));
      canvas.drawRRect(rrect, glow);
      canvas.restore();
    }

    // Crisp ring. Dim when idle, full when focused.
    final ring = Paint()
      ..shader = shader
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4 + intensity * 1.1
      ..color = Colors.white.withValues(alpha: 0.5 + intensity * 0.5);
    canvas.saveLayer(rect, Paint()..color = Colors.white.withValues(alpha: 0.45 + intensity * 0.55));
    canvas.drawRRect(rrect, ring);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlowRingPainter old) =>
      old.rotation != rotation || old.intensity != intensity;
}

/// Pulsing gradient orb with a sparkles glyph — the AI identity mark.
class _AiOrb extends StatefulWidget {
  const _AiOrb({required this.size});

  final double size;

  @override
  State<_AiOrb> createState() => _AiOrbState();
}

class _AiOrbState extends State<_AiOrb> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final wave = (math.sin(_c.value * 2 * math.pi) + 1) / 2; // 0..1
        return Container(
          width: widget.size,
          height: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.size * 0.3),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_gradC, _gradB],
            ),
            boxShadow: [
              BoxShadow(
                color: _gradB.withValues(alpha: 0.30 + wave * 0.30),
                blurRadius: 12 + wave * 10,
                spreadRadius: wave * 1.5,
              ),
            ],
          ),
          child: Icon(LucideIcons.sparkles,
              size: widget.size * 0.46, color: Colors.white),
        );
      },
    );
  }
}

class _SuggestionChip extends StatefulWidget {
  const _SuggestionChip({
    required this.colors,
    required this.label,
    required this.onTap,
  });

  final AppColors colors;
  final String label;
  final VoidCallback? onTap;

  @override
  State<_SuggestionChip> createState() => _SuggestionChipState();
}

class _SuggestionChipState extends State<_SuggestionChip> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return GestureDetector(
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 110),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _pressed ? _gradB.withValues(alpha: 0.14) : colors.bg2,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _pressed
                  ? _gradB.withValues(alpha: 0.5)
                  : colors.border,
            ),
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: colors.text2,
            ),
          ),
        ),
      ),
    );
  }
}
