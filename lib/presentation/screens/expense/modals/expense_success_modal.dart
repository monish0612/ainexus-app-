import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/platform/local_file_image.dart';
import '../../../../core/platform/platform_capabilities.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';

/// Mirrors [SuccessConfidence] / [SuccessMeta] from `ExpenseSuccessModal.tsx`.
typedef SuccessConfidence = String;

class SuccessMeta {
  const SuccessMeta({
    required this.confidence,
    required this.reasoning,
    this.capturedImagePath,
  });

  final SuccessConfidence confidence;
  final String reasoning;
  final String? capturedImagePath;
}

class SuccessExpense {
  const SuccessExpense({
    required this.amount,
    required this.description,
    required this.category,
    required this.bank,
    required this.cardType,
  });

  final double amount;
  final String description;
  final String category;
  final String bank;
  final String cardType;
}

class _ConfStyle {
  const _ConfStyle({
    required this.label,
    required this.color,
    required this.bg,
    required this.icon,
    this.score,
  });

  final String label;
  final Color color;
  final Color bg;
  final IconData icon;
  final String? score;
}

/// Full-screen success flow (push with slide-up). Ring + check use green `#51CF66`.
class ExpenseSuccessModal extends StatefulWidget {
  const ExpenseSuccessModal({
    super.key,
    required this.expense,
    required this.meta,
    required this.budget,
    required this.totalSpent,
    required this.onAddAnother,
    required this.onDone,
  });

  final SuccessExpense expense;
  final SuccessMeta meta;
  final double budget;
  final double totalSpent;
  final VoidCallback onAddAnother;
  final VoidCallback onDone;

  static Future<void> show(
    BuildContext context, {
    required SuccessExpense expense,
    required SuccessMeta meta,
    required double budget,
    required double totalSpent,
    required VoidCallback onAddAnother,
    required VoidCallback onDone,
  }) {
    return Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black54,
        pageBuilder: (_, __, ___) => ExpenseSuccessModal(
          expense: expense,
          meta: meta,
          budget: budget,
          totalSpent: totalSpent,
          onAddAnother: onAddAnother,
          onDone: onDone,
        ),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<ExpenseSuccessModal> createState() => _ExpenseSuccessModalState();
}

class _ExpenseSuccessModalState extends State<ExpenseSuccessModal>
    with SingleTickerProviderStateMixin {
  int _phase = 0;
  late final AnimationController _ringController;

  static const _green = Color(0xFF51CF66);

  @override
  void initState() {
    super.initState();
    _ringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    Future<void>.delayed(const Duration(milliseconds: 120), () {
      if (mounted) {
        setState(() => _phase = 1);
        _ringController.forward();
      }
    });
    Future<void>.delayed(const Duration(milliseconds: 720), () {
      if (mounted) setState(() => _phase = 2);
    });
    Future<void>.delayed(const Duration(milliseconds: 1020), () {
      if (mounted) setState(() => _phase = 3);
    });
    Future<void>.delayed(const Duration(milliseconds: 1280), () {
      if (mounted) setState(() => _phase = 4);
    });
    Future<void>.delayed(const Duration(milliseconds: 1520), () {
      if (mounted) setState(() => _phase = 5);
    });
  }

  @override
  void dispose() {
    _ringController.dispose();
    super.dispose();
  }

  _ConfStyle _confStyle(SuccessConfidence c) {
    switch (c) {
      case 'learned':
        return const _ConfStyle(
          label: 'AI REMEMBERED',
          color: Color(0xFF818CF8),
          bg: Color(0x26818CF8),
          icon: LucideIcons.brain,
          score: '97',
        );
      case 'matched':
        return const _ConfStyle(
          label: 'AI DETECTED',
          color: Color(0xFF34D399),
          bg: Color(0x1F34D399),
          icon: LucideIcons.sparkles,
          score: '82',
        );
      case 'default':
        return const _ConfStyle(
          label: 'LOW CONFIDENCE',
          color: Color(0xFFF59E0B),
          bg: Color(0x1FF59E0B),
          icon: LucideIcons.sparkles,
          score: '30',
        );
      case 'manual':
      default:
        return const _ConfStyle(
          label: 'MANUAL OVERRIDE',
          color: Color(0xFFFBBF24),
          bg: Color(0x1FFBBF24),
          icon: LucideIcons.sparkles,
          score: null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final e = widget.expense;
    final meta = widget.meta;
    final catColor = AppColors.categoryColors[e.category] ?? AppColors.accent;
    final catIcon = AppColors.categoryIcons[e.category] ?? '📦';
    final conf = _confStyle(meta.confidence);

    final budget = widget.budget;
    final totalSpent = widget.totalSpent;
    final remaining = budget > 0 ? budget - totalSpent : 0.0;
    final thisExpensePct = budget > 0 ? (e.amount / budget) * 100 : 0.0;
    final usedPct = budget > 0 ? (totalSpent / budget) * 100 : 0.0;
    final overBudget = budget > 0 && remaining < 0;
    final usedClamped = usedPct.clamp(0.0, 100.0);

    final textTheme = GoogleFonts.plusJakartaSansTextTheme(Theme.of(context).textTheme);

    return Material(
      color: colors.bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.9),
                  radius: 1.2,
                  colors: [
                    const Color(0x477C3AED),
                    colors.bg.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Center(
                    child: Text(
                      'SUCCESS',
                      textAlign: TextAlign.center,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.text3,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2.5,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      children: [
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 148,
                          width: 148,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              AnimatedBuilder(
                                animation: _ringController,
                                builder: (context, child) {
                                  return CustomPaint(
                                    size: const Size(148, 148),
                                    painter: _RingPainter(
                                      progress: _phase >= 1
                                          ? _ringController.value
                                          : 0,
                                      trackColor: _green.withValues(alpha: 0.2),
                                      strokeColor: _green,
                                    ),
                                  );
                                },
                              ),
                              Container(
                                width: 118,
                                height: 118,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: colors.bg1,
                                  boxShadow: [
                                    BoxShadow(
                                      color: _green.withValues(alpha: 0.25),
                                      blurRadius: 40,
                                      spreadRadius: 2,
                                    ),
                                    BoxShadow(
                                      color: _green.withValues(alpha: 0.08),
                                      blurRadius: 80,
                                      spreadRadius: 8,
                                    ),
                                  ],
                                ),
                              ),
                              AnimatedScale(
                                scale: _phase >= 2 ? 1 : 0,
                                duration: const Duration(milliseconds: 420),
                                curve: Curves.elasticOut,
                                child: const Icon(
                                  LucideIcons.check,
                                  size: 50,
                                  color: _green,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        AnimatedOpacity(
                          opacity: _phase >= 3 ? 1 : 0,
                          duration: const Duration(milliseconds: 420),
                          child: Column(
                            children: [
                              Text(
                                'Expense Logged',
                                textAlign: TextAlign.center,
                                style: textTheme.headlineSmall?.copyWith(
                                  color: colors.text,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 30,
                                  letterSpacing: -0.6,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 32),
                                child: Text(
                                  'AI has successfully analyzed and categorized your transaction.',
                                  textAlign: TextAlign.center,
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colors.text3,
                                    height: 1.65,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 28),
                        AnimatedSlide(
                          offset: _phase >= 4 ? Offset.zero : const Offset(0, 0.08),
                          duration: const Duration(milliseconds: 420),
                          curve: Curves.easeOut,
                          child: AnimatedOpacity(
                            opacity: _phase >= 4 ? 1 : 0,
                            duration: const Duration(milliseconds: 420),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              child: _SummaryCard(
                                colors: colors,
                                textTheme: textTheme,
                                expense: e,
                                meta: meta,
                                catColor: catColor,
                                catIcon: catIcon,
                                conf: conf,
                                imagePath: meta.capturedImagePath,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        AnimatedOpacity(
                          opacity: _phase >= 5 ? 1 : 0,
                          duration: const Duration(milliseconds: 350),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (budget > 0) ...[
                                  Text(
                                    'Budget',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colors.text3,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: LinearProgressIndicator(
                                      value: usedClamped / 100,
                                      minHeight: 8,
                                      backgroundColor: colors.bg3,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        overBudget || usedPct > 85
                                            ? const Color(0xFFF87171)
                                            : AppColors.accent,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${formatCurrency(totalSpent)} spent',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colors.text2,
                                        ),
                                      ),
                                      Text(
                                        'of ${formatCurrency(budget)}',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colors.text4,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                Row(
                                  children: [
                                    Expanded(
                                      child: _ImpactTile(
                                        colors: colors,
                                        textTheme: textTheme,
                                        title: 'Budget impact',
                                        value: budget > 0
                                            ? '-${thisExpensePct.toStringAsFixed(1)}%'
                                            : 'N/A',
                                        subtitle: budget > 0
                                            ? '${usedPct.toStringAsFixed(0)}% used'
                                            : null,
                                        valueColor: overBudget
                                            ? const Color(0xFFF87171)
                                            : colors.text,
                                        subtitleColor: usedPct > 85
                                            ? const Color(0xFFF87171)
                                            : const Color(0xFFF59E0B),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: _ImpactTile(
                                        colors: colors,
                                        textTheme: textTheme,
                                        title: budget > 0
                                            ? 'Remaining'
                                            : 'Total logged',
                                        value: formatCurrency(
                                          budget > 0 ? remaining : totalSpent,
                                        ),
                                        subtitle: budget > 0
                                            ? (overBudget ? 'Over' : 'Left')
                                            : null,
                                        valueColor: overBudget
                                            ? const Color(0xFFF87171)
                                            : colors.text,
                                        subtitleColor: overBudget
                                            ? const Color(0xFFF87171)
                                            : const Color(0xFF34D399),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                FilledButton(
                                  onPressed: widget.onAddAnother,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.accent,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(LucideIcons.plus, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Add Another',
                                        style: textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton(
                                  onPressed: widget.onDone,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: colors.text2,
                                    side: BorderSide(color: colors.border),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: Text(
                                    'Dashboard',
                                    style: textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.strokeColor,
  });

  final double progress;
  final Color trackColor;
  final Color strokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const stroke = 4.0;
    final radius = size.width / 2 - stroke;

    final track = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, track);

    if (progress > 0) {
      const start = -3.14159 / 2;
      final sweep = 2 * 3.14159 * progress;
      final rect = Rect.fromCircle(center: center, radius: radius);

      final glow = Paint()
        ..color = strokeColor.withAlpha(0x40)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawArc(rect, start, sweep, false, glow);

      final arc = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, start, sweep, false, arc);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.colors,
    required this.textTheme,
    required this.expense,
    required this.meta,
    required this.catColor,
    required this.catIcon,
    required this.conf,
    this.imagePath,
  });

  final AppColors colors;
  final TextTheme textTheme;
  final SuccessExpense expense;
  final SuccessMeta meta;
  final Color catColor;
  final String catIcon;
  final _ConfStyle conf;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            Positioned(
              top: -40,
              right: -40,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: catColor.withValues(alpha: 0.15),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CATEGORY',
                              style: textTheme.labelSmall?.copyWith(
                                color: catColor,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.8,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              expense.category,
                              style: textTheme.headlineSmall?.copyWith(
                                color: colors.text,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          color: catColor.withValues(alpha: 0.08),
                          border: Border.all(color: colors.border),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: imagePath != null &&
                                PlatformCapabilities.canUseDartIoFiles
                            ? LocalFileImage(
                                path: imagePath!,
                                fit: BoxFit.cover,
                                fallback: Center(
                                  child: Text(
                                    catIcon,
                                    style: const TextStyle(fontSize: 42),
                                  ),
                                ),
                              )
                            : Center(
                                child: Text(
                                  catIcon,
                                  style: const TextStyle(fontSize: 42),
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'AMOUNT',
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.text3,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatCurrency(expense.amount),
                              style: textTheme.titleLarge?.copyWith(
                                color: colors.text,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 38,
                        color: colors.border,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MERCHANT',
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.text3,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              expense.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.copyWith(
                                color: colors.text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _Pill(
                        text: '🏦 ${expense.bank}',
                        fg: const Color(0xFFA78BFA),
                        bg: const Color(0x2E7C3AED),
                      ),
                      _Pill(
                        text:
                            '${_cardLead(expense.cardType)} ${expense.cardType}',
                        fg: colors.text2,
                        bg: colors.bg3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: conf.bg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: conf.color.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(conf.icon, size: 11, color: conf.color),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            conf.score != null
                                ? '${conf.label} • ${conf.score}% CONFIDENCE'
                                : conf.label,
                            style: textTheme.labelSmall?.copyWith(
                              color: conf.color,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (meta.reasoning.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      meta.reasoning,
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.text4,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _cardLead(String cardType) {
    if (cardType == 'Cash') return '💵';
    if (cardType == 'Credit Card') return '💳';
    return '🏦';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.fg,
    required this.bg,
  });

  final String text;
  final Color fg;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _ImpactTile extends StatelessWidget {
  const _ImpactTile({
    required this.colors,
    required this.textTheme,
    required this.title,
    required this.value,
    this.subtitle,
    required this.valueColor,
    this.subtitleColor,
  });

  final AppColors colors;
  final TextTheme textTheme;
  final String title;
  final String value;
  final String? subtitle;
  final Color valueColor;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.labelMedium?.copyWith(
              color: colors.text3,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: textTheme.titleLarge?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 21,
                  ),
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(width: 6),
                Text(
                  subtitle!,
                  style: textTheme.labelSmall?.copyWith(
                    color: subtitleColor ?? colors.text3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
