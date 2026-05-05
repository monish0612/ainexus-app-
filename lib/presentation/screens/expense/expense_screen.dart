import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/di/injection.dart';
import '../../../core/services/expense_widget_service.dart';
import '../../../core/services/process_text_service.dart';
import '../../../core/services/telegram_logger.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/expense_entities.dart';
import '../../widgets/compact_header.dart';
import '../settings/settings_modal.dart';
import 'widgets/tracker_tab.dart';
import 'widgets/insights_tab.dart';
import 'widgets/expense_item.dart';
import 'modals/add_expense_modal.dart';
import 'modals/set_budget_modal.dart';
import 'modals/edit_expense_modal.dart';
import 'modals/expense_trend_modal.dart';
import 'modals/budget_history_modal.dart';

// ---------------------------------------------------------------------------
// Repository-backed providers (data survives restarts)
// ---------------------------------------------------------------------------

final expensesStreamProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchExpenses();
});

final budgetHistoryStreamProvider =
    StreamProvider<List<BudgetHistoryEntry>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchBudgetHistory();
});

final currentBudgetProvider = Provider<double>((ref) {
  final history = ref.watch(budgetHistoryStreamProvider).valueOrNull ?? [];
  return history.isNotEmpty ? history.first.amount : 0;
});

final learningsProvider =
    StateNotifierProvider<_LearningsCtrl, CategoryLearning>((ref) {
  return _LearningsCtrl(ref);
});

