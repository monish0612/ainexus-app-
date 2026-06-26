import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';

/// Mirrors `BANKS` in `expense.ts`.
const List<String> expenseBanks = [
  'HDFC',
  'ICICI',
  'AXIS',
  'SCAPIA',
  'CASH',
];

/// Mirrors `CARD_TYPES` in `expense.ts`.
const List<String> expenseCardTypes = [
  'DB',
  'CC',
  'Cash',
];

/// Mirrors `CATEGORIES` in `expense.ts`.
const List<String> expenseCategories = [
  'Food',
  'Grocery',
  'Transport',
  'Entertainment',
  'Shopping',
  'Bills',
  'Health',
  'Fuel',
  'Travel',
  'Subscription',
  'Electronics',
  'Fashion',
  'Medical',
  'Education',
  'Family',
  'Friends',
  'Personal',
  'Investment',
  'Rent',
  'Insurance',
  'Gifts',
  'Charity',
  'Donation',
  'Pets',
  'Loan',
  'Others',
];

/// The single category that represents wealth-building rather than consumption.
///
/// Money logged under this category is **not** an expense: it is excluded from
/// every spend aggregation (month/today totals, budgets, charts, category /
/// bank / card breakdowns, trends, the home-screen widget) and is surfaced
/// separately as a portfolio in the Insights tab. This is the one source of
/// truth — all spend code routes its "is this consumption?" check through
/// [isInvestmentCategory].
const String kInvestmentCategory = 'Investment';

/// Whether [category] is the investment category. Whitespace/casing tolerant so
/// it stays correct even if a synced/legacy row arrives slightly differently
/// shaped (the category picker only ever emits the canonical 'Investment').
bool isInvestmentCategory(String? category) {
  final c = category?.trim();
  if (c == null || c.isEmpty) return false;
  return c.toLowerCase() == kInvestmentCategory.toLowerCase();
}

/// Convenience spend/investment partitioning for any [Expense] list.
extension ExpenseInvestmentFilter on Iterable<Expense> {
  /// Consumption only — drops investments. Use for every spend total/chart.
  Iterable<Expense> get spendOnly =>
      where((e) => !isInvestmentCategory(e.category));

  /// Investments only — the portfolio contributions.
  Iterable<Expense> get investmentsOnly =>
      where((e) => isInvestmentCategory(e.category));
}

/// Mirrors `CategoryLearning` in `expense.ts` (`Record<string, string>`).
typedef CategoryLearning = Map<String, String>;

const Set<String> _aiCategoryConfidenceValues = {
  'learned',
  'matched',
  'default',
};

@immutable
class Expense extends Equatable {
  const Expense({
    required this.id,
    required this.amount,
    required this.description,
    required this.category,
    required this.bank,
    required this.cardType,
    required this.date,
    required this.isManualCategory,
    this.comments = '',
  });

  final String id;
  final double amount;
  final String description;
  final String category;
  final String bank;
  final String cardType;
  final String date;
  final bool isManualCategory;

  /// Optional free-form note/reminder attached at log time. '' = none.
  final String comments;

  Expense copyWith({
    String? id,
    double? amount,
    String? description,
    String? category,
    String? bank,
    String? cardType,
    String? date,
    bool? isManualCategory,
    String? comments,
  }) {
    return Expense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      category: category ?? this.category,
      bank: bank ?? this.bank,
      cardType: cardType ?? this.cardType,
      date: date ?? this.date,
      isManualCategory: isManualCategory ?? this.isManualCategory,
      comments: comments ?? this.comments,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'description': description,
        'category': category,
        'bank': bank,
        'cardType': cardType,
        'date': date,
        'isManualCategory': isManualCategory,
        'comments': comments,
      };

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: (json['id'] ?? '').toString(),
      amount: (json['amount'] is num)
          ? (json['amount'] as num).toDouble()
          : double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      description: (json['description'] ?? '').toString(),
      category: (json['category'] ?? '').toString(),
      bank: (json['bank'] ?? '').toString(),
      cardType: (json['cardType'] ?? json['card_type'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      isManualCategory: json['isManualCategory'] == true ||
          json['is_manual_category'] == true,
      comments: (json['comments'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        amount,
        description,
        category,
        bank,
        cardType,
        date,
        isManualCategory,
        comments,
      ];
}

@immutable
class BudgetHistoryEntry extends Equatable {
  const BudgetHistoryEntry({
    required this.id,
    required this.amount,
    required this.setAt,
  });

  final String id;
  final double amount;
  final String setAt;

  BudgetHistoryEntry copyWith({
    String? id,
    double? amount,
    String? setAt,
  }) {
    return BudgetHistoryEntry(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      setAt: setAt ?? this.setAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'amount': amount,
        'setAt': setAt,
      };

  factory BudgetHistoryEntry.fromJson(Map<String, dynamic> json) {
    return BudgetHistoryEntry(
      id: (json['id'] ?? '').toString(),
      amount: (json['amount'] is num)
          ? (json['amount'] as num).toDouble()
          : double.tryParse(json['amount']?.toString() ?? '') ?? 0,
      setAt: (json['setAt'] ?? json['set_at'] ?? '').toString(),
    );
  }

  @override
  List<Object?> get props => [id, amount, setAt];
}

@immutable
class AICategoryResult extends Equatable {
  const AICategoryResult({
    required this.category,
    required this.confidence,
    required this.reasoning,
    required this.score,
  });

  final String category;
  /// One of `'learned'`, `'matched'`, `'default'` (see `AICategoryResult` in `aiCategorize.ts`).
  final String confidence;
  final String reasoning;
  final double score;

  Map<String, dynamic> toJson() => {
        'category': category,
        'confidence': confidence,
        'reasoning': reasoning,
        'score': score,
      };

  factory AICategoryResult.fromJson(Map<String, dynamic> json) {
    final confidence = (json['confidence'] ?? 'default').toString();
    final safeConfidence = _aiCategoryConfidenceValues.contains(confidence)
        ? confidence
        : 'default';
    return AICategoryResult(
      category: (json['category'] ?? 'Others').toString(),
      confidence: safeConfidence,
      reasoning: (json['reasoning'] ?? '').toString(),
      score: (json['score'] is num)
          ? (json['score'] as num).toDouble()
          : double.tryParse(json['score']?.toString() ?? '') ?? 0,
    );
  }

  @override
  List<Object?> get props => [category, confidence, reasoning, score];
}
