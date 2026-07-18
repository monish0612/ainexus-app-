import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/salary_entities.dart';

/// The day-of-month a monthly salary is credited. Per the user's cycle, the
/// salary recorded for month `M` lands on this day of the *previous* month
/// (e.g. the "July" salary is credited on the 28th of June). So a bill due in
/// month `X` is settled from the salary recorded for month `X` whenever the due
/// day falls before this credit day (the usual case).
const int kSalaryCreditDay = 28;

// ── Inputs ───────────────────────────────────────────────────────────────────

/// A credit card's billing cycle, decoupled from the presentation `Bank` model
/// so this engine stays in the core layer and is trivially unit-testable.
@immutable
class BankBillingConfig {
  const BankBillingConfig({
    required this.name,
    required this.statementDay,
    required this.dueDay,
    this.color = '#868E96',
  });

  final String name;
  final String color;

  /// Day-of-month (1-31) the statement closes.
  final int statementDay;

  /// Day-of-month (1-31) the bill is due, in the month after the statement
  /// closes.
  final int dueDay;
}

/// A single credit-card expense reduced to what the forecast needs. Carries the
/// [category] and [description] so the UI can drill from a statement total down
/// to the individual charges that make it up.
@immutable
class CardExpense extends Equatable {
  const CardExpense({
    required this.bank,
    required this.amount,
    required this.date,
    this.category = '',
    this.description = '',
  });

  final String bank;
  final double amount;
  final DateTime date;
  final String category;
  final String description;

  @override
  List<Object?> get props => [bank, amount, date, category, description];
}

// ── Outputs ──────────────────────────────────────────────────────────────────

/// One statement window for a card: the charges between two statement dates,
/// the date it closes, when the resulting bill is due, and which recorded
/// salary month settles it.
@immutable
class CardStatement extends Equatable {
  const CardStatement({
    required this.bankName,
    required this.color,
    required this.closeDate,
    required this.dueDate,
    required this.salaryMonthKey,
    required this.total,
    required this.isOpen,
    this.items = const [],
  });

  final String bankName;
  final String color;

  /// The date this statement closes (charges on/before it belong to it).
  final DateTime closeDate;

  /// The date the resulting bill is due (in the month after [closeDate]).
  final DateTime dueDate;

  /// 'YYYY-MM' of the recorded salary that settles this bill.
  final String salaryMonthKey;

  /// Total charged in this statement window.
  final double total;

  /// True while the window is still accumulating (now is on/before [closeDate]).
  final bool isOpen;

  /// The individual charges that make up this statement, newest first. Lets the
  /// UI expand a statement total into its line items.
  final List<CardExpense> items;

  @override
  List<Object?> get props =>
      [bankName, closeDate, dueDate, salaryMonthKey, total, isOpen, items];
}

/// A recorded salary month with the credit-card bills it must absorb and the
/// resulting projected in-hand balance.
@immutable
class SalaryMonthForecast extends Equatable {
  const SalaryMonthForecast({
    required this.monthKey,
    required this.salary,
    required this.bills,
  });

  final String monthKey;
  final double salary;
  final List<CardStatement> bills;

  String get monthLabel => monthKeyLabel(monthKey);

  /// Total credit-card bills settled from this salary.
  double get cardBills => bills.fold(0.0, (s, b) => s + b.total);

  /// Salary minus the card bills it must cover. Can be negative.
  double get projectedInHand => salary - cardBills;

  bool get hasSalary => salary > 0;

  /// True when the card bills alone exceed the recorded salary.
  bool get isShort => salary > 0 && cardBills > salary;

  @override
  List<Object?> get props => [monthKey, salary, bills];
}

/// The complete credit-card forecast: every derived statement, a forward
/// salary-vs-bills timeline, and the currently-open statement per card.
@immutable
class CreditCardForecast extends Equatable {
  const CreditCardForecast({
    required this.statements,
    required this.timeline,
    required this.openStatements,
    required this.unconfiguredBanks,
  });

  /// All derived statements across all configured CC banks, sorted by due date.
  final List<CardStatement> statements;