class _LearningsCtrl extends StateNotifier<CategoryLearning> {
  _LearningsCtrl(this._ref) : super({}) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    try {
      final repo = _ref.read(expenseRepositoryProvider);
      // Load local first, then merge from server in background
      state = await repo.getLearnings();
      repo.syncLearningsFromServer().then((_) async {
        state = await repo.getLearnings();
      });
    } catch (e) {
      TLog.w('Learnings', 'Failed to load learnings', error: e);
    }
  }

  Future<void> learnFromDescription(
    String description,
    String category,
  ) async {
    final repo = _ref.read(expenseRepositoryProvider);
    final words = description
        .toLowerCase()
        .split(RegExp(r'[\s,\-_/]+'))
        .where((w) => w.length > 3);
    final updated = Map<String, String>.from(state);
    for (final word in words) {
      updated[word] = category;
      await repo.saveLearning(word, category);
      // Sync each learning to server (fire-and-forget)
      repo.syncLearning(word, category);
    }
    state = updated;
  }
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class ExpenseScreen extends ConsumerStatefulWidget {
  const ExpenseScreen({super.key});

  @override
  ConsumerState<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends ConsumerState<ExpenseScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    Future.microtask(() {
      final repo = ref.read(expenseRepositoryProvider);
      repo.syncFromServer();
      repo.syncBudgetFromServer();
      repo.retryPendingClears();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  List<ExpenseData> _toExpenseData(List<Expense> expenses) {
    return expenses
        .map((e) => ExpenseData(
              id: e.id,
              amount: e.amount,
              description: e.description,
              category: e.category,
              bank: e.bank,
              cardType: e.cardType,
              date: e.date,
              isManualCategory: e.isManualCategory,
            ))
        .toList();
  }

  Expense _fromExpenseData(ExpenseData d) {
    return Expense(
      id: d.id,
      amount: d.amount,
      description: d.description,
      category: d.category,
      bank: d.bank,
      cardType: d.cardType,
      date: d.date,
      isManualCategory: d.isManualCategory,
    );
  }

  void _showSyncError() {
    if (!mounted) return;
    final colors = Theme.of(context).extension<AppColors>()!;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(LucideIcons.cloudOff, size: 16, color: colors.isDark ? Colors.white70 : Colors.white),
            const SizedBox(width: 8),
            Text(
              'Sync failed — saved locally',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.isDark ? Colors.white70 : Colors.white,
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        backgroundColor: const Color(0xFFF59E0B).withValues(alpha: 0.9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  void _openAddExpenseModal() {
    final learnings = ref.read(learningsProvider);
    final aiService = ref.read(aiCategorizeServiceProvider);

    showAddExpenseModal(
      context,
      learnings: learnings,
      categorize: (description, l) => aiService.categorize(description, l),
      smartParse: (text) => aiService.smartParse(text),
      onAdd: (payload, isManual, meta) async {
        final expense = Expense(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          amount: payload.amount,
          description: payload.description,
          category: payload.category,
          bank: payload.bank,
          cardType: payload.cardType,
          date: payload.date,
          isManualCategory: isManual,
        );
        final sw = Stopwatch()..start();
        try {
          final synced = await ref.read(expenseRepositoryProvider).addExpense(expense);
          sw.stop();
          TLog.i('Expense',
              '✅ Added in ${sw.elapsedMilliseconds}ms: ₹${payload.amount.toStringAsFixed(0)} | ${payload.description} | ${payload.category} | ${payload.bank}/${payload.cardType} | conf=${meta.confidence}');
          if (!synced) _showSyncError();
        } catch (e) {
          sw.stop();
          TLog.e('Expense', 'Failed to add expense (${sw.elapsedMilliseconds}ms)', error: e);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to save expense')),
            );
          }
        }
      },
      onTeachAI: (description, category) {
        ref
            .read(learningsProvider.notifier)
            .learnFromDescription(description, category);
      },
    );
  }

  void _openSetBudgetModal() {
    final currentBudget = ref.read(currentBudgetProvider);
    showSetBudgetModal(
      context,
      currentBudget: currentBudget,
      onSave: (amount) async {
        try {
          final synced = await ref.read(expenseRepositoryProvider).setBudget(amount);
          TLog.i('Expense', '📊 Budget set: ₹${amount.toStringAsFixed(0)}');
          if (!synced) _showSyncError();
        } catch (e) {
          TLog.e('Expense', 'Failed to set budget', error: e);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to set budget')),
            );
          }
        }
      },
    );
  }

  void _openEditExpenseModal(ExpenseData data) {
    final expense = _fromExpenseData(data);
    showEditExpenseModal(
      context,
      expense: expense,
      onUpdate: (updated) async {
        final sw = Stopwatch()..start();
        try {
          final synced = await ref.read(expenseRepositoryProvider).updateExpense(updated);
          sw.stop();
          TLog.i('Expense',
              '✏️ Updated in ${sw.elapsedMilliseconds}ms: ₹${updated.amount.toStringAsFixed(0)} | ${updated.description} | ${updated.category}');
          if (!synced) _showSyncError();
        } catch (e) {
          sw.stop();
          TLog.e('Expense', 'Failed to update expense (${sw.elapsedMilliseconds}ms)', error: e);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to update expense')),
            );
          }
        }
      },
    );
  }

  Future<void> _deleteExpense(String id) async {
    final sw = Stopwatch()..start();
    try {
      final synced = await ref.read(expenseRepositoryProvider).deleteExpense(id);
      sw.stop();
      TLog.i('Expense', '🗑️ Deleted in ${sw.elapsedMilliseconds}ms: $id');
      if (!synced) _showSyncError();
    } catch (e) {
      sw.stop();
      TLog.e('Expense', 'Failed to delete expense (${sw.elapsedMilliseconds}ms)', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete expense')),
        );
      }
    }
  }

  void _updateExpense(ExpenseData data) {
    final updated = _fromExpenseData(data);
    ref.read(expenseRepositoryProvider).updateExpense(updated).then((synced) {
      if (!mounted) return;
      if (!synced) _showSyncError();
    }).catchError((Object e) {
      TLog.e('Expense', 'Failed to update expense inline', error: e);
    });
  }

  Future<void> _handleEasterEgg(String command) async {
    final repo = ref.read(expenseRepositoryProvider);
    bool serverOk = true;
    switch (command) {
      case 'clear budget':
        serverOk = await repo.clearBudgetHistory();
      case 'clear expenses':
        serverOk = await repo.clearAllExpenses();
      case 'clear all':
        final b = await repo.clearBudgetHistory();
        final e = await repo.clearAllExpenses();
        serverOk = b && e;
    }
    if (!serverOk) {
      TLog.w('Expense', 'Easter egg "$command" — server sync pending, '
          'will retry automatically on next launch');
    }
  }

  void _openTrendModal() {
    final expenses = ref.read(expensesStreamProvider).valueOrNull ?? [];
    final budget = ref.read(currentBudgetProvider);
    showExpenseTrendModal(context, expenses: expenses, budget: budget);
  }

  void _openBudgetHistoryModal() {
    final budgetHistory =
        ref.read(budgetHistoryStreamProvider).valueOrNull ?? [];
    final expenses = ref.read(expensesStreamProvider).valueOrNull ?? [];
    final budget = ref.read(currentBudgetProvider);
    showBudgetHistoryModal(
      context,
      budgetHistory: budgetHistory,
      expenses: expenses,
      currentBudget: budget,
      onClose: () {},
    );
  }

  void _openAddExpenseModalWithImage(String imagePath) {
    final learnings = ref.read(learningsProvider);
    final aiService = ref.read(aiCategorizeServiceProvider);

    showAddExpenseModal(
      context,
      learnings: learnings,
      categorize: (description, l) => aiService.categorize(description, l),
      smartParse: (text) => aiService.smartParse(text),
      initialImagePath: imagePath,
      onAdd: (payload, isManual, meta) async {
        final expense = Expense(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          amount: payload.amount,
          description: payload.description,
          category: payload.category,
          bank: payload.bank,
          cardType: payload.cardType,
          date: payload.date,
          isManualCategory: isManual,
        );
        final sw = Stopwatch()..start();
        try {
          final synced =
              await ref.read(expenseRepositoryProvider).addExpense(expense);
          sw.stop();
          TLog.i('Expense',
              '✅ Added (shared) in ${sw.elapsedMilliseconds}ms: ₹${payload.amount.toStringAsFixed(0)} | ${payload.description} | ${payload.category}');
          if (!synced) _showSyncError();
        } catch (e) {
          sw.stop();
          TLog.e('Expense', 'Failed to add expense from share (${sw.elapsedMilliseconds}ms)', error: e);
        }
      },
      onTeachAI: (description, category) {
        ref
            .read(learningsProvider.notifier)
            .learnFromDescription(description, category);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingExpenseImageProvider, (prev, next) {
      if (next != null && next.isNotEmpty) {
        ref.read(pendingExpenseImageProvider.notifier).state = null;
        _openAddExpenseModalWithImage(next);
      }
    });

    final colors = Theme.of(context).extension<AppColors>()!;

    final expensesAsync = ref.watch(expensesStreamProvider);
    final expenses = expensesAsync.valueOrNull ?? [];
    final budget = ref.watch(currentBudgetProvider);
    final budgetHistory =
        ref.watch(budgetHistoryStreamProvider).valueOrNull ?? [];
    final learnings = ref.watch(learningsProvider);

    final expenseData = _toExpenseData(expenses);

    // Push today's summary to the home-screen expense widget (debounced, skip-if-unchanged)
    ExpenseWidgetService.instance.scheduleUpdate(
      expenses: expenses,
      monthBudget: budget,
    );

    return Column(
      children: [
        CompactHeader(
          title: 'Expense',
          onAvatarTap: () => showSettingsModal(context, ref),
        ),
        Container(
          color: colors.headerBg,
          child: TabBar(
            controller: _tabCtrl,
            labelColor: colors.text,
            unselectedLabelColor: colors.text3,
            indicatorColor: AppColors.accent,
            indicatorWeight: 2,
            dividerColor: colors.border,
            labelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
            tabs: const [
              Tab(text: 'Tracker'),
              Tab(text: 'Insights'),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              TabBarView(
                controller: _tabCtrl,
                children: [
                  TrackerTab(
                    expenses: expenseData,
                    budget: budget,
                    budgetHistory: budgetHistory,
                    learnings: learnings,
                    onAddExpense: _openAddExpenseModal,
                    onDeleteExpense: _deleteExpense,
                    onUpdateExpense: _updateExpense,
                    onSetBudget: _openSetBudgetModal,
                    onUpdateLearnings: () {},
                    onEditExpense: _openEditExpenseModal,
                    onShowTrend: _openTrendModal,
                    onShowBudgetHistory: _openBudgetHistoryModal,
                  ),
                  InsightsTab(
                    expenses: expenseData,
                    budget: budget,
                    onEasterEgg: _handleEasterEgg,
                  ),
                ],
              ),
              Positioned(
                right: 20,
                bottom: 20,
                child: AnimatedBuilder(
                  animation: _tabCtrl,
                  builder: (context, child) {
                    final onTracker =
                        _tabCtrl.index == 0 && !_tabCtrl.indexIsChanging;
                    return AnimatedOpacity(
                      opacity: onTracker ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 200),
                      child: IgnorePointer(
                        ignoring: !onTracker,
                        child: child,
                      ),
                    );
                  },
                  child: _AddExpenseFab(onTap: _openAddExpenseModal),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AddExpenseFab extends StatefulWidget {
  const _AddExpenseFab({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_AddExpenseFab> createState() => _AddExpenseFabState();
}

class _AddExpenseFabState extends State<_AddExpenseFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _scaleCtrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
      reverseDuration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleCtrl.forward(),
      onTapUp: (_) {
        _scaleCtrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _scaleCtrl.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7C3AED), Color(0xFF6366F1)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.6),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            LucideIcons.plus,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}
