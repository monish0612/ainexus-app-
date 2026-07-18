import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../../core/theme/app_colors.dart';

/// Normalises a [DateTime] to local midnight so equality checks and
/// day-bucketing are stable regardless of the time component.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// A production-grade, fluid expense-date picker.
///
/// Replaces the old three-chip (Today / Yesterday / NM 1st) selector with a
/// beautiful inline calendar. The user can:
///  - tap a quick chip (Yesterday / Today / Tomorrow),
///  - open a smoothly-animated month calendar and pick *any* day (past months,
///    this month, or future months) by swiping between months.
///
/// The chosen [selectedDate] is what the whole expense pipeline logs against,
/// so an expense dated "last month" lands in last month, "next month" lands in
/// next month, etc.
class ExpenseDatePicker extends StatefulWidget {
  const ExpenseDatePicker({
    super.key,
    required this.selectedDate,
    required this.onChanged,
    this.label = 'EXPENSE DATE',
    this.firstDate,
    this.lastDate,
    this.initiallyExpanded = false,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onChanged;
  final String label;

  /// Earliest selectable day (inclusive). Defaults to 3 years in the past.
  final DateTime? firstDate;

  /// Latest selectable day (inclusive). Defaults to 2 years in the future.
  final DateTime? lastDate;

  final bool initiallyExpanded;

  @override
  State<ExpenseDatePicker> createState() => _ExpenseDatePickerState();
}

class _ExpenseDatePickerState extends State<ExpenseDatePicker> {
  static const int _anchorPage = 1200; // ~100 years of headroom either side.

  late bool _expanded;
  late DateTime _anchorMonth; // month shown at [_anchorPage].
  late PageController _pageController;
  int _currentPage = _anchorPage;

  DateTime get _firstDate =>
      widget.firstDate ?? DateTime(DateTime.now().year - 3, 1, 1);
  DateTime get _lastDate =>
      widget.lastDate ?? DateTime(DateTime.now().year + 2, 12, 31);

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    final sel = widget.selectedDate;
    _anchorMonth = DateTime(sel.year, sel.month);
    _pageController = PageController(initialPage: _anchorPage);
  }

  @override
  void didUpdateWidget(covariant ExpenseDatePicker old) {
    super.didUpdateWidget(old);
    // Keep the visible month aligned with the selection when it changes
    // externally (e.g. via a quick chip) and the calendar is open.
    if (!_isSameDay(old.selectedDate, widget.selectedDate) && _expanded) {
      _jumpToMonthOf(widget.selectedDate);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  DateTime _monthForPage(int page) =>
      DateTime(_anchorMonth.year, _anchorMonth.month + (page - _anchorPage));

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _inRange(DateTime d) {
    final day = dateOnly(d);
    return !day.isBefore(dateOnly(_firstDate)) &&
        !day.isAfter(dateOnly(_lastDate));
  }

  void _select(DateTime day, {bool collapse = false}) {
    final normalised = dateOnly(day);
    if (!_inRange(normalised)) return;
    HapticFeedback.selectionClick();
    widget.onChanged(normalised);
    if (collapse) {
      setState(() => _expanded = false);
    }
  }

  void _toggleCalendar() {
    HapticFeedback.lightImpact();
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      // Ensure the open calendar shows the month of the current selection.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToMonthOf(widget.selectedDate);
      });
    }
  }

  void _jumpToMonthOf(DateTime date) {
    final target = _anchorPage +
        ((date.year - _anchorMonth.year) * 12) +
        (date.month - _anchorMonth.month);
    if (!_pageController.hasClients) {
      _currentPage = target;
      return;
    }
    if (target == _currentPage) return;
    _pageController.jumpToPage(target);
    setState(() => _currentPage = target);
  }

  void _stepMonth(int delta) {
    HapticFeedback.selectionClick();
    _pageController.animateToPage(
      _currentPage + delta,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  // ── Relative descriptor for the selection summary ────────────────────────
  String _relativeLabel(DateTime day) {
    final today = dateOnly(DateTime.now());
    final diff = dateOnly(day).difference(today).inDays;
    if (diff == 0) return 'Today';
    if (diff == -1) return 'Yesterday';
    if (diff == 1) return 'Tomorrow';
    if (diff < 0 && diff >= -6) return '${-diff} days ago';
    if (diff > 0 && diff <= 6) return 'in $diff days';
    final sameYear = day.year == today.year;
    return DateFormat(sameYear ? 'EEE, d MMM' : 'EEE, d MMM yyyy').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final selected = widget.selectedDate;
    final today = dateOnly(DateTime.now());
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));

    // Clamp the whole control to a comfortable max width so it fills phones
    // edge-to-edge yet stays nicely proportioned (not stretched into sparse
    // rows) on tablets, foldables and large/desktop web surfaces.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: colors.text4,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: _QuickChip(
                colors: colors,
                label: 'Yesterday',
                selected: _isSameDay(selected, yesterday),
                onTap: () => _select(yesterday),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickChip(
                colors: colors,
                label: 'Today',
                selected: _isSameDay(selected, today),
                onTap: () => _select(today),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickChip(
                colors: colors,
                label: 'Tomorrow',
                selected: _isSameDay(selected, tomorrow),
                onTap: () => _select(tomorrow),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _SelectedDatePill(
          colors: colors,
          dateText: DateFormat('EEE, d MMM yyyy').format(selected),
          relative: _relativeLabel(selected),
          expanded: _expanded,
          onTap: _toggleCalendar,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: _expanded
              ? Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: _CalendarPanel(
                    colors: colors,
                    pageController: _pageController,
                    monthForPage: _monthForPage,
                    onPageChanged: (p) {
                      HapticFeedback.selectionClick();
                      setState(() => _currentPage = p);
                    },
                    onStepMonth: _stepMonth,
                    currentMonth: _monthForPage(_currentPage),
                    selectedDate: selected,
                    today: today,
                    isSameDay: _isSameDay,
                    inRange: _inRange,
                    onPickDay: (d) => _select(d, collapse: true),
                  ),
                )
              : const SizedBox.shrink(),
        ),
          ],
        ),
      ),
    );
  }
}

// ─── Quick chip ──────────────────────────────────────────────────────────────

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.colors,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppColors colors;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0x380D59F2) : colors.bg2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? AppColors.accent.withValues(alpha: 0.5)
                : colors.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: selected ? AppColors.accent : colors.text3,
          ),
        ),
      ),
    );
  }
}

// ─── Selected-date pill (toggles calendar) ───────────────────────────────────

class _SelectedDatePill extends StatelessWidget {
  const _SelectedDatePill({
    required this.colors,
    required this.dateText,
    required this.relative,
    required this.expanded,
    required this.onTap,
  });

  final AppColors colors;
  final String dateText;
  final String relative;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: expanded ? const Color(0x140D59F2) : colors.bg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: expanded
                  ? AppColors.accent.withValues(alpha: 0.45)
                  : colors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                LucideIcons.calendarDays,
                size: 18,
                color: expanded ? AppColors.accent : colors.text3,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateText,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      relative,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accent.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                child: Icon(
                  LucideIcons.chevronDown,
                  size: 18,
                  color: colors.text4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Calendar panel ──────────────────────────────────────────────────────────

class _CalendarPanel extends StatelessWidget {
  const _CalendarPanel({
    required this.colors,
    required this.pageController,
    required this.monthForPage,
    required this.onPageChanged,
    required this.onStepMonth,
    required this.currentMonth,
    required this.selectedDate,
    required this.today,
    required this.isSameDay,
    required this.inRange,
    required this.onPickDay,
  });

  final AppColors colors;
  final PageController pageController;
  final DateTime Function(int page) monthForPage;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onStepMonth;
  final DateTime currentMonth;
  final DateTime selectedDate;
  final DateTime today;
  final bool Function(DateTime a, DateTime b) isSameDay;
  final bool Function(DateTime d) inRange;
  final ValueChanged<DateTime> onPickDay;

  static const List<String> _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      decoration: BoxDecoration(
        color: colors.bg2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _NavButton(
                colors: colors,
                icon: LucideIcons.chevronLeft,
                onTap: () => onStepMonth(-1),
              ),
              Expanded(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: child,
                    ),
                    child: Text(
                      DateFormat('MMMM yyyy').format(currentMonth),
                      key: ValueKey<String>(
                        DateFormat('yyyy-MM').format(currentMonth),
                      ),
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.text,
                      ),
                    ),
                  ),
                ),
              ),
              _NavButton(
                colors: colors,
                icon: LucideIcons.chevronRight,
                onTap: () => onStepMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: Center(
                    child: Text(
                      w,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: colors.text4,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Height is derived from the available width so the always-6-row grid
          // fits exactly at any resolution — square cells never grow taller than
          // their box, so the last week (29–31) is never clipped.
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = _MonthGrid.spacing;
              final cell = (constraints.maxWidth - spacing * 6) / 7;
              final gridHeight = cell * _MonthGrid.rows + spacing * (_MonthGrid.rows - 1);
              return SizedBox(
                height: gridHeight,
                child: PageView.builder(
                  controller: pageController,
                  onPageChanged: onPageChanged,
                  itemBuilder: (context, page) {
                    return _MonthGrid(
                      colors: colors,
                      month: monthForPage(page),
                      selectedDate: selectedDate,
                      today: today,
                      isSameDay: isSameDay,
                      inRange: inRange,
                      onPickDay: onPickDay,
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.colors,
    required this.icon,
    required this.onTap,
  });

  final AppColors colors;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.bg3,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 18, color: colors.text2),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.colors,
    required this.month,
    required this.selectedDate,
    required this.today,
    required this.isSameDay,
    required this.inRange,
    required this.onPickDay,
  });

  final AppColors colors;
  final DateTime month;
  final DateTime selectedDate;
  final DateTime today;
  final bool Function(DateTime a, DateTime b) isSameDay;
  final bool Function(DateTime d) inRange;
  final ValueChanged<DateTime> onPickDay;

  /// A calendar always reserves 6 week-rows so its height is constant across
  /// months (no layout jump when swiping) and the panel height stays exact.
  static const int rows = 6;
  static const double spacing = 2;

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Sunday-first grid: Sun→0 … Sat→6.
    final leading = firstOfMonth.weekday % 7;

    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        childAspectRatio: 1,
      ),
      itemCount: rows * 7,
      itemBuilder: (context, index) {
        final dayNum = index - leading + 1;
        if (dayNum < 1 || dayNum > daysInMonth) {
          return const SizedBox.shrink();
        }
        final day = DateTime(month.year, month.month, dayNum);
        final selected = isSameDay(day, selectedDate);
        final isToday = isSameDay(day, today);
        final enabled = inRange(day);
        return _DayCell(
          colors: colors,
          day: dayNum,
          selected: selected,
          isToday: isToday,
          enabled: enabled,
          onTap: enabled ? () => onPickDay(day) : null,
        );
      },
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.colors,
    required this.day,
    required this.selected,
    required this.isToday,
    required this.enabled,
    required this.onTap,
  });

  final AppColors colors;
  final int day;
  final bool selected;
  final bool isToday;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color textColor;
    if (!enabled) {
      textColor = colors.text5;
    } else if (selected) {
      textColor = Colors.white;
    } else if (isToday) {
      textColor = AppColors.accent;
    } else {
      textColor = colors.text2;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Fill the cell (minus a hair of breathing room) but cap the circle
          // so it looks tidy on wide screens — never larger than its box, so it
          // can never overflow and trip a layout error on tiny screens.
          final diameter =
              (math.min(constraints.maxWidth, constraints.maxHeight) - 2)
                  .clamp(0.0, 44.0);
          return Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: diameter,
              height: diameter,
              alignment: Alignment.center,
              decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: selected
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF3B82F6), AppColors.accent],
                  )
                : null,
            color: selected
                ? null
                : (isToday
                    ? AppColors.accent.withValues(alpha: 0.12)
                    : Colors.transparent),
            border: isToday && !selected
                ? Border.all(color: AppColors.accent.withValues(alpha: 0.5))
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.accent.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$day',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: selected || isToday
                        ? FontWeight.w800
                        : FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