  /// Forward-looking per-salary-month rollup (current spending month + next 2).
  final List<SalaryMonthForecast> timeline;

  /// The current open (still accumulating) statement for each CC bank, sorted
  /// by close date. Empty entries (no current charges) are omitted.
  final List<CardStatement> openStatements;

  /// CC bank names found in the expenses that have no billing-cycle config
  /// (so they couldn't be forecast). Lets the UI nudge the user to set them up.
  final Set<String> unconfiguredBanks;

  bool get hasActivity => statements.isNotEmpty;

  static const empty = CreditCardForecast(
    statements: [],
    timeline: [],
    openStatements: [],
    unconfiguredBanks: {},
  );

  @override
  List<Object?> get props =>
      [statements, timeline, openStatements, unconfiguredBanks];
}

/// The timing of a single prospective card charge — used by the expense entry
/// form to tell the user, at log time, exactly which salary will repay it.
@immutable
class CardBillTiming extends Equatable {
  const CardBillTiming({
    required this.statementClose,
    required this.dueDate,
    required this.salaryMonthKey,
  });

  final DateTime statementClose;
  final DateTime dueDate;
  final String salaryMonthKey;

  String get salaryMonthLabel => monthKeyLabel(salaryMonthKey);

  @override
  List<Object?> get props => [statementClose, dueDate, salaryMonthKey];
}

// ── Date helpers (pure) ──────────────────────────────────────────────────────

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

DateTime _addMonths(DateTime monthStart, int delta) {
  return DateTime(monthStart.year, monthStart.month + delta, 1);
}

/// The statement-close date for a charge on [expense] given [statementDay].
/// Charges on/before the statement day close that month; later charges roll to
/// the next month's statement. The day is clamped to the month length.
DateTime statementCloseDate(DateTime expense, int statementDay) {
  final dimThis = _daysInMonth(expense.year, expense.month);
  final sThis = statementDay.clamp(1, dimThis);
  if (expense.day <= sThis) {
    return DateTime(expense.year, expense.month, sThis);
  }
  final next = DateTime(expense.year, expense.month + 1, 1);
  final dimNext = _daysInMonth(next.year, next.month);
  return DateTime(next.year, next.month, statementDay.clamp(1, dimNext));
}

/// The bill due date for a statement that closed on [close], in the following
/// month, clamped to the month length.
DateTime dueDateFor(DateTime close, int dueDay) {
  final next = DateTime(close.year, close.month + 1, 1);
  final dim = _daysInMonth(next.year, next.month);
  return DateTime(next.year, next.month, dueDay.clamp(1, dim));
}

/// The recorded-salary month ('YYYY-MM') that settles a bill due on [due].
/// salary[M] is credited on [creditDay] of month M-1, so a bill due before the
/// credit day is paid by that month's salary; on/after it, the next month's.
String repayingSalaryMonthKey(DateTime due, {int creditDay = kSalaryCreditDay}) {
  if (due.day >= creditDay) {
    return monthKeyOf(DateTime(due.year, due.month + 1, 1));
  }
  return monthKeyOf(due);
}

/// The salary month currently being "spent" as of [now] — the latest salary
/// already credited.
String currentSalaryMonthKey(DateTime now, {int creditDay = kSalaryCreditDay}) {
  if (now.day >= creditDay) {
    return monthKeyOf(DateTime(now.year, now.month + 1, 1));
  }
  return monthKeyOf(now);
}

/// Computes the timing for a single prospective credit-card charge.
CardBillTiming cardBillTimingFor({
  required DateTime expenseDate,
  required int statementDay,
  required int dueDay,
  int creditDay = kSalaryCreditDay,
}) {
  final close = statementCloseDate(expenseDate, statementDay);
  final due = dueDateFor(close, dueDay);
  final salaryMonth = repayingSalaryMonthKey(due, creditDay: creditDay);
  return CardBillTiming(
    statementClose: close,
    dueDate: due,
    salaryMonthKey: salaryMonth,
  );
}

// ── Forecast computation (pure) ──────────────────────────────────────────────

/// Builds the full credit-card forecast from configured CC banks, recent CC
/// expenses, and recorded salaries. Pure — no I/O — so it can be unit-tested in
/// isolation.
CreditCardForecast computeCreditCardForecast({
  required List<BankBillingConfig> ccBanks,
  required List<CardExpense> ccExpenses,
  required Map<String, double> salaryByMonth,
  required DateTime now,
  int creditDay = kSalaryCreditDay,
}) {
  String norm(String s) => s.trim().toLowerCase();
  final configByName = {for (final b in ccBanks) norm(b.name): b};

  // Group charges into statement windows keyed by (bankName, closeDate).
  final buckets = <String, _StatementBucket>{};
  final unconfigured = <String>{};

  for (final e in ccExpenses) {
    final cfg = configByName[norm(e.bank)];
    if (cfg == null) {
      unconfigured.add(e.bank);
      continue;
    }
    final close = statementCloseDate(e.date, cfg.statementDay);
    final key = '${norm(cfg.name)}|${close.toIso8601String()}';
    final bucket = buckets.putIfAbsent(
      key,
      () => _StatementBucket(config: cfg, closeDate: close),
    );
    bucket.total += e.amount;
    bucket.items.add(e);
  }

  final statements = <CardStatement>[];
  for (final b in buckets.values) {
    final due = dueDateFor(b.closeDate, b.config.dueDay);
    final items = b.items.toList()
      ..sort((x, y) => y.date.compareTo(x.date));
    statements.add(
      CardStatement(
        bankName: b.config.name,
        color: b.config.color,
        closeDate: b.closeDate,
        dueDate: due,
        salaryMonthKey: repayingSalaryMonthKey(due, creditDay: creditDay),
        total: b.total,
        // A statement is still open while now is on/before its close date.
        isOpen: !now.isAfter(b.closeDate),
        items: List.unmodifiable(items),
      ),
    );
  }
  statements.sort((a, b) => a.dueDate.compareTo(b.dueDate));

  // Forward timeline: current spending month + next two.
  final currentKey = currentSalaryMonthKey(now, creditDay: creditDay);
  final currentStart = _monthStartOfKey(currentKey) ?? DateTime(now.year, now.month, 1);
  final timelineKeys = [
    monthKeyOf(currentStart),
    monthKeyOf(_addMonths(currentStart, 1)),
    monthKeyOf(_addMonths(currentStart, 2)),
  ];

  final billsByMonth = <String, List<CardStatement>>{};
  for (final s in statements) {
    billsByMonth.putIfAbsent(s.salaryMonthKey, () => []).add(s);
  }

  final timeline = <SalaryMonthForecast>[];
  for (final key in timelineKeys) {
    timeline.add(
      SalaryMonthForecast(
        monthKey: key,
        salary: salaryByMonth[key] ?? 0.0,
        bills: List.unmodifiable(billsByMonth[key] ?? const []),
      ),
    );
  }

  // One open statement per bank (the currently accumulating window).
  final openByBank = <String, CardStatement>{};
  for (final s in statements) {
    if (!s.isOpen) continue;
    final k = norm(s.bankName);
    final existing = openByBank[k];
    if (existing == null || s.closeDate.isBefore(existing.closeDate)) {
      openByBank[k] = s;
    }
  }
  final openStatements = openByBank.values.toList()
    ..sort((a, b) => a.closeDate.compareTo(b.closeDate));

  return CreditCardForecast(
    statements: List.unmodifiable(statements),
    timeline: List.unmodifiable(timeline),
    openStatements: List.unmodifiable(openStatements),
    unconfiguredBanks: unconfigured,
  );
}

DateTime? _monthStartOfKey(String key) {
  final parts = key.split('-');
  if (parts.length < 2) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (y == null || m == null) return null;
  return DateTime(y, m, 1);
}

class _StatementBucket {
  _StatementBucket({required this.config, required this.closeDate});
  final BankBillingConfig config;
  final DateTime closeDate;
  double total = 0;
  final List<CardExpense> items = [];
}
