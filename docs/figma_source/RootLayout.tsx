import { useState, useEffect, useCallback } from 'react';
import { useLocation } from 'react-router';
import { BottomNav } from './BottomNav';
import { SettingsModal } from './SettingsModal';
import { useSettings } from '../utils/settingsContext';
import { createPalette } from '../utils/palette';
import type { Expense, CategoryLearning, BudgetHistoryEntry } from '../types/expense';
import { ExpensePage } from '../pages/ExpensePage';
import { NewsPage } from '../pages/NewsPage';
import { TutorPage } from '../pages/TutorPage';
import { CloudPage } from '../pages/CloudPage';

function useExpenseState() {
  const [expenses, setExpenses] = useState<Expense[]>(() => {
    try { return JSON.parse(localStorage.getItem('xp_expenses') || '[]'); } catch { return []; }
  });
  const [budget, setBudgetState] = useState<number>(() => {
    return parseFloat(localStorage.getItem('xp_budget') || '0');
  });
  const [budgetHistory, setBudgetHistoryState] = useState<BudgetHistoryEntry[]>(() => {
    try { return JSON.parse(localStorage.getItem('xp_budget_history') || '[]'); } catch { return []; }
  });
  const [learnings, setLearningsState] = useState<CategoryLearning>(() => {
    try { return JSON.parse(localStorage.getItem('xp_learnings') || '{}'); } catch { return {}; }
  });

  useEffect(() => { localStorage.setItem('xp_expenses', JSON.stringify(expenses)); }, [expenses]);
  useEffect(() => { localStorage.setItem('xp_budget', String(budget)); }, [budget]);
  useEffect(() => { localStorage.setItem('xp_budget_history', JSON.stringify(budgetHistory)); }, [budgetHistory]);
  useEffect(() => { localStorage.setItem('xp_learnings', JSON.stringify(learnings)); }, [learnings]);

  const addExpense = useCallback((expense: Omit<Expense, 'id' | 'date'>) => {
    const newExpense: Expense = { ...expense, id: crypto.randomUUID(), date: new Date().toISOString() };
    setExpenses(prev => [newExpense, ...prev]);
  }, []);

  const deleteExpense = useCallback((id: string) => {
    setExpenses(prev => prev.filter(e => e.id !== id));
  }, []);

  const updateExpense = useCallback((updatedExpense: Expense) => {
    setExpenses(prev => prev.map(e => e.id === updatedExpense.id ? updatedExpense : e));
  }, []);

  const setBudget = useCallback((amount: number) => {
    setBudgetState(amount);
    // Record in history every time budget is set
    const entry: BudgetHistoryEntry = {
      id: crypto.randomUUID(),
      amount,
      setAt: new Date().toISOString(),
    };
    setBudgetHistoryState(prev => [entry, ...prev]);
  }, []);

  const setLearnings = useCallback((updated: CategoryLearning) => {
    setLearningsState(updated);
  }, []);

  return { expenses, budget, budgetHistory, learnings, addExpense, deleteExpense, updateExpense, setBudget, setLearnings };
}

export function RootLayout() {
  const location = useLocation();
  const { expenses, budget, budgetHistory, learnings, addExpense, deleteExpense, updateExpense, setBudget, setLearnings } = useExpenseState();
  const { theme } = useSettings();
  const p = createPalette(theme);

  const path = location.pathname;

  return (
    <div
      className="min-h-screen w-full flex items-center justify-center"
      style={{ background: p.bg }}
    >
      <div
        id="app-root"
        data-theme={theme}
        className="relative w-full flex flex-col overflow-hidden"
        style={{ maxWidth: 430, height: '100dvh', background: p.bg }}
      >
        <div className="flex-1 overflow-hidden relative z-10">
          {path === '/' && (
            <ExpensePage
              expenses={expenses}
              budget={budget}
              budgetHistory={budgetHistory}
              learnings={learnings}
              onAddExpense={addExpense}
              onDeleteExpense={deleteExpense}
              onUpdateExpense={updateExpense}
              onSetBudget={setBudget}
              onUpdateLearnings={setLearnings}
            />
          )}
          {path === '/news' && <NewsPage />}
          {path === '/tutor' && <TutorPage />}
          {path === '/cloud' && <CloudPage />}
        </div>

        <div className="relative z-10 shrink-0">
          <BottomNav />
        </div>

        {/* Global Settings Modal — rendered above everything */}
        <SettingsModal />
      </div>
    </div>
  );
}