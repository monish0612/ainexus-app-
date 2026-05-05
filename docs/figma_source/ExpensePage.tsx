import { useState, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { Plus } from 'lucide-react';
import type { Expense, CategoryLearning, BudgetHistoryEntry } from '../types/expense';
import { learnFromCorrection } from '../utils/categoryUtils';
import { TrackerTab } from '../components/expense/TrackerTab';
import { InsightsTab } from '../components/expense/InsightsTab';
import { AddExpenseModal } from '../components/expense/AddExpenseModal';
import { SetBudgetModal } from '../components/expense/SetBudgetModal';
import { EditExpenseModal } from '../components/expense/EditExpenseModal';
import { BudgetHistoryModal } from '../components/expense/BudgetHistoryModal';
import { ExpenseSuccessModal } from '../components/expense/ExpenseSuccessModal';
import type { SuccessMeta, SuccessExpense } from '../components/expense/ExpenseSuccessModal';
import { useSettings } from '../utils/settingsContext';
import { usePalette } from '../utils/palette';

interface ExpensePageProps {
  expenses: Expense[];
  budget: number;
  budgetHistory: BudgetHistoryEntry[];
  learnings: CategoryLearning;
  onAddExpense: (expense: Omit<Expense, 'id' | 'date'>) => void;
  onDeleteExpense: (id: string) => void;
  onUpdateExpense: (expense: Expense) => void;
  onSetBudget: (amount: number) => void;
  onUpdateLearnings: (learnings: CategoryLearning) => void;
}

const TABS = ['Tracker', 'Insights'] as const;
type Tab = typeof TABS[number];
const font = "'Plus Jakarta Sans', sans-serif";

export function ExpensePage({
  expenses, budget, budgetHistory, learnings,
  onAddExpense, onDeleteExpense, onUpdateExpense, onSetBudget, onUpdateLearnings,
}: ExpensePageProps) {
  const [activeTab, setActiveTab] = useState<Tab>('Tracker');
  const [showAdd, setShowAdd] = useState(false);
  const [showBudget, setShowBudget] = useState(false);
  const [showHistory, setShowHistory] = useState(false);
  const [editingExpense, setEditingExpense] = useState<Expense | null>(null);
  const [showSuccess, setShowSuccess] = useState(false);
  const [successExpense, setSuccessExpense] = useState<SuccessExpense | null>(null);
  const [successMeta, setSuccessMeta] = useState<SuccessMeta | null>(null);
  const [successTotalSpent, setSuccessTotalSpent] = useState(0);
  const touchStartX = useRef<number | null>(null);
  const tabBarRef = useRef<HTMLDivElement>(null);

  const handleTouchStart = (e: React.TouchEvent) => {
    touchStartX.current = e.touches[0].clientX;
  };

  const handleTouchEnd = (e: React.TouchEvent) => {
    if (touchStartX.current === null) return;
    const delta = e.changedTouches[0].clientX - touchStartX.current;
    if (Math.abs(delta) < 50) return;
    if (delta < 0 && activeTab === 'Tracker') setActiveTab('Insights');
    if (delta > 0 && activeTab === 'Insights') setActiveTab('Tracker');
    touchStartX.current = null;
  };

  const handleAddExpense = (expense: Omit<Expense, 'id' | 'date'>, isManual: boolean, meta: SuccessMeta) => {
    onAddExpense(expense);
    if (isManual) {
      const updated = learnFromCorrection(expense.description, expense.category, learnings);
      onUpdateLearnings(updated);
    }
    // Compute month total including this new expense
    const thisMonth = new Date().toISOString().slice(0, 7);
    const prevTotal = expenses
      .filter(e => e.date.startsWith(thisMonth))
      .reduce((sum, e) => sum + e.amount, 0);
    setSuccessExpense({ amount: expense.amount, description: expense.description, category: expense.category, bank: expense.bank, cardType: expense.cardType });
    setSuccessMeta(meta);
    setSuccessTotalSpent(prevTotal + expense.amount);
    // Show success after add modal has slid out
    setTimeout(() => setShowSuccess(true), 380);
  };

  const { openSettings } = useSettings();
  const p = usePalette();

  return (
    <div className="flex flex-col h-full" style={{ background: p.bg }}>

      {/* ── Compact header ── */}
      <div
        className="shrink-0 flex items-center justify-between px-4"
        style={{
          height: 52,
          paddingTop: 'env(safe-area-inset-top, 0px)',
          borderBottom: `1px solid ${p.border}`,
          background: p.headerBg,
        }}
      >
        {/* Left: profile avatar — opens Settings */}
        <motion.button
          whileTap={{ scale: 0.84 }}
          onClick={openSettings}
          className="flex items-center justify-center rounded-full"
          style={{
            width: 32, height: 32,
            background: 'linear-gradient(135deg, #0D59F2, #22D3EE)',
            padding: 2, flexShrink: 0,
          }}
        >
          <div style={{ width: '100%', height: '100%', borderRadius: '50%', background: p.isDark ? '#111' : '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontSize: 11, fontWeight: 800, color: p.isDark ? '#fff' : '#0F172A', fontFamily: font }}>AR</span>
          </div>
        </motion.button>

        {/* Center: app name */}
        <span style={{ fontSize: 17, fontWeight: 800, color: p.text, fontFamily: font, letterSpacing: '-0.3px' }}>
          MyWallet
        </span>

        {/* Right: spacer */}
        <div style={{ width: 32 }} />
      </div>

      {/* ── Tab bar ── */}
      <div
        ref={tabBarRef}
        className="shrink-0 flex relative"
        style={{ borderBottom: `1px solid ${p.border}`, background: p.headerBg }}
      >
        {TABS.map((tab) => (
          <button
            key={tab}
            onClick={() => setActiveTab(tab)}
            className="flex-1 flex flex-col items-center justify-center relative py-3"
            style={{ outline: 'none', background: 'transparent', border: 'none' }}
          >
            <span
              style={{
                fontSize: 14,
                fontWeight: activeTab === tab ? 700 : 500,
                color: activeTab === tab ? p.text : p.text3,
                fontFamily: font,
                letterSpacing: 0.1,
                transition: 'color 0.2s',
              }}
            >
              {tab}
            </span>
            {activeTab === tab && (
              <motion.div
                layoutId="tab-underline"
                className="absolute bottom-0"
                style={{ height: 3, left: '20%', right: '20%', background: '#7C3AED', borderRadius: '3px 3px 0 0' }}
                transition={{ type: 'spring', damping: 30, stiffness: 340 }}
              />
            )}
          </button>
        ))}
      </div>

      {/* ── Scrollable content ── */}
      <div
        className="flex-1 relative overflow-hidden"
        onTouchStart={handleTouchStart}
        onTouchEnd={handleTouchEnd}
      >
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={activeTab}
            className="absolute inset-0 overflow-y-auto"
            initial={{ opacity: 0, x: activeTab === 'Tracker' ? -28 : 28 }}
            animate={{ opacity: 1, x: 0 }}
            exit={{ opacity: 0, x: activeTab === 'Tracker' ? 28 : -28 }}
            transition={{ duration: 0.2, ease: 'easeOut' }}
          >
            {activeTab === 'Tracker' ? (
              <TrackerTab
                expenses={expenses}
                budget={budget}
                learnings={learnings}
                onDeleteExpense={onDeleteExpense}
                onEditExpense={setEditingExpense}
                onOpenBudget={() => setShowBudget(true)}
                onOpenHistory={() => setShowHistory(true)}
              />
            ) : (
              <InsightsTab expenses={expenses} budget={budget} />
            )}
          </motion.div>
        </AnimatePresence>

        {activeTab === 'Tracker' && (
          <motion.button
            whileTap={{ scale: 0.88 }}
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            onClick={() => setShowAdd(true)}
            className="absolute bottom-5 right-5 flex items-center justify-center rounded-full z-20"
            style={{
              width: 56, height: 56,
              background: 'linear-gradient(135deg, #7C3AED, #6366F1)',
              boxShadow: '0 4px 20px rgba(124,58,237,0.6)',
            }}
          >
            <Plus size={24} color="#fff" strokeWidth={2.5} />
          </motion.button>
        )}
      </div>

      {/* ── Modals ── */}
      <AddExpenseModal
        open={showAdd}
        onClose={() => setShowAdd(false)}
        onAdd={handleAddExpense}
        learnings={learnings}
        onTeachAI={(desc, cat) => {
          const updated = learnFromCorrection(desc, cat, learnings);
          onUpdateLearnings(updated);
        }}
      />

      <SetBudgetModal
        open={showBudget}
        current={budget}
        onClose={() => setShowBudget(false)}
        onSet={onSetBudget}
      />

      <EditExpenseModal
        open={editingExpense !== null}
        expense={editingExpense}
        onClose={() => setEditingExpense(null)}
        onUpdate={(updated) => { onUpdateExpense(updated); setEditingExpense(null); }}
      />

      <BudgetHistoryModal
        open={showHistory}
        onClose={() => setShowHistory(false)}
        budgetHistory={budgetHistory}
        expenses={expenses}
        currentBudget={budget}
      />

      <ExpenseSuccessModal
        open={showSuccess}
        expense={successExpense}
        meta={successMeta}
        budget={budget}
        totalSpent={successTotalSpent}
        onAddAnother={() => { setShowSuccess(false); setTimeout(() => setShowAdd(true), 300); }}
        onDone={() => setShowSuccess(false)}
      />
    </div>
  );
}