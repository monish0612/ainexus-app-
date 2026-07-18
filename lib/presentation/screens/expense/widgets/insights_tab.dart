import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../domain/entities/expense_entities.dart';
import './expense_item.dart';
import './salary_insights_card.dart';

/// Cumulative invested-by-month running totals (oldest → newest) for the
/// portfolio sparkline. Pure, null-safe and order-independent so it can be
/// unit-tested in isolation:
///   • Buckets by the 'YYYY-MM' prefix of each ISO date (malformed/short dates
///     fall back to the raw string — they still bucket deterministically and
///     never throw).
///   • Sorts month keys ascending, then emits the running cumulative sum.
///   • Returns an empty list for empty input (sparkline is then skipped).
List<double> investmentCumulativeMonthlySeries(
  Iterable<ExpenseData> investments,
) {
  final byMonth = <String, double>{};
  for (final e in investments) {
    final d = e.date;
    final key = d.length >= 7 ? d.substring(0, 7) : d;
    byMonth[key] = (byMonth[key] ?? 0) + e.amount;
  }
  if (byMonth.isEmpty) return const [];
  final keys = byMonth.keys.toList()..sort();
  var running = 0.0;
  return [
    for (final k in keys) running += byMonth[k]!,
  ];
}

class InsightsTab extends StatefulWidget {
  const InsightsTab({
    super.key,
    required this.expenses,
    required this.budget,
    this.onEasterEgg,
    this.onOpenInvestments,
    this.onOpenLoans,
  });

  final List<ExpenseData> expenses;
  final double budget;
  final Future<void> Function(String command)? onEasterEgg;

  /// Opens the dedicated Investments portfolio drill-down (tap on the
  /// investment KPI card). Wired by the parent to the timeframe screen.
  final VoidCallback? onOpenInvestments;

  /// Opens the dedicated Loan repayments drill-down (tap on the loan KPI card).
  /// Wired by the parent to the timeframe screen.
  final VoidCallback? onOpenLoans;

  @override
  State<InsightsTab> createState() => _InsightsTabState();
}

enum _Period { week, month, m3, m6, all, nt }

const List<String> _periodUiLabels = ['Week', 'Month', '3M', '6M', 'All', 'NT'];

/// Pure, timezone-aware period bucketing — the single source of truth for
/// "which insight period does an expense's logged date fall into?".
///
/// [periodKey] is an [_Period] name ('week' | 'month' | 'm3' | 'm6' | 'all' |
/// 'nt'). Investments are always excluded (they are wealth-building, not
/// spend). Rolling windows have an inclusive upper bound of end-of-today so a
/// *future*-dated entry (a next-month bill logged in advance) never leaks into
/// Week/Month/3M/6M — it surfaces under 'nt' (next month) and 'all'.
///
/// Kept a top-level pure function so the date→bucket contract can be unit
/// tested with a fixed `now`, independent of the (huge) widget tree.
List<ExpenseData> expensesInInsightPeriod(
  List<ExpenseData> all,
  String periodKey,
  DateTime now,
) {
  final spend = all.where((e) => !isNonSpendCategory(e.category));

  if (periodKey == 'nt') {
    final ntStart = DateTime(now.year, now.month + 1, 1);
    final ntEnd = DateTime(now.year, now.month + 2, 0, 23, 59, 59, 999);
    return spend.where((e) {
      final d = safeParseDate(e.date).toLocal();
      return !d.isBefore(ntStart) && !d.isAfter(ntEnd);
    }).toList();
  }

  final cut = switch (periodKey) {
    'week' => now.subtract(const Duration(days: 7)),
    'month' => now.subtract(const Duration(days: 30)),
    'm3' => now.subtract(const Duration(days: 90)),
    'm6' => DateTime(now.year, now.month - 6, now.day),
    _ => DateTime.fromMillisecondsSinceEpoch(0), // 'all'
  };
  // 'all' keeps no upper bound (all-time includes future-dated entries).
  final upper = periodKey == 'all'
      ? null
      : DateTime(now.year, now.month, now.day, 23, 59, 59, 999);

  return spend.where((e) {
    final d = safeParseDate(e.date).toLocal();
    if (d.isBefore(cut)) return false;
    if (upper != null && d.isAfter(upper)) return false;
    return true;
  }).toList();
}

const Map<_Period, String> _periodSubtitles = {
  _Period.week: 'last 7 days',
  _Period.month: 'last 30 days',
  _Period.m3: 'last 3 months',
  _Period.m6: 'last 6 months',
  _Period.all: 'all time',
  _Period.nt: 'next month',
};

class _TrendPoint {
  const _TrendPoint({required this.label, required this.amount});
  final String label;
  final double amount;
}

enum _DowViewMode { total, average, transactions }

const Map<_DowViewMode, String> _dowViewModeLabels = {
  _DowViewMode.total: 'Total',
  _DowViewMode.average: 'Avg/day',
  _DowViewMode.transactions: 'Txns',
};

class _DowBucket {
  const _DowBucket({
    required this.label,
    required this.shortLabel,
    required this.total,
    required this.txnCount,
    required this.occurrences,
    required this.activeDays,
  });

  final String label;
  final String shortLabel;
  final double total;
  final int txnCount;
  final int occurrences;
  final int activeDays;

  double get averagePerOccurrence => occurrences > 0 ? total / occurrences : 0;
  double get averagePerTxn => txnCount > 0 ? total / txnCount : 0;
}

class _DowSummary {
  const _DowSummary({
    required this.buckets,
    required this.totalSpend,
    required this.weekendShare,
  });

  final List<_DowBucket> buckets;
  final double totalSpend;
  final double weekendShare;
}

class _KpiSlide {
  const _KpiSlide({
    required this.label,
    required this.value,
    required this.sub,
    required this.accent,
    required this.emoji,
    required this.detailTitle,
    required this.detailExpenses,
  });

  final String label;
  final String value;
  final String sub;
  final Color accent;
  final String emoji;
  final String detailTitle;
  final List<ExpenseData> detailExpenses;
}

class _InsightsTabState extends State<InsightsTab> {
  static const List<_Period> _periods = _Period.values;

  final TextEditingController _searchCtrl = TextEditingController();
  late final PageController _kpiPageCtrl;
  _Period _period = _Period.month;
  int _visibleTxns = 20;
  bool _showHighest = true;
  int _kpiPage = 0;
  _DowViewMode _dowViewMode = _DowViewMode.total;
  int _selectedDowIndex = -1;

  static const _easterEggCommands = {
    'clear budget',
    'clear expenses',
    'clear all',
    'nuke',
  };

  @override
  void initState() {
    super.initState();
    _kpiPageCtrl = PageController(viewportFraction: 0.78, initialPage: 3000);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _kpiPageCtrl.dispose();
    super.dispose();
  }

  void _checkEasterEgg(String text) {
    final cmd = text.trim().toLowerCase();
    if (!_easterEggCommands.contains(cmd)) return;
    if (widget.onEasterEgg == null) return;

    _searchCtrl.clear();
    setState(() {});

    widget.onEasterEgg!(cmd).then((_) {
      if (!mounted) return;
      // 'nuke' shows its own cinematic result window (driven by the parent),
      // so we skip the lightweight inline toast for it.
      if (cmd == 'nuke') return;
      _showEasterEggNotification(cmd);
    });
  }

  void _showEasterEggNotification(String command) {
    final overlay = Overlay.of(context);
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) => _EasterEggToast(
        command: command,
        onDismiss: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }

  void _setPeriod(_Period p) {
    if (p == _period) return;
    setState(() {
      _period = p;
      _visibleTxns = 20;
      _selectedDowIndex = -1;
    });
  }

  void _showKpiDetail(
    BuildContext ctx,
    AppColors c,
    _KpiSlide slide,
  ) {
    if (slide.detailExpenses.isEmpty) return;
    showModalBottomSheet<void>(
      context: ctx,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _KpiDetailSheet(
        colors: c,
        slide: slide,
      ),
    );
  }

  String _dayKeyLocal(DateTime dt) {
    final l = dt.toLocal();
    return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  String _monthKeyFromString(String dateStr) =>
      dateStr.length >= 7 ? dateStr.substring(0, 7) : dateStr;

  DateTime _cutoff(_Period period) {
    final n = DateTime.now();
    switch (period) {
      case _Period.week:
        return n.subtract(const Duration(days: 7));
      case _Period.month:
        return n.subtract(const Duration(days: 30));
      case _Period.m3:
        return n.subtract(const Duration(days: 90));
      case _Period.m6:
        return DateTime(n.year, n.month - 6, n.day);
      case _Period.all:
        return DateTime.fromMillisecondsSinceEpoch(0);
      case _Period.nt:
        return DateTime(n.year, n.month + 1, 1);
    }
  }

  /// All investment transactions, newest-first — powers the portfolio card.
  List<ExpenseData> get _investmentsAll {
    final list = widget.expenses
        .where((e) => isInvestmentCategory(e.category))
        .toList()
      ..sort((a, b) => safeParseDate(b.date).compareTo(safeParseDate(a.date)));
    return list;
  }

  /// All loan repayment transactions, newest-first — powers the loan card.
  List<ExpenseData> get _loansAll {
    final list = widget.expenses
        .where((e) => isLoanCategory(e.category))
        .toList()
      ..sort((a, b) => safeParseDate(b.date).compareTo(safeParseDate(a.date)));
    return list;
  }

  List<ExpenseData> _periodExpenses() =>
      expensesInInsightPeriod(widget.expenses, _period.name, DateTime.now());

  /// Upper bound (inclusive) for a rolling period so future-dated entries (a
  /// next-month bill) don't leak into "Week/Month/3M/6M". `all` and `nt` have
  /// their own handling and return null here.
  DateTime? _periodUpperBound(_Period period) {
    if (period == _Period.all || period == _Period.nt) return null;
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day, 23, 59, 59, 999);
  }

  /// Investments that fall inside the currently-selected period — the "this
  /// period invested" figure on the portfolio card. Takes the already-computed
  /// investment list to avoid re-filtering/sorting the full expense history.
  double _investedInPeriod(List<ExpenseData> invs) {
    if (invs.isEmpty) return 0;
    if (_period == _Period.nt) {
      final n = DateTime.now();
      final ntStart = DateTime(n.year, n.month + 1, 1);
      final ntEnd = DateTime(n.year, n.month + 2, 0, 23, 59, 59, 999);
      return invs.where((e) {
        final d = safeParseDate(e.date).toLocal();
        return !d.isBefore(ntStart) && !d.isAfter(ntEnd);
      }).fold<double>(0, (s, e) => s + e.amount.toDouble());
    }
    final cut = _cutoff(_period);
    final upper = _periodUpperBound(_period);
    return invs.where((e) {
      final d = safeParseDate(e.date).toLocal();
      if (d.isBefore(cut)) return false;
      if (upper != null && d.isAfter(upper)) return false;
      return true;
    }).fold<double>(0, (s, e) => s + e.amount.toDouble());
  }

  /// Cumulative invested-by-month series (oldest→newest) for the card sparkline.
  /// Delegates to the pure [investmentCumulativeMonthlySeries] so the logic is
  /// unit-testable in isolation.
  List<double> _investmentCumulativeSeries(List<ExpenseData> invs) =>
      investmentCumulativeMonthlySeries(invs);

  List<_TrendPoint> _buildTrendSeries(
    List<ExpenseData> expenses,
    _Period period,
  ) {
    if (expenses.isEmpty) return const [];

    if (period == _Period.nt) {
      final n = DateTime.now();
      final ntStart = DateTime(n.year, n.month + 1, 1);
      final daysInMonth = DateTime(n.year, n.month + 2, 0).day;
      final grouped = <String, double>{};
      for (final e in expenses) {
        final k = _dayKeyLocal(safeParseDate(e.date));
        grouped[k] = (grouped[k] ?? 0) + e.amount.toDouble();
      }
      return List<_TrendPoint>.generate(daysInMonth, (i) {
        final d = ntStart.add(Duration(days: i));
        final key = _dayKeyLocal(d);
        final label = (i % 5 == 0 || i == daysInMonth - 1) ? '${d.day}' : '';
        return _TrendPoint(label: label, amount: grouped[key] ?? 0);
      });
    }

    if (period == _Period.all || period == _Period.m6 || period == _Period.m3) {
      final mm = <String, double>{};
      for (final e in expenses) {
        final m = _monthKeyFromString(e.date);
        mm[m] = (mm[m] ?? 0) + e.amount.toDouble();
      }
      final keys = mm.keys.toList()..sort();
      if (keys.isEmpty) return const [];
      final start = safeParseDate('${keys.first}-01');
      final lastKey = safeParseDate('${keys.last}-01');
      final now = DateTime.now();
      final endDate = lastKey.isAfter(now) ? lastKey : now;
      final out = <_TrendPoint>[];
      var cur = DateTime(start.year, start.month);
      final endM = DateTime(endDate.year, endDate.month);
      while (!cur.isAfter(endM)) {
        final k =
            '${cur.year.toString().padLeft(4, '0')}-${cur.month.toString().padLeft(2, '0')}';
        final label = DateFormat('MMM yy', 'en_IN').format(cur);
        out.add(_TrendPoint(label: label, amount: mm[k] ?? 0));
        cur = DateTime(cur.year, cur.month + 1);
      }
      return out;
    }

    final grouped = <String, double>{};
    for (final e in expenses) {
      final k = _dayKeyLocal(safeParseDate(e.date));
      grouped[k] = (grouped[k] ?? 0) + e.amount.toDouble();
    }

    final days = period == _Period.week ? 7 : 30;
    const dowShort = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    return List<_TrendPoint>.generate(days, (i) {
      final d = DateTime.now().subtract(Duration(days: days - 1 - i));
      final key = _dayKeyLocal(d);
      final label = period == _Period.week
          ? dowShort[d.weekday % 7]
          : (i % 6 == 0 || i == days - 1)
              ? '${d.day}'
              : '';
      return _TrendPoint(label: label, amount: grouped[key] ?? 0);
    });
  }

  DateTime _startOfDayLocal(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  DateTime _periodRangeStart(List<ExpenseData> expenses, _Period period) {
    if (period == _Period.nt) {
      final n = DateTime.now();
      return DateTime(n.year, n.month + 1, 1);
    }
    if (expenses.isEmpty || period != _Period.all) {
      return _startOfDayLocal(_cutoff(period));
    }

    var oldest = safeParseDate(expenses.first.date).toLocal();
    for (final e in expenses.skip(1)) {
      final current = safeParseDate(e.date).toLocal();
      if (current.isBefore(oldest)) oldest = current;
    }
    return _startOfDayLocal(oldest);
  }

  _DowSummary _buildDowSummary(List<ExpenseData> expenses, _Period period) {
    const labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const shortLabels = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];

    final totals = List<double>.filled(7, 0);
    final txnCounts = List<int>.filled(7, 0);
    final activeDateSets = List.generate(7, (_) => <String>{});

    for (final e in expenses) {
      final dt = safeParseDate(e.date).toLocal();
      final idx = (dt.weekday + 6) % 7;
      totals[idx] += e.amount.toDouble();
      txnCounts[idx]++;
      activeDateSets[idx].add(_dayKeyLocal(dt));
    }

    final occurrences = List<int>.filled(7, 0);
    final start = _periodRangeStart(expenses, period);
    final end = _startOfDayLocal(DateTime.now());
    for (var cursor = start; !cursor.isAfter(end); cursor = cursor.add(const Duration(days: 1))) {
      occurrences[(cursor.weekday + 6) % 7]++;
    }

    final totalSpend = totals.fold<double>(0, (sum, value) => sum + value);
    final weekendTotal = totals[5] + totals[6];

    return _DowSummary(
      buckets: List<_DowBucket>.generate(
        7,
        (i) => _DowBucket(
          label: labels[i],
          shortLabel: shortLabels[i],
          total: totals[i],
          txnCount: txnCounts[i],
          occurrences: occurrences[i],
          activeDays: activeDateSets[i].length,
        ),
      ),
      totalSpend: totalSpend,
      weekendShare: totalSpend > 0 ? (weekendTotal / totalSpend) * 100 : 0,
    );
  }

  double _dowMetricValue(_DowBucket bucket, _DowViewMode mode) {
    switch (mode) {
      case _DowViewMode.total:
        return bucket.total;
      case _DowViewMode.average:
        return bucket.averagePerOccurrence;
      case _DowViewMode.transactions:
        return bucket.txnCount.toDouble();
    }
  }

  int _peakDowIndex(List<_DowBucket> buckets, _DowViewMode mode) {
    var bestIndex = 0;
    var bestValue = -1.0;
    for (var i = 0; i < buckets.length; i++) {
      final value = _dowMetricValue(buckets[i], mode);
      if (value > bestValue) {
        bestValue = value;
        bestIndex = i;
      }
    }
    return bestIndex;
  }

  int _quietDowIndex(List<_DowBucket> buckets) {
    var quietIndex = -1;
    var quietValue = double.infinity;
    for (var i = 0; i < buckets.length; i++) {
      if (buckets[i].total <= 0) continue;
      if (buckets[i].total < quietValue) {
        quietValue = buckets[i].total;
        quietIndex = i;
      }
    }
    return quietIndex;
  }

  String _compactCurrency(num amount) {
    final abs = amount.abs();

    String compact(double value, String suffix) {
      final digits = value >= 100 ? 0 : 1;
      return '₹${value.toStringAsFixed(digits)}$suffix';
    }

    if (abs >= 10000000) {
      final out = compact(abs / 10000000, 'Cr');
      return amount < 0 ? '-$out' : out;
    }
    if (abs >= 100000) {
      final out = compact(abs / 100000, 'L');
      return amount < 0 ? '-$out' : out;
    }
    if (abs >= 1000) {
      final out = compact(abs / 1000, 'K');
      return amount < 0 ? '-$out' : out;
    }
    return formatCurrency(amount);
  }

  String _compactMetricValue(double value, _DowViewMode mode) {
    if (mode == _DowViewMode.transactions) {
      return value.toStringAsFixed(0);
    }
    return _compactCurrency(value);
  }

  String _dowInsightCopy({
    required _DowSummary summary,
    required _DowViewMode mode,
    required int peakIndex,
    required int quietIndex,
  }) {
    final peak = summary.buckets[peakIndex].label;
    final quiet = quietIndex >= 0 ? summary.buckets[quietIndex].label : null;
    final quietText = quiet == null ? '' : ' $quiet stays the lightest active day.';
    final weekendText =
        ' Weekend share is ${summary.weekendShare.toStringAsFixed(0)}%.';

    switch (mode) {
      case _DowViewMode.total:
        return '$peak carries the heaviest spend.$quietText$weekendText';
      case _DowViewMode.average:
        return '$peak has the strongest average weekday.$quietText$weekendText';
      case _DowViewMode.transactions:
        return '$peak records the most checkouts.$quietText$weekendText';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>()!;
    const accent = AppColors.accent;

    final periodExp = _periodExpenses();
    final trendData = _buildTrendSeries(periodExp, _period);
    final dowSummary = _buildDowSummary(periodExp, _period);

    final total = periodExp.fold<double>(0, (s, e) => s + e.amount.toDouble());
    final txnCount = periodExp.length;

    int days;
    if (_period == _Period.all && periodExp.isNotEmpty) {
      var oldest = DateTime.now().millisecondsSinceEpoch;
      for (final e in periodExp) {
        final t = safeParseDate(e.date).toLocal().millisecondsSinceEpoch;
        if (t < oldest) oldest = t;
      }
      days = math.max(
        1,
        ((DateTime.now().millisecondsSinceEpoch - oldest) / 86400000).ceil(),
      );
    } else {
      days = switch (_period) {
        _Period.week => 7,
        _Period.month => 30,
        _Period.m3 => 90,
        _Period.m6 => 180,
        _Period.all => 1,
        _Period.nt => DateTime(DateTime.now().year, DateTime.now().month + 2, 0).day,
      };
    }
    final avgDay = days > 0 ? total / days : 0.0;

    // Category breakdown
    final byCat = <String, double>{};
    for (final e in periodExp) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount.toDouble();
    }
    String topCat = '—';
    String topCatEmoji = '📦';
    double topCatAmt = 0;
    if (byCat.isNotEmpty) {
      final sorted = byCat.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      topCat = sorted.first.key;
      topCatAmt = sorted.first.value;
      topCatEmoji = AppColors.categoryIcons[topCat] ?? '📦';
    }
    final catRows = byCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Bank breakdown
    final byBank = <String, double>{};
    final bankTxnCount = <String, int>{};
    for (final e in periodExp) {
      byBank[e.bank] = (byBank[e.bank] ?? 0) + e.amount.toDouble();
      bankTxnCount[e.bank] = (bankTxnCount[e.bank] ?? 0) + 1;
    }
    final bankRows = byBank.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Card type breakdown
    final byCard = <String, double>{};
    final cardTxnCount = <String, int>{};
    for (final e in periodExp) {
      byCard[e.cardType] = (byCard[e.cardType] ?? 0) + e.amount.toDouble();
      cardTxnCount[e.cardType] = (cardTxnCount[e.cardType] ?? 0) + 1;
    }
    final cardRows = byCard.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Highest single expense
    double highestSingle = 0;
    if (periodExp.isNotEmpty) {
      for (final e in periodExp) {
        if (e.amount > highestSingle) highestSingle = e.amount.toDouble();
      }
    }

    // Top 10 highest / lowest
    final sortedByAmtDesc = List<ExpenseData>.from(periodExp)
      ..sort((a, b) => b.amount.compareTo(a.amount));
    final top10Highest = sortedByAmtDesc.take(10).toList();
    final sortedByAmtAsc = List<ExpenseData>.from(periodExp)
      ..sort((a, b) => a.amount.compareTo(b.amount));
    final top10Lowest = sortedByAmtAsc.take(10).toList();

    // All transactions sorted by date (newest first)
    final allSorted = List<ExpenseData>.from(periodExp)
      ..sort(
        (a, b) => safeParseDate(b.date).compareTo(safeParseDate(a.date)),
      );
    final shownTxns = allSorted.take(_visibleTxns).toList();
    final hasMoreTxns = allSorted.length > _visibleTxns;

    // Search
    final q = _searchCtrl.text.trim().toLowerCase();
    final isSearching = q.isNotEmpty;
    final searchHits = isSearching
        ? (widget.expenses
              .where(
                (e) =>
                    e.description.toLowerCase().contains(q) ||
                    e.category.toLowerCase().contains(q) ||
                    e.bank.toLowerCase().contains(q) ||
                    e.cardType.toLowerCase().contains(q) ||
                    e.amount.toString().contains(q),
              )
              .toList()
            ..sort(
              (a, b) =>
                  safeParseDate(b.date).compareTo(safeParseDate(a.date)),
            ))
        : <ExpenseData>[];
    final searchTotal =
        searchHits.fold<double>(0, (s, e) => s + e.amount.toDouble());

    // Trend delta
    double? trendDelta;
    if (trendData.length >= 4) {
      final mid = trendData.length ~/ 2;
      final a =
          trendData.sublist(0, mid).fold<double>(0, (s, p) => s + p.amount);
      final b =
          trendData.sublist(mid).fold<double>(0, (s, p) => s + p.amount);
      if (a > 0) trendDelta = ((b - a) / a) * 100;
    }

    final maxTrendY = trendData.isEmpty
        ? 1.0
        : math.max(
            1.0,
            trendData.map((e) => e.amount).reduce(math.max) * 1.15,
          );
    final peakDowIndex = _peakDowIndex(dowSummary.buckets, _dowViewMode);
    final selectedDowIndex =
        _selectedDowIndex >= 0 && _selectedDowIndex < dowSummary.buckets.length
            ? _selectedDowIndex
            : peakDowIndex;
    final selectedDow = dowSummary.buckets[selectedDowIndex];
    final quietDowIndex = _quietDowIndex(dowSummary.buckets);
    final maxDow = math.max(
      1.0,
      dowSummary.buckets
              .map((bucket) => _dowMetricValue(bucket, _dowViewMode))
              .reduce(math.max) *
          1.22,
    );
    final hasDowData = dowSummary.totalSpend > 0;

    // ── Investment portfolio (kept entirely separate from spend) ──
    // Computed once per build and threaded into the helpers so we never
    // re-filter + re-sort the expense list three times for one card.
    final investments = _investmentsAll;
    final investedTotal =
        investments.fold<double>(0, (s, e) => s + e.amount.toDouble());
    final investedPeriod = _investedInPeriod(investments);
    final investSeries = _investmentCumulativeSeries(investments);

    // ── Loan repayments (debt, kept entirely separate from spend) ──
    // Reuses the same period / cumulative helpers as investments — both are
    // just "non-spend" lists surfaced in their own card.
    final loans = _loansAll;
    final loanTotal = loans.fold<double>(0, (s, e) => s + e.amount.toDouble());
    final loanPeriod = _investedInPeriod(loans);
    final loanSeries = _investmentCumulativeSeries(loans);

    return ColoredBox(
      color: c.bg,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          // ── Salary & income summary (tap → full salary stats) ──
          const SalaryInsightsCard(),
          // ── Search Bar ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              onSubmitted: _checkEasterEgg,
              textInputAction: TextInputAction.search,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: c.text,
              ),
              cursorColor: accent,
              decoration: InputDecoration(
                hintText: 'Search merchant, category, bank, amount…',
                hintStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: c.text4,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: isSearching ? accent : c.text4,
                ),
                suffixIcon: isSearching
                    ? IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                        icon: Icon(
                          Icons.close_rounded,
                          size: 20,
                          color: c.text3,
                        ),
                      )
                    : null,
                filled: true,
                fillColor: c.bg3,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color:
                        isSearching ? accent.withValues(alpha: 0.45) : c.border,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      BorderSide(color: accent.withValues(alpha: 0.7)),
                ),
              ),
            ),
          ),

          // ── Search results overlay ──
          if (isSearching) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${searchHits.length} result${searchHits.length != 1 ? 's' : ''}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (searchHits.isNotEmpty)
                    Text(
                      'Total: ${formatCurrency(searchTotal)}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.text3,
                      ),
                    ),
                ],
              ),
            ),
            if (searchHits.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                child: Column(
                  children: [
                    const Text('🔍', style: TextStyle(fontSize: 40)),
                    const SizedBox(height: 8),
                    Text(
                      'No results for "${_searchCtrl.text.trim()}"',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: c.text3,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.bg2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: searchHits.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: c.border2),
                    itemBuilder: (context, i) => _SearchExpenseRow(
                      colors: c,
                      expense: searchHits[i],
                      query: _searchCtrl.text.trim(),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 16),
          ],

          // ── Period Chips ──
          if (!isSearching) ...[
            _PeriodChipRow(
              colors: c,
              accent: accent,
              periods: _periods,
              selected: _period,
              onSelect: _setPeriod,
            ),

            // ── Investment portfolio (separate from spending) ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: _InvestmentPortfolioCard(
                colors: c,
                totalInvested: investedTotal,
                periodInvested: investedPeriod,
                periodLabel: _periodSubtitles[_period] ?? '',
                count: investments.length,
                cumulativeSeries: investSeries,
                onTap: widget.onOpenInvestments,
              ),
            ),

            // ── Loan repayments (separate from spending) ──
            // Only shown once at least one loan has been logged, so the Insights
            // tab stays clean for users who never track loans.
            if (loans.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: _LoanRepaymentCard(
                  colors: c,
                  totalRepaid: loanTotal,
                  periodRepaid: loanPeriod,
                  periodLabel: _periodSubtitles[_period] ?? '',
                  count: loans.length,
                  cumulativeSeries: loanSeries,
                  onTap: widget.onOpenLoans,
                ),
              ),

            // ── KPI Carousel ──
            Builder(builder: (_) {
              final slides = <_KpiSlide>[
                _KpiSlide(
                  label: 'TOTAL SPENT',
                  value: formatCurrency(total),
                  sub: '$txnCount transactions · ${_periodSubtitles[_period]}',
                  accent: accent,
                  emoji: '💰',
                  detailTitle: 'All expenses',
                  detailExpenses: allSorted,
                ),
                _KpiSlide(
                  label: 'AVERAGE / DAY',
                  value: formatCurrency(avgDay),
                  sub: '${_periodSubtitles[_period]} · $days days',
                  accent: const Color(0xFF34D399),
                  emoji: '📊',
                  detailTitle: 'Daily breakdown',
                  detailExpenses: allSorted,
                ),
                _KpiSlide(
                  label: 'TOP CATEGORY',
                  value: topCat,
                  sub: topCat == '—'
                      ? 'No data'
                      : '${formatCurrency(topCatAmt)} · ${(total > 0 ? (topCatAmt / total * 100) : 0).toStringAsFixed(0)}%',
                  accent: AppColors.categoryColors[topCat] ?? accent,
                  emoji: topCatEmoji,
                  detailTitle: '$topCat expenses',
                  detailExpenses: topCat == '—'
                      ? []
                      : allSorted.where((e) => e.category == topCat).toList(),
                ),
                _KpiSlide(
                  label: 'HIGHEST EXPENSE',
                  value: highestSingle > 0 ? formatCurrency(highestSingle) : '—',
                  sub: sortedByAmtDesc.isNotEmpty
                      ? sortedByAmtDesc.first.description
                      : 'No data',
                  accent: const Color(0xFFF87171),
                  emoji: '🔥',
                  detailTitle: 'Top expenses',
                  detailExpenses: sortedByAmtDesc.take(10).toList(),
                ),
                _KpiSlide(
                  label: 'MOST USED BANK',
                  value: bankRows.isNotEmpty ? bankRows.first.key : '—',
                  sub: bankRows.isNotEmpty
                      ? '${bankTxnCount[bankRows.first.key]} txns · ${formatCurrency(bankRows.first.value)}'
                      : 'No data',
                  accent: const Color(0xFFA78BFA),
                  emoji: '🏦',
                  detailTitle: bankRows.isNotEmpty
                      ? '${bankRows.first.key} expenses'
                      : 'Bank expenses',
                  detailExpenses: bankRows.isNotEmpty
                      ? allSorted
                          .where((e) => e.bank == bankRows.first.key)
                          .toList()
                      : [],
                ),
                _KpiSlide(
                  label: 'TOP CARD TYPE',
                  value: cardRows.isNotEmpty ? cardRows.first.key : '—',
                  sub: cardRows.isNotEmpty
                      ? '${cardTxnCount[cardRows.first.key]} txns · ${formatCurrency(cardRows.first.value)}'
                      : 'No data',
                  accent: const Color(0xFFFF922B),
                  emoji: '💳',
                  detailTitle: cardRows.isNotEmpty
                      ? '${cardRows.first.key} expenses'
                      : 'Card expenses',
                  detailExpenses: cardRows.isNotEmpty
                      ? allSorted
                          .where((e) => e.cardType == cardRows.first.key)
                          .toList()
                      : [],
                ),
              ];

              return Column(
                children: [
                  SizedBox(
                    height: 170,
                    child: PageView.builder(
                      controller: _kpiPageCtrl,
                      onPageChanged: (i) =>
                          setState(() => _kpiPage = i % slides.length),
                      itemBuilder: (context, index) {
                        final i = index % slides.length;
                        return _KpiCarouselCard(
                          slide: slides[i],
                          colors: c,
                          isActive: _kpiPage == i,
                          onTap: () => _showKpiDetail(
                            context,
                            c,
                            slides[i],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(slides.length, (i) {
                      final active = _kpiPage == i;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: active ? 22 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: active
                              ? slides[i].accent
                              : c.text5,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      );
                    }),
                  ),
                ],
              );
            }),

            if (widget.budget > 0) ...[
              const SizedBox(height: 16),
              _BudgetStrip(
                colors: c,
                spent: total,
                budget: widget.budget,
              ),
            ],

            const SizedBox(height: 20),

            // ── Spending Trend ──
            _SectionTitle(
              colors: c,
              title: 'Spending trend',
              subtitle: _period == _Period.all
                  ? 'Monthly totals · all time'
                  : 'Totals · ${_periodSubtitles[_period]}',
            ),
            _ChartCard(
              colors: c,
              accent: accent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatCurrency(total),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (trendDelta != null) ...[
                        const SizedBox(width: 10),
                        _TrendDeltaPill(delta: trendDelta),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 160,
                    child: trendData.isEmpty
                        ? Center(
                            child: Text(
                              'No data this period',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                color: c.text4,
                              ),
                            ),
                          )
                        : LineChart(
                            _trendLineChartData(
                              c: c,
                              accent: accent,
                              points: trendData,
                              maxY: maxTrendY,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // ── Spending by Day ──
            _SectionTitle(
              colors: c,
              title: 'Spending by day',
              subtitle: 'Weekday rhythm · ${_periodSubtitles[_period]}',
            ),
            _ChartCard(
              colors: c,
              accent: accent,
              child: hasDowData
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 240),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeOutCubic,
                          child: _DowHeroCard(
                            key: ValueKey<String>(
                              '${_dowViewMode.name}_$selectedDowIndex',
                            ),
                            colors: c,
                            accent: accent,
                            mode: _dowViewMode,
                            bucket: selectedDow,
                            totalSpend: dowSummary.totalSpend,
                            isPeak: selectedDowIndex == peakDowIndex,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _DowModeSwitcher(
                          colors: c,
                          accent: accent,
                          selected: _dowViewMode,
                          onSelect: (mode) {
                            if (mode == _dowViewMode) return;
                            setState(() => _dowViewMode = mode);
                          },
                        ),
                        const SizedBox(height: 14),
                        RepaintBoundary(
                          child: SizedBox(
                            height: 188,
                            child: BarChart(
                              _dowBarChartData(
                                c: c,
                                accent: accent,
                                buckets: dowSummary.buckets,
                                mode: _dowViewMode,
                                selectedIndex: selectedDowIndex,
                                peakIndex: peakDowIndex,
                                maxY: maxDow,
                                onSelect: (index) =>
                                    setState(() => _selectedDowIndex = index),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 86,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: dowSummary.buckets.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, i) => _DowDayCard(
                              colors: c,
                              accent: accent,
                              mode: _dowViewMode,
                              bucket: dowSummary.buckets[i],
                              selected: i == selectedDowIndex,
                              isPeak: i == peakDowIndex,
                              onTap: () =>
                                  setState(() => _selectedDowIndex = i),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DowInsightBanner(
                          colors: c,
                          accent: accent,
                          message: _dowInsightCopy(
                            summary: dowSummary,
                            mode: _dowViewMode,
                            peakIndex: peakDowIndex,
                            quietIndex: quietDowIndex,
                          ),
                        ),
                        if (_period == _Period.m3 ||
                            _period == _Period.m6 ||
                            _period == _Period.all) ...[
                          const SizedBox(height: 10),
                          Text(
                            'Long ranges compare better in Avg/day because raw totals stack fast over time.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: c.text4,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ],
                    )
                  : SizedBox(
                      height: 168,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.calendar_view_week_rounded,
                              size: 30,
                              color: c.text5,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'No weekday pattern yet',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: c.text3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add a few expenses to reveal your weekly rhythm.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                color: c.text5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),

            // ── Category Breakdown ──
            _SectionTitle(
              colors: c,
              title: 'Category breakdown',
              subtitle:
                  '${catRows.length} categories · ${_periodSubtitles[_period]}',
            ),
            _BreakdownCard(
              colors: c,
              emptyLabel: 'No expenses this period',
              child: catRows.isEmpty
                  ? null
                  : Column(
                      children: [
                        for (var i = 0; i < catRows.length; i++)
                          _CategoryRow(
                            colors: c,
                            name: catRows[i].key,
                            amount: catRows[i].value,
                            totalSpend: total,
                            showDivider: i < catRows.length - 1,
                            transactionCount: periodExp
                                .where((e) => e.category == catRows[i].key)
                                .length,
                          ),
                      ],
                    ),
            ),

            // ── Bank Breakdown ──
            if (bankRows.isNotEmpty) ...[
              _SectionTitle(
                colors: c,
                title: 'Bank breakdown',
                subtitle:
                    '${bankRows.length} banks · ${_periodSubtitles[_period]}',
              ),
              _BreakdownCard(
                colors: c,
                child: Column(
                  children: [
                    for (var i = 0; i < bankRows.length; i++)
                      _BankRow(
                        colors: c,
                        bank: bankRows[i].key,
                        amount: bankRows[i].value,
                        totalSpend: total,
                        showDivider: i < bankRows.length - 1,
                        txnCount: bankTxnCount[bankRows[i].key] ?? 0,
                      ),
                  ],
                ),
              ),
            ],

            // ── Card Type Breakdown ──
            if (cardRows.isNotEmpty) ...[
              _SectionTitle(
                colors: c,
                title: 'Card type breakdown',
                subtitle: 'Payment method usage',
              ),
              _BreakdownCard(
                colors: c,
                child: Column(
                  children: [
                    for (var i = 0; i < cardRows.length; i++)
                      _CardTypeRow(
                        colors: c,
                        cardType: cardRows[i].key,
                        amount: cardRows[i].value,
                        totalSpend: total,
                        showDivider: i < cardRows.length - 1,
                        txnCount: cardTxnCount[cardRows[i].key] ?? 0,
                      ),
                  ],
                ),
              ),
            ],

            // ── Top 10 Highest / Lowest toggle ──
            if (periodExp.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _showHighest
                            ? 'Top 10 highest'
                            : 'Top 10 lowest',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                        ),
                      ),
                    ),
                    Container(
                      decoration: BoxDecoration(
                        color: c.bg3,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _ToggleChip(
                            label: 'Highest',
                            selected: _showHighest,
                            colors: c,
                            onTap: () =>
                                setState(() => _showHighest = true),
                          ),
                          _ToggleChip(
                            label: 'Lowest',
                            selected: !_showHighest,
                            colors: c,
                            onTap: () =>
                                setState(() => _showHighest = false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              _BreakdownCard(
                colors: c,
                child: Column(
                  children: [
                    for (var i = 0;
                        i <
                            (_showHighest
                                ? top10Highest.length
                                : top10Lowest.length);
                        i++)
                      _TopExpenseItem(
                        colors: c,
                        rank: i + 1,
                        expense: _showHighest
                            ? top10Highest[i]
                            : top10Lowest[i],
                        showDivider: i <
                            (_showHighest
                                    ? top10Highest.length
                                    : top10Lowest.length) -
                                1,
                      ),
                  ],
                ),
              ),
            ],

            // ── All Transactions ──
            _SectionTitle(
              colors: c,
              title: 'All transactions',
              subtitle:
                  '${allSorted.length} expenses · ${_periodSubtitles[_period]}',
            ),
            if (allSorted.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                child: Center(
                  child: Text(
                    'No transactions this period',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: c.text4,
                    ),
                  ),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.bg2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < shownTxns.length; i++) ...[
                        if (i > 0) Divider(height: 1, color: c.border2),
                        _SearchExpenseRow(
                          colors: c,
                          expense: shownTxns[i],
                          query: '',
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (hasMoreTxns) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () =>
                          setState(() => _visibleTxns += 20),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: double.infinity,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Load ${math.min(20, allSorted.length - _visibleTxns)} more',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: accent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: AppColors.accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ] else if (allSorted.length > 20)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Center(
                    child: Text(
                      'All ${allSorted.length} transactions loaded',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: c.text5,
                      ),
                    ),
                  ),
                ),
            ],
          ],
        ],
      ),
    );
  }

  LineChartData _trendLineChartData({
    required AppColors c,
    required Color accent,
    required List<_TrendPoint> points,
    required double maxY,
  }) {
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].amount),
    ];
    return LineChartData(
      minX: 0,
      maxX: (points.length - 1).toDouble(),
      minY: 0,
      maxY: maxY,
      clipData: const FlClipData.all(),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        horizontalInterval: maxY > 0 ? maxY / 4 : 1,
        verticalInterval: math.max(1, points.length / 6).ceilToDouble(),
        getDrawingHorizontalLine: (_) =>
            FlLine(color: c.border2, strokeWidth: 1),
        getDrawingVerticalLine: (_) =>
            FlLine(color: c.border2, strokeWidth: 1),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 40,
            interval: maxY > 0 ? maxY / 4 : 1,
            getTitlesWidget: (v, _) {
              if (v < 0 || v > maxY * 1.01) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(
                  formatCurrency(v),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    color: c.text4,
                  ),
                ),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 22,
            interval: 1,
            getTitlesWidget: (v, meta) {
              final i = v.round();
              if (i < 0 || i >= points.length) {
                return const SizedBox.shrink();
              }
              final label = points[i].label;
              if (label.isEmpty) return const SizedBox.shrink();
              return SideTitleWidget(
                axisSide: meta.axisSide,
                fitInside: SideTitleFitInsideData.fromTitleMeta(meta),
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    color: c.text4,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      lineTouchData: LineTouchData(
        enabled: true,
        handleBuiltInTouches: true,
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => c.bg1.withValues(alpha: 0.97),
          tooltipBorder: BorderSide(color: accent.withValues(alpha: 0.45)),
          tooltipRoundedRadius: 12,
          getTooltipItems: (touched) => touched.map((s) {
            final idx = s.x.round().clamp(0, points.length - 1);
            final p = points[idx];
            final line = p.label.isNotEmpty
                ? '${p.label}\n${formatCurrency(s.y)}'
                : formatCurrency(s.y);
            return LineTooltipItem(
              line,
              GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            );
          }).toList(),
        ),
        getTouchedSpotIndicator: (bar, spots) => spots
            .map(
              (s) => TouchedSpotIndicatorData(
                FlLine(
                  color: accent.withValues(alpha: 0.35),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                ),
                FlDotData(
                  show: true,
                  getDotPainter: (spot, _, __, ___) => FlDotCirclePainter(
                    radius: 5,
                    color: accent,
                    strokeWidth: 2,
                    strokeColor: c.bg,
                  ),
                ),
              ),
            )
            .toList(),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          curveSmoothness: 0.28,
          barWidth: 2.5,
          color: accent,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.55),
                accent.withValues(alpha: 0.02),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }

  BarChartData _dowBarChartData({
    required AppColors c,
    required Color accent,
    required List<_DowBucket> buckets,
    required _DowViewMode mode,
    required int selectedIndex,
    required int peakIndex,
    required double maxY,
    required ValueChanged<int> onSelect,
  }) {
    return BarChartData(
      minY: 0,
      maxY: maxY,
      alignment: BarChartAlignment.spaceAround,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: false,
        horizontalInterval: maxY > 0 ? maxY / 4 : 1,
        getDrawingHorizontalLine: (_) => FlLine(
          color: c.border2.withValues(alpha: 0.5),
          strokeWidth: 0.8,
          dashArray: [4, 4],
        ),
      ),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        topTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 34,
            interval: maxY > 0 ? maxY / 4 : 1,
            getTitlesWidget: (v, meta) {
              if (v < 0 || v > maxY * 1.01) return const SizedBox.shrink();
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  _compactMetricValue(v, mode),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: c.text4,
                  ),
                ),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 24,
            getTitlesWidget: (v, meta) {
              final i = v.toInt();
              if (i < 0 || i >= 7) return const SizedBox.shrink();
              final isSelected = i == selectedIndex;
              final isPeak = i == peakIndex;
              return SideTitleWidget(
                axisSide: meta.axisSide,
                child: Text(
                  buckets[i].label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight:
                        isSelected || isPeak ? FontWeight.w800 : FontWeight.w600,
                    color: isSelected
                        ? c.text
                        : isPeak
                            ? accent
                            : c.text3,
                  ),
                ),
              );
            },
          ),
        ),
      ),
      barTouchData: BarTouchData(
        enabled: true,
        handleBuiltInTouches: true,
        touchCallback: (event, response) {
          final spot = response?.spot;
          if (!event.isInterestedForInteractions || spot == null) return;
          onSelect(spot.touchedBarGroupIndex);
        },
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (_) => c.bg1.withValues(alpha: 0.97),
          tooltipBorder: BorderSide(color: accent.withValues(alpha: 0.45)),
          tooltipRoundedRadius: 12,
          getTooltipItem: (group, _, rod, __) {
            final bucket = buckets[group.x];
            final copy = switch (mode) {
              _DowViewMode.total => '${bucket.label}\n${formatCurrency(bucket.total)} · ${bucket.txnCount} txns',
              _DowViewMode.average =>
                '${bucket.label}\n${formatCurrency(bucket.averagePerOccurrence)} avg · ${bucket.txnCount} txns',
              _DowViewMode.transactions =>
                '${bucket.label}\n${bucket.txnCount} txns · ${formatCurrency(bucket.total)}',
            };
            return BarTooltipItem(
              copy,
              GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: c.text,
              ),
            );
          },
        ),
      ),
      barGroups: [
        for (var i = 0; i < 7; i++)
          (() {
            final bucket = buckets[i];
            final value = _dowMetricValue(bucket, mode);
            final isSelected = i == selectedIndex;
            final isPeak = i == peakIndex;
            return BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: value > 0 ? value : maxY * 0.02,
                width: isSelected ? 24 : isPeak ? 22 : 20,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(10),
                ),
                gradient: value > 0
                    ? LinearGradient(
                        colors: isSelected
                            ? [AppColors.accentCyan, accent]
                            : isPeak
                                ? [accent, accent.withValues(alpha: 0.82)]
                            : [
                                accent.withValues(alpha: 0.55),
                                accent.withValues(alpha: 0.25),
                              ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      )
                    : LinearGradient(
                        colors: [
                          c.text5.withValues(alpha: 0.18),
                          c.text5.withValues(alpha: 0.06),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
              ),
            ],
            );
          })(),
      ],
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// ── Reusable Widgets ─────────────────────────────────────────────────────────
// ══════════════════════════════════════════════════════════════════════════════

class _PeriodChipRow extends StatelessWidget {
  const _PeriodChipRow({
    required this.colors,
    required this.accent,
    required this.periods,
    required this.selected,
    required this.onSelect,
  });

  final AppColors colors;
  final Color accent;
  final List<_Period> periods;
  final _Period selected;
  final ValueChanged<_Period> onSelect;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      child: Row(
        children: [
          for (var i = 0; i < periods.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: _PeriodChip(
                label: _periodUiLabels[periods[i].index],
                selected: selected == periods[i],
                colors: colors,
                accent: accent,
                onTap: () => onSelect(periods[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.colors,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppColors colors;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? accent : colors.bg3,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.35)
                  : colors.border,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : colors.text3,
            ),
          ),
        ),
      ),
    );
  }
}

class _KpiCarouselCard extends StatefulWidget {
  const _KpiCarouselCard({
    required this.slide,
    required this.colors,
    required this.isActive,
    required this.onTap,
  });

  final _KpiSlide slide;
  final AppColors colors;
  final bool isActive;
  final VoidCallback onTap;

  @override
  State<_KpiCarouselCard> createState() => _KpiCarouselCardState();
}

class _KpiCarouselCardState extends State<_KpiCarouselCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tapCtrl;

  @override
  void initState() {
    super.initState();
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _tapCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slide;
    final c = widget.colors;

    return AnimatedBuilder(
      animation: _tapCtrl,
      builder: (context, child) => Transform.scale(
        scale: _tapCtrl.value,
        child: child,
      ),
      child: GestureDetector(
        onTapDown: (_) => _tapCtrl.reverse(),
        onTapUp: (_) {
          _tapCtrl.forward();
          widget.onTap();
        },
        onTapCancel: () => _tapCtrl.forward(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.bg2,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: widget.isActive
                  ? s.accent.withValues(alpha: 0.35)
                  : c.border,
            ),
            boxShadow: widget.isActive
                ? [
                    BoxShadow(
                      color: s.accent.withValues(alpha: 0.18),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Positioned(
                right: -16,
                bottom: -16,
                child: IgnorePointer(
                  child: Text(
                    s.emoji,
                    style: TextStyle(
                      fontSize: 80,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: s.accent.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          s.emoji,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        s.label,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: s.accent.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    s.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    s.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      color: c.text3,
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Text(
                        'Tap to explore',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: c.text5,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 12,
                        color: c.text5,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KpiDetailSheet extends StatelessWidget {
  const _KpiDetailSheet({
    required this.colors,
    required this.slide,
  });

  final AppColors colors;
  final _KpiSlide slide;

  @override
  Widget build(BuildContext context) {
    final total = slide.detailExpenses.fold<double>(
      0,
      (s, e) => s + e.amount.toDouble(),
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (context, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: colors.bg1,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(24),
          ),
          border: Border(
            top: BorderSide(color: colors.border),
            left: BorderSide(color: colors.border),
            right: BorderSide(color: colors.border),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.text5,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: slide.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      slide.emoji,
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          slide.detailTitle,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: colors.text,
                          ),
                        ),
                        Text(
                          '${slide.detailExpenses.length} transactions · ${formatCurrency(total)}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: colors.text4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(color: colors.border2),
            Expanded(
              child: ListView.separated(
                controller: scrollCtrl,
                padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
                itemCount: slide.detailExpenses.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: colors.border2),
                itemBuilder: (context, i) {
                  final e = slide.detailExpenses[i];
                  final catColor = AppColors.categoryColors[e.category] ??
                      AppColors.accent;
                  final emoji =
                      AppColors.categoryIcons[e.category] ?? '📦';
                  final d = safeParseDate(e.date).toLocal();
                  final dateStr =
                      DateFormat('d MMM · hh:mm a', 'en_IN').format(d);

                  return Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: colors.text,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${e.category} · ${e.bank} · $dateStr',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 10,
                                  color: colors.text4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatCurrency(e.amount),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: colors.text,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact INR formatter (₹1.2K / ₹3.4L / ₹2.1Cr) used by the portfolio card's
/// secondary stats so large figures never overflow the pills. Public + pure so
/// it can be unit-tested directly.
String compactInr(num amount) {
  final abs = amount.abs();
  String c(double v, String s) =>
      '₹${v.toStringAsFixed(v >= 100 ? 0 : 1)}$s';
  if (abs >= 10000000) return amount < 0 ? '-${c(abs / 10000000, 'Cr')}' : c(abs / 10000000, 'Cr');
  if (abs >= 100000) return amount < 0 ? '-${c(abs / 100000, 'L')}' : c(abs / 100000, 'L');
  if (abs >= 1000) return amount < 0 ? '-${c(abs / 1000, 'K')}' : c(abs / 1000, 'K');
  return formatCurrency(amount);
}

/// Premium, standout portfolio card: total invested (cost basis) as the hero,
/// a cumulative-growth sparkline, and period / average sub-stats. Investments
/// are deliberately tracked here, never mixed into spending. Tapping opens the
/// full Investments drill-down. Fully theme-aware and overflow-safe.
class _InvestmentPortfolioCard extends StatelessWidget {
  const _InvestmentPortfolioCard({
    required this.colors,
    required this.totalInvested,
    required this.periodInvested,
    required this.periodLabel,
    required this.count,
    required this.cumulativeSeries,
    this.onTap,
  });

  final AppColors colors;
  final double totalInvested;
  final double periodInvested;
  final String periodLabel;
  final int count;
  final List<double> cumulativeSeries;
  final VoidCallback? onTap;

  static const _accent = AppColors.categoryInvestment; // 0xFF20C997

  @override
  Widget build(BuildContext context) {
    final isDark = colors.isDark;
    final useLightFg = isDark;
    final heroColor = useLightFg ? Colors.white : const Color(0xFF0F766E);
    final labelColor =
        useLightFg ? Colors.white.withValues(alpha: 0.55) : colors.text3;
    final subColor =
        useLightFg ? Colors.white.withValues(alpha: 0.40) : colors.text4;
    final isEmpty = count == 0;
    final avg = count > 0 ? totalInvested / count : 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEmpty ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [Color(0xFF04302C), Color(0xFF073D34), Color(0xFF052E2B)]
                  : const [Color(0xFFECFDF5), Color(0xFFD1FAE5)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _accent.withValues(alpha: isDark ? 0.32 : 0.40),
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: isDark ? 0.22 : 0.16),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Text('📈', style: TextStyle(fontSize: 17)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'INVESTMENT PORTFOLIO',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: labelColor,
                      ),
                    ),
                  ),
                  if (!isEmpty && onTap != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Manage',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 17, color: _accent),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (isEmpty)
                _buildEmpty(subColor)
              else
                _buildBody(heroColor, labelColor, subColor, avg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(Color subColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Start your portfolio',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.isDark ? Colors.white : const Color(0xFF0F766E),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Log an expense under the Investment category and it is tracked here as wealth — never counted against your spending.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    height: 1.45,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    Color heroColor,
    Color labelColor,
    Color subColor,
    double avg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL INVESTED',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: totalInvested),
                    duration: const Duration(milliseconds: 750),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatCurrency(value),
                        maxLines: 1,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1,
                          color: heroColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count investment${count == 1 ? '' : 's'} · cost basis',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
            if (cumulativeSeries.length >= 2)
              SizedBox(
                width: 92,
                height: 46,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    values: cumulativeSeries,
                    color: _accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _miniStat(
                label: 'THIS ${periodLabel.toUpperCase()}',
                value: compactInr(periodInvested),
                labelColor: labelColor,
                valueColor: heroColor,
              ),
            ),
            Container(
              width: 1,
              height: 26,
              color: heroColor.withValues(alpha: 0.12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _miniStat(
                label: 'AVG / INVESTMENT',
                value: compactInr(avg),
                labelColor: labelColor,
                valueColor: heroColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniStat({
    required String label,
    required String value,
    required Color labelColor,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// Dedicated "Loan Repayments" KPI card — mirrors [_InvestmentPortfolioCard] in
/// layout but is themed for debt (amber accent). Loan-category expenses are not
/// consumption: they never touch the monthly budget and are surfaced here as
/// total repaid, this-period repaid and a cumulative trend.
class _LoanRepaymentCard extends StatelessWidget {
  const _LoanRepaymentCard({
    required this.colors,
    required this.totalRepaid,
    required this.periodRepaid,
    required this.periodLabel,
    required this.count,
    required this.cumulativeSeries,
    this.onTap,
  });

  final AppColors colors;
  final double totalRepaid;
  final double periodRepaid;
  final String periodLabel;
  final int count;
  final List<double> cumulativeSeries;
  final VoidCallback? onTap;

  static const _accent = AppColors.categoryLoan; // 0xFFFAB005

  @override
  Widget build(BuildContext context) {
    final isDark = colors.isDark;
    final useLightFg = isDark;
    final heroColor = useLightFg ? Colors.white : const Color(0xFF92660A);
    final labelColor =
        useLightFg ? Colors.white.withValues(alpha: 0.55) : colors.text3;
    final subColor =
        useLightFg ? Colors.white.withValues(alpha: 0.40) : colors.text4;
    final isEmpty = count == 0;
    final avg = count > 0 ? totalRepaid / count : 0.0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEmpty ? null : onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isDark
                  ? const [Color(0xFF352A05), Color(0xFF433609), Color(0xFF2C2405)]
                  : const [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _accent.withValues(alpha: isDark ? 0.32 : 0.40),
            ),
            boxShadow: [
              BoxShadow(
                color: _accent.withValues(alpha: isDark ? 0.22 : 0.16),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: _accent.withValues(alpha: 0.45),
                      ),
                    ),
                    child: const Text('💰', style: TextStyle(fontSize: 17)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'LOAN REPAYMENTS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: labelColor,
                      ),
                    ),
                  ),
                  if (!isEmpty && onTap != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Manage',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 17, color: _accent),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (isEmpty)
                _buildEmpty(subColor)
              else
                _buildBody(heroColor, labelColor, subColor, avg),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(Color subColor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Track your loans',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.isDark ? Colors.white : const Color(0xFF92660A),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Log an expense under the Loan category and it is tracked here as debt repayment — never counted against your monthly budget.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11.5,
                    height: 1.45,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    Color heroColor,
    Color labelColor,
    Color subColor,
    double avg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL REPAID',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: labelColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(begin: 0, end: totalRepaid),
                    duration: const Duration(milliseconds: 750),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        formatCurrency(value),
                        maxLines: 1,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          height: 1,
                          color: heroColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$count payment${count == 1 ? '' : 's'} · repaid',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: subColor,
                    ),
                  ),
                ],
              ),
            ),
            if (cumulativeSeries.length >= 2)
              SizedBox(
                width: 92,
                height: 46,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    values: cumulativeSeries,
                    color: _accent,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _miniStat(
                label: 'THIS ${periodLabel.toUpperCase()}',
                value: compactInr(periodRepaid),
                labelColor: labelColor,
                valueColor: heroColor,
              ),
            ),
            Container(
              width: 1,
              height: 26,
              color: heroColor.withValues(alpha: 0.12),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _miniStat(
                label: 'AVG / PAYMENT',
                value: compactInr(avg),
                labelColor: labelColor,
                valueColor: heroColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _miniStat({
    required String label,
    required String value,
    required Color labelColor,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// Lightweight cumulative-growth sparkline (area + line). Pure paint, no
/// gestures — cheap and overflow-proof. Renders nothing for <2 points.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final range = (maxV - minV).abs() < 1e-9 ? 1.0 : (maxV - minV);
    final dx = size.width / (values.length - 1);

    Offset pointAt(int i) {
      final x = dx * i;
      final norm = (values[i] - minV) / range;
      final y = size.height - (norm * (size.height - 4)) - 2;
      return Offset(x, y);
    }

    final linePath = Path();
    final fillPath = Path()..moveTo(0, size.height);
    for (var i = 0; i < values.length; i++) {
      final p = pointAt(i);
      if (i == 0) {
        linePath.moveTo(p.dx, p.dy);
      } else {
        linePath.lineTo(p.dx, p.dy);
      }
      fillPath.lineTo(p.dx, p.dy);
    }
    fillPath
      ..lineTo(size.width, size.height)
      ..close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.42),
          color.withValues(alpha: 0.02),
        ],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fillPath, fillPaint);

    final linePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    final last = pointAt(values.length - 1);
    canvas.drawCircle(last, 2.6, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

class _BudgetStrip extends StatelessWidget {
  const _BudgetStrip({
    required this.colors,
    required this.spent,
    required this.budget,
  });

  final AppColors colors;
  final double spent;
  final double budget;

  @override
  Widget build(BuildContext context) {
    final pct = math.min((spent / budget) * 100, 100.0);
    final over = spent > budget;
    final warn = !over && pct > 75;
    final pctColor = over
        ? const Color(0xFFF87171)
        : warn
            ? const Color(0xFFF59E0B)
            : const Color(0xFF34D399);
    final gradient = over
        ? const LinearGradient(
            colors: [Color(0xFFF87171), Color(0xFFEF4444)])
        : warn
            ? const LinearGradient(
                colors: [Color(0xFFF59E0B), Color(0xFFFBBF24)])
            : const LinearGradient(
                colors: [AppColors.accent, Color(0xFF34D399)]);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Budget progress',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: colors.text,
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: pctColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: colors.bg3),
                    FractionallySizedBox(
                      widthFactor: pct / 100,
                      alignment: Alignment.centerLeft,
                      child: DecoratedBox(
                        decoration: BoxDecoration(gradient: gradient),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${formatCurrency(spent)} spent',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: colors.text3,
                  ),
                ),
                Text(
                  over
                      ? '${formatCurrency(spent - budget)} over'
                      : '${formatCurrency(budget - spent)} left',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: over ? const Color(0xFFF87171) : colors.text3,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.colors,
    required this.title,
    this.subtitle,
  });

  final AppColors colors;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: colors.text,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                color: colors.text4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.colors,
    required this.accent,
    required this.child,
  });

  final AppColors colors;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.border),
        ),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: IgnorePointer(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(alpha: 0.08),
                  ),
                ),
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class _DowHeroCard extends StatelessWidget {
  const _DowHeroCard({
    super.key,
    required this.colors,
    required this.accent,
    required this.mode,
    required this.bucket,
    required this.totalSpend,
    required this.isPeak,
  });

  final AppColors colors;
  final Color accent;
  final _DowViewMode mode;
  final _DowBucket bucket;
  final double totalSpend;
  final bool isPeak;

  @override
  Widget build(BuildContext context) {
    final share = totalSpend > 0 ? (bucket.total / totalSpend) * 100 : 0.0;
    final headline = switch (mode) {
      _DowViewMode.total => 'TOTAL ON ${bucket.label.toUpperCase()}',
      _DowViewMode.average => 'AVG ON ${bucket.label.toUpperCase()}',
      _DowViewMode.transactions => 'TRANSACTIONS ON ${bucket.label.toUpperCase()}',
    };
    final subtitle = switch (mode) {
      _DowViewMode.total =>
        '${bucket.txnCount} txns · ${share.toStringAsFixed(0)}% of spend',
      _DowViewMode.average =>
        '${bucket.occurrences} ${bucket.label.toLowerCase()}s in range · ${bucket.activeDays} active',
      _DowViewMode.transactions =>
        '${formatCurrency(bucket.total)} total spend · ${bucket.activeDays} active days',
    };

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: colors.isDark
              ? [
                  accent.withValues(alpha: 0.18),
                  AppColors.accentCyan.withValues(alpha: 0.08),
                ]
              : [
                  accent.withValues(alpha: 0.1),
                  AppColors.accentCyan.withValues(alpha: 0.05),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Text(
                  headline,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.9,
                    color: accent,
                  ),
                ),
              ),
              const Spacer(),
              if (isPeak)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0x1FF59E0B),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0x40F59E0B)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.local_fire_department_rounded,
                        size: 13,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Peak',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFFF59E0B),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            bucket.label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            switch (mode) {
              _DowViewMode.transactions => '${bucket.txnCount}',
              _ => _primaryValue(mode, bucket),
            },
            style: GoogleFonts.plusJakartaSans(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: colors.text,
              height: 1,
              letterSpacing: -0.7,
            ),
          ),
          if (mode == _DowViewMode.transactions)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'transactions',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.text3,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: colors.text3,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DowMiniPill(
                colors: colors,
                label: 'Share',
                value: '${share.toStringAsFixed(0)}%',
              ),
              _DowMiniPill(
                colors: colors,
                label: 'Avg txn',
                value: bucket.txnCount > 0
                    ? formatCurrency(bucket.averagePerTxn)
                    : '—',
              ),
              _DowMiniPill(
                colors: colors,
                label: 'Active',
                value: '${bucket.activeDays}/${bucket.occurrences}',
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _primaryValue(_DowViewMode mode, _DowBucket bucket) {
    switch (mode) {
      case _DowViewMode.total:
        return formatCurrency(bucket.total);
      case _DowViewMode.average:
        return formatCurrency(bucket.averagePerOccurrence);
      case _DowViewMode.transactions:
        return '${bucket.txnCount}';
    }
  }
}

class _DowMiniPill extends StatelessWidget {
  const _DowMiniPill({
    required this.colors,
    required this.label,
    required this.value,
  });

  final AppColors colors;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors.isDark
              ? [
                  AppColors.accent.withValues(alpha: 0.1),
                  AppColors.accentCyan.withValues(alpha: 0.05),
                ]
              : [
                  AppColors.accent.withValues(alpha: 0.06),
                  AppColors.accentCyan.withValues(alpha: 0.025),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colors.isDark
              ? AppColors.accent.withValues(alpha: 0.14)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.7,
              color: colors.text4,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: colors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _DowModeSwitcher extends StatelessWidget {
  const _DowModeSwitcher({
    required this.colors,
    required this.accent,
    required this.selected,
    required this.onSelect,
  });

  final AppColors colors;
  final Color accent;
  final _DowViewMode selected;
  final ValueChanged<_DowViewMode> onSelect;

  @override
  Widget build(BuildContext context) {
    IconData iconFor(_DowViewMode mode) {
      switch (mode) {
        case _DowViewMode.total:
          return Icons.bar_chart_rounded;
        case _DowViewMode.average:
          return Icons.auto_graph_rounded;
        case _DowViewMode.transactions:
          return Icons.receipt_long_rounded;
      }
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors.isDark
              ? [
                  AppColors.accent.withValues(alpha: 0.12),
                  AppColors.accentCyan.withValues(alpha: 0.08),
                ]
              : [
                  AppColors.accent.withValues(alpha: 0.06),
                  AppColors.accentCyan.withValues(alpha: 0.03),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.isDark
              ? AppColors.accent.withValues(alpha: 0.18)
              : AppColors.accent.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(
              alpha: colors.isDark ? 0.08 : 0.04,
            ),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          for (final mode in _DowViewMode.values) ...[
            if (mode != _DowViewMode.values.first) const SizedBox(width: 6),
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onSelect(mode),
                  borderRadius: BorderRadius.circular(12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: selected == mode
                            ? colors.isDark
                                ? [
                                    AppColors.accent.withValues(alpha: 0.32),
                                    AppColors.accentCyan.withValues(alpha: 0.18),
                                  ]
                                : [
                                    AppColors.accent.withValues(alpha: 0.16),
                                    AppColors.accentCyan.withValues(alpha: 0.08),
                                  ]
                            : colors.isDark
                                ? [
                                    AppColors.accent.withValues(alpha: 0.08),
                                    AppColors.accentCyan.withValues(alpha: 0.04),
                                  ]
                                : [
                                    AppColors.accent.withValues(alpha: 0.035),
                                    AppColors.accentCyan.withValues(alpha: 0.02),
                                  ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected == mode
                            ? accent.withValues(alpha: 0.24)
                            : AppColors.accent.withValues(
                                alpha: colors.isDark ? 0.08 : 0.04,
                              ),
                      ),
                      boxShadow: selected == mode
                          ? [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          iconFor(mode),
                          size: 14,
                          color: selected == mode
                              ? accent
                              : colors.isDark
                                  ? colors.text3
                                  : colors.text4,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _dowViewModeLabels[mode]!,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: selected == mode
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: selected == mode
                                ? accent
                                : colors.isDark
                                    ? colors.text3
                                    : colors.text4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DowDayCard extends StatelessWidget {
  const _DowDayCard({
    required this.colors,
    required this.accent,
    required this.mode,
    required this.bucket,
    required this.selected,
    required this.isPeak,
    required this.onTap,
  });

  final AppColors colors;
  final Color accent;
  final _DowViewMode mode;
  final _DowBucket bucket;
  final bool selected;
  final bool isPeak;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final surfaceGradient = selected
        ? LinearGradient(
            colors: colors.isDark
                ? [
                    AppColors.accent.withValues(alpha: 0.24),
                    AppColors.accentCyan.withValues(alpha: 0.14),
                  ]
                : [
                    AppColors.accent.withValues(alpha: 0.12),
                    AppColors.accentCyan.withValues(alpha: 0.07),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : isPeak
            ? LinearGradient(
                colors: colors.isDark
                    ? [
                        AppColors.accent.withValues(alpha: 0.14),
                        AppColors.accentCyan.withValues(alpha: 0.12),
                      ]
                    : [
                        AppColors.accent.withValues(alpha: 0.08),
                        AppColors.accentCyan.withValues(alpha: 0.06),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : LinearGradient(
                colors: colors.isDark
                    ? [
                        AppColors.accent.withValues(alpha: 0.1),
                        AppColors.accentCyan.withValues(alpha: 0.06),
                      ]
                    : [
                        AppColors.accent.withValues(alpha: 0.05),
                        AppColors.accentCyan.withValues(alpha: 0.025),
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              );

    String primaryValue() {
      switch (mode) {
        case _DowViewMode.total:
          return _compactCurrency(bucket.total);
        case _DowViewMode.average:
          return _compactCurrency(bucket.averagePerOccurrence);
        case _DowViewMode.transactions:
          return '${bucket.txnCount}';
      }
    }

    String secondaryValue() {
      switch (mode) {
        case _DowViewMode.total:
          return '${bucket.txnCount} txn${bucket.txnCount == 1 ? '' : 's'}';
        case _DowViewMode.average:
          return '${bucket.activeDays}/${bucket.occurrences} active';
        case _DowViewMode.transactions:
          return _compactCurrency(bucket.total);
      }
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: 94,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            gradient: surfaceGradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.28)
                  : isPeak
                      ? AppColors.accentCyan.withValues(alpha: 0.22)
                      : AppColors.accent.withValues(
                          alpha: colors.isDark ? 0.12 : 0.08,
                        ),
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : isPeak
                    ? [
                        BoxShadow(
                          color: AppColors.accentCyan.withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    bucket.shortLabel,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: selected
                          ? accent
                          : isPeak
                              ? AppColors.accentCyan
                              : colors.isDark
                                  ? colors.text2
                                  : colors.text3,
                    ),
                  ),
                  const Spacer(),
                  if (isPeak)
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
              const Spacer(),
              Text(
                primaryValue(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: mode == _DowViewMode.transactions ? 22 : 15,
                  fontWeight: FontWeight.w900,
                  color: colors.text,
                  height: 1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                secondaryValue(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: colors.text4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _compactCurrency(num amount) {
    final abs = amount.abs();

    String compact(double value, String suffix) {
      final digits = value >= 100 ? 0 : 1;
      return '₹${value.toStringAsFixed(digits)}$suffix';
    }

    if (abs >= 10000000) {
      final out = compact(abs / 10000000, 'Cr');
      return amount < 0 ? '-$out' : out;
    }
    if (abs >= 100000) {
      final out = compact(abs / 100000, 'L');
      return amount < 0 ? '-$out' : out;
    }
    if (abs >= 1000) {
      final out = compact(abs / 1000, 'K');
      return amount < 0 ? '-$out' : out;
    }
    return formatCurrency(amount);
  }
}

class _DowInsightBanner extends StatelessWidget {
  const _DowInsightBanner({
    required this.colors,
    required this.accent,
    required this.message,
  });

  final AppColors colors;
  final Color accent;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: colors.isDark
              ? [
                  AppColors.accent.withValues(alpha: 0.12),
                  AppColors.accentCyan.withValues(alpha: 0.08),
                ]
              : [
                  AppColors.accent.withValues(alpha: 0.065),
                  AppColors.accentCyan.withValues(alpha: 0.035),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.isDark
              ? AppColors.accent.withValues(alpha: 0.18)
              : AppColors.accent.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withValues(
              alpha: colors.isDark ? 0.08 : 0.035,
            ),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.insights_rounded,
              size: 15,
              color: accent,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                height: 1.5,
                color: colors.text3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownCard extends StatelessWidget {
  const _BreakdownCard({
    required this.colors,
    required this.child,
    this.emptyLabel,
  });

  final AppColors colors;
  final Widget? child;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: Container(
        decoration: BoxDecoration(
          color: colors.bg2,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: colors.border),
        ),
        child: child ??
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  emptyLabel ?? '',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    color: colors.text4,
                  ),
                ),
              ),
            ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.colors,
    required this.name,
    required this.amount,
    required this.totalSpend,
    required this.showDivider,
    required this.transactionCount,
  });

  final AppColors colors;
  final String name;
  final double amount;
  final double totalSpend;
  final bool showDivider;
  final int transactionCount;

  @override
  Widget build(BuildContext context) {
    final catColor =
        AppColors.categoryColors[name] ?? AppColors.categoryOthers;
    final emoji = AppColors.categoryIcons[name] ?? '📦';
    final pct = totalSpend > 0 ? (amount / totalSpend) * 100 : 0.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Text(emoji, style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                          ),
                        ),
                        Text(
                          '$transactionCount transactions',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: colors.text4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatCurrency(amount),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          color: colors.text,
                        ),
                      ),
                      Text(
                        '${pct.toStringAsFixed(1)}%',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: catColor.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: colors.bg3.withValues(alpha: 0.5),
                      ),
                      FractionallySizedBox(
                        widthFactor: (pct / 100).clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: ColoredBox(color: catColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: colors.border2),
      ],
    );
  }
}

class _BankRow extends StatelessWidget {
  const _BankRow({
    required this.colors,
    required this.bank,
    required this.amount,
    required this.totalSpend,
    required this.showDivider,
    required this.txnCount,
  });

  final AppColors colors;
  final String bank;
  final double amount;
  final double totalSpend;
  final bool showDivider;
  final int txnCount;

  @override
  Widget build(BuildContext context) {
    final bankColor = AppColors.bankColors[bank] ?? const Color(0xFF555555);
    final pct = totalSpend > 0 ? (amount / totalSpend) * 100 : 0.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bankColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('🏦',
                        style: TextStyle(fontSize: 18, color: bankColor)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bank,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                          ),
                        ),
                        Text(
                          '$txnCount transactions · ${pct.toStringAsFixed(1)}%',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: colors.text4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatCurrency(amount),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: colors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: colors.bg3.withValues(alpha: 0.5),
                      ),
                      FractionallySizedBox(
                        widthFactor: (pct / 100).clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: ColoredBox(color: bankColor),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: colors.border2),
      ],
    );
  }
}

class _CardTypeRow extends StatelessWidget {
  const _CardTypeRow({
    required this.colors,
    required this.cardType,
    required this.amount,
    required this.totalSpend,
    required this.showDivider,
    required this.txnCount,
  });

  final AppColors colors;
  final String cardType;
  final double amount;
  final double totalSpend;
  final bool showDivider;
  final int txnCount;

  static const _icons = <String, String>{
    'Debit Card': '💳',
    'Credit Card': '🪪',
    'Cash': '💵',
  };

  static const _iconColors = <String, Color>{
    'Debit Card': Color(0xFF339AF0),
    'Credit Card': Color(0xFFCC5DE8),
    'Cash': Color(0xFF51CF66),
  };

  @override
  Widget build(BuildContext context) {
    final icon = _icons[cardType] ?? '💳';
    final color = _iconColors[cardType] ?? const Color(0xFF555555);
    final pct = totalSpend > 0 ? (amount / totalSpend) * 100 : 0.0;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child:
                        Text(icon, style: const TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cardType,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                          ),
                        ),
                        Text(
                          '$txnCount transactions · ${pct.toStringAsFixed(1)}%',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            color: colors.text4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    formatCurrency(amount),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: colors.text,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 5,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ColoredBox(
                        color: colors.bg3.withValues(alpha: 0.5),
                      ),
                      FractionallySizedBox(
                        widthFactor: (pct / 100).clamp(0.0, 1.0),
                        alignment: Alignment.centerLeft,
                        child: ColoredBox(color: color),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, thickness: 1, color: colors.border2),
      ],
    );
  }
}

class _ToggleChip extends StatelessWidget {
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final AppColors colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : colors.text4,
          ),
        ),
      ),
    );
  }
}

class _TopExpenseItem extends StatelessWidget {
  const _TopExpenseItem({
    required this.colors,
    required this.rank,
    required this.expense,
    required this.showDivider,
  });

  final AppColors colors;
  final int rank;
  final ExpenseData expense;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final catColor =
        AppColors.categoryColors[expense.category] ?? AppColors.accent;
    final emoji = AppColors.categoryIcons[expense.category] ?? '📦';
    final d = safeParseDate(expense.date).toLocal();
    final dateStr = DateFormat('d MMM', 'en_IN').format(d);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: Text(
                  '#$rank',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: rank <= 3
                        ? const Color(0xFFF59E0B)
                        : colors.text4,
                  ),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    Text(emoji, style: const TextStyle(fontSize: 16)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.text,
                      ),
                    ),
                    Text(
                      '${expense.category} · $dateStr',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10,
                        color: colors.text4,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                formatCurrency(expense.amount),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: colors.text,
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: colors.border2),
      ],
    );
  }
}

class _TrendDeltaPill extends StatelessWidget {
  const _TrendDeltaPill({required this.delta});

  final double delta;

  @override
  Widget build(BuildContext context) {
    final up = delta >= 0;
    final fg = up ? const Color(0xFFF87171) : const Color(0xFF34D399);
    final bg = fg.withValues(alpha: 0.12);
    final br = fg.withValues(alpha: 0.25);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: br),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
            size: 14,
            color: fg,
          ),
          const SizedBox(width: 4),
          Text(
            '${up ? '+' : ''}${delta.toStringAsFixed(1)}%',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchExpenseRow extends StatelessWidget {
  const _SearchExpenseRow({
    required this.colors,
    required this.expense,
    required this.query,
  });

  final AppColors colors;
  final ExpenseData expense;
  final String query;

  @override
  Widget build(BuildContext context) {
    final catColor =
        AppColors.categoryColors[expense.category] ?? AppColors.accent;
    final emoji = AppColors.categoryIcons[expense.category] ?? '📦';
    final d = safeParseDate(expense.date).toLocal();
    final dateS = DateFormat('d MMM', 'en_IN').format(d);
    final timeS = DateFormat('hh:mm a', 'en_IN').format(d);
    final desc = expense.description;
    final idx =
        query.isEmpty ? -1 : desc.toLowerCase().indexOf(query.toLowerCase());

    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 14,
          bottom: 14,
          child: Container(
            width: 3,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Text(emoji, style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _highlightedTitle(
                      desc: desc,
                      idx: idx,
                      qLen: query.length,
                      catColor: catColor,
                      textColor: colors.text,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      children: [
                        Text(
                          expense.category,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: catColor.withValues(alpha: 0.85),
                          ),
                        ),
                        Text('●',
                            style: TextStyle(
                                fontSize: 8, color: colors.text5)),
                        Text(
                          dateS,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: colors.text4,
                          ),
                        ),
                        Text(
                          timeS,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11,
                            color: colors.text5,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '-${formatCurrency(expense.amount)}',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: colors.text,
                    ),
                  ),
                  Text(
                    expense.bank,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      color: colors.text4,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _highlightedTitle({
    required String desc,
    required int idx,
    required int qLen,
    required Color catColor,
    required Color textColor,
  }) {
    if (idx < 0 || qLen == 0) {
      return Text(
        desc,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      );
    }
    final end = math.min(idx + qLen, desc.length);
    return Text.rich(
      TextSpan(
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        children: [
          TextSpan(
            text: desc.substring(0, idx),
            style: TextStyle(color: textColor),
          ),
          TextSpan(
            text: desc.substring(idx, end),
            style: TextStyle(
              color: catColor,
              backgroundColor: catColor.withValues(alpha: 0.15),
            ),
          ),
          TextSpan(
            text: desc.substring(end),
            style: TextStyle(color: textColor),
          ),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// ── Easter Egg Notification ─────────────────────────────────────────────────

class _EasterEggToast extends StatefulWidget {
  const _EasterEggToast({required this.command, required this.onDismiss});

  final String command;
  final VoidCallback onDismiss;

  @override
  State<_EasterEggToast> createState() => _EasterEggToastState();
}

class _EasterEggToastState extends State<_EasterEggToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    _ctrl.forward();

    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _ctrl.reverse().then((_) {
          if (mounted) widget.onDismiss();
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final (emoji, title, sub, gradStart, gradEnd) = switch (widget.command) {
      'clear budget' => (
          '💸',
          'Budget Obliterated!',
          'Budget history has been wiped clean',
          const Color(0xFFFF6B6B),
          const Color(0xFFFF922B),
        ),
      'clear expenses' => (
          '🧹',
          'Expenses Purged!',
          'All expense records have been cleared',
          const Color(0xFF339AF0),
          const Color(0xFF6366F1),
        ),
      'clear all' => (
          '💥',
          'Total Wipeout!',
          'Budget & expenses — all gone. Fresh start!',
          const Color(0xFFCC5DE8),
          const Color(0xFFFF6B6B),
        ),
      _ => (
          '✨',
          'Done!',
          'Operation completed',
          const Color(0xFF34D399),
          const Color(0xFF339AF0),
        ),
    };

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: SlideTransition(
        position: _slideAnim,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [gradStart, gradEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: gradStart.withValues(alpha: 0.5),
                    blurRadius: 24,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white.withValues(alpha: 0.85),
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
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
