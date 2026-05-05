import { useMemo, useState, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronRight, ChevronLeft, TrendingDown, TrendingUp, History } from 'lucide-react';
import { usePalette } from '../../utils/palette';
import {
  PieChart, Pie, Tooltip, ResponsiveContainer,
  BarChart, Bar, XAxis, YAxis,
} from 'recharts';
import type { Expense } from '../../types/expense';
import { CATEGORY_COLORS } from '../../types/expense';
import { formatDate, formatCurrency } from '../../utils/categoryUtils';
import { ExpenseItem } from './ExpenseItem';
import { ExpenseTrendModal } from './ExpenseTrendModal';

const ANALYSIS_PERIODS = ['This Month', 'Last Month', 'Last 3M', 'Last 6M', 'All Time'] as const;

interface TrackerTabProps {
  expenses: Expense[];
  budget: number;
  learnings: Record<string, string>;
  onDeleteExpense: (id: string) => void;
  onEditExpense: (expense: Expense) => void;
  onOpenBudget: () => void;
  onOpenHistory: () => void;
}

const font = "'Plus Jakarta Sans', sans-serif";

export function TrackerTab({ expenses, budget, onDeleteExpense, onEditExpense, onOpenBudget, onOpenHistory }: TrackerTabProps) {
  const p = usePalette();
  const [showTrend, setShowTrend] = useState(false);
  const [analysisPage, setAnalysisPage] = useState(0);
  const [analysisDir, setAnalysisDir] = useState<1 | -1>(1);
  const [visibleGroups, setVisibleGroups] = useState(7);
  const analysisTouchRef = useRef<{ startX: number; startY: number } | null>(null);

  const spent = useMemo(() => expenses.reduce((sum, e) => sum + e.amount, 0), [expenses]);
  const balance = budget > 0 ? budget - spent : -spent;
  const isOverBudget = budget > 0 && spent > budget;
  const budgetPct = budget > 0 ? Math.min(spent / budget, 1) : 0;

  // ── Card theme: green → amber → red (adapts to dark/white theme) ──
  const cardTheme = useMemo(() => {
    const isDark = p.isDark;
    if (!budget) return {
      gradient: isDark
        ? 'linear-gradient(135deg, #1A1035 0%, #261848 40%, #1A1035 100%)'
        : 'linear-gradient(135deg, #F5F3FF 0%, #EDE9FE 100%)',
      shadow: isDark ? '0 8px 36px rgba(124,58,237,0.28)' : '0 4px 20px rgba(124,58,237,0.12)',
      ringColor: '#7C3AED',
      ringTrack: 'rgba(124,58,237,0.15)',
      statusLabel: 'SET BUDGET',
      statusColor: isDark ? '#C4B5FD' : '#7C3AED',
      statusBg: 'rgba(124,58,237,0.18)',
    };
    if (isOverBudget) return {
      gradient: isDark
        ? 'linear-gradient(135deg, #3D0505 0%, #5C0D0D 45%, #3D0505 100%)'
        : 'linear-gradient(135deg, #FFF1F2 0%, #FFE4E6 100%)',
      shadow: isDark ? '0 8px 44px rgba(239,68,68,0.5)' : '0 4px 20px rgba(239,68,68,0.15)',
      ringColor: '#EF4444',
      ringTrack: 'rgba(239,68,68,0.15)',
      statusLabel: 'OVER BUDGET',
      statusColor: isDark ? '#FCA5A5' : '#DC2626',
      statusBg: 'rgba(239,68,68,0.15)',
    };
    if (budgetPct > 0.75) return {
      gradient: isDark
        ? 'linear-gradient(135deg, #2A1500 0%, #3E1E00 45%, #2A1500 100%)'
        : 'linear-gradient(135deg, #FFFBEB 0%, #FEF3C7 100%)',
      shadow: isDark ? '0 8px 36px rgba(245,158,11,0.3)' : '0 4px 20px rgba(245,158,11,0.15)',
      ringColor: '#F59E0B',
      ringTrack: 'rgba(245,158,11,0.15)',
      statusLabel: 'AT RISK',
      statusColor: isDark ? '#FCD34D' : '#D97706',
      statusBg: 'rgba(245,158,11,0.15)',
    };
    return {
      gradient: isDark
        ? 'linear-gradient(135deg, #022C1A 0%, #04402A 45%, #022C1A 100%)'
        : 'linear-gradient(135deg, #ECFDF5 0%, #D1FAE5 100%)',
      shadow: isDark ? '0 8px 36px rgba(34,197,94,0.22)' : '0 4px 20px rgba(34,197,94,0.15)',
      ringColor: '#22C55E',
      ringTrack: 'rgba(34,197,94,0.12)',
      statusLabel: 'ON TRACK',
      statusColor: isDark ? '#86EFAC' : '#16A34A',
      statusBg: 'rgba(34,197,94,0.15)',
    };
  }, [budget, isOverBudget, budgetPct, p.isDark]);

  // SVG ring geometry
  const ringR = 33;
  const ringCircum = 2 * Math.PI * ringR;
  const ringOffset = ringCircum * (1 - budgetPct);

  // ── Today & yesterday stats ──
  const { todayTotal, yesterdayTotal, todayData, yesterdayData } = useMemo(() => {
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const yStart = new Date(todayStart); yStart.setDate(todayStart.getDate() - 1);
    const yEnd = new Date(todayStart.getTime() - 1);

    const todayExp = expenses.filter(e => new Date(e.date) >= todayStart);
    const yExp = expenses.filter(e => { const d = new Date(e.date); return d >= yStart && d <= yEnd; });

    const buildBuckets = (exps: Expense[]) => {
      const map: Record<string, number> = {};
      exps.forEach(e => {
        const h = new Date(e.date).getHours();
        const b = `${Math.floor(h / 4) * 4}h`;
        map[b] = (map[b] || 0) + e.amount;
      });
      return [0, 4, 8, 12, 16, 20].map(h => ({ name: `${h}h`, amount: map[`${h}h`] || 0 }));
    };

    return {
      todayTotal: todayExp.reduce((s, e) => s + e.amount, 0),
      yesterdayTotal: yExp.reduce((s, e) => s + e.amount, 0),
      todayData: buildBuckets(todayExp),
      yesterdayData: buildBuckets(yExp),
    };
  }, [expenses]);

  // ── Swipeable analysis period filtering ──
  const analysisPeriodExpenses = useMemo(() => {
    const now = new Date();
    switch (analysisPage) {
      case 0: {
        const s = new Date(now.getFullYear(), now.getMonth(), 1);
        return expenses.filter(e => new Date(e.date) >= s);
      }
      case 1: {
        const s = new Date(now.getFullYear(), now.getMonth() - 1, 1);
        const end = new Date(now.getFullYear(), now.getMonth(), 0, 23, 59, 59);
        return expenses.filter(e => { const d = new Date(e.date); return d >= s && d <= end; });
      }
      case 2: {
        const s = new Date(now.getFullYear(), now.getMonth() - 2, 1);
        return expenses.filter(e => new Date(e.date) >= s);
      }
      case 3: {
        const s = new Date(now.getFullYear(), now.getMonth() - 5, 1);
        return expenses.filter(e => new Date(e.date) >= s);
      }
      default:
        return expenses;
    }
  }, [expenses, analysisPage]);

  const analysisSpent = useMemo(() =>
    analysisPeriodExpenses.reduce((s, e) => s + e.amount, 0),
    [analysisPeriodExpenses]);

  const analysisCategoryBreakdown = useMemo(() => {
    const map: Record<string, number> = {};
    for (const e of analysisPeriodExpenses) map[e.category] = (map[e.category] || 0) + e.amount;
    return Object.entries(map)
      .map(([cat, total]) => ({
        name: cat,
        cat, total,
        pct: analysisSpent > 0 ? (total / analysisSpent) * 100 : 0,
        fill: CATEGORY_COLORS[cat] || '#818CF8',
      }))
      .sort((a, b) => b.total - a.total)
      .slice(0, 5);
  }, [analysisPeriodExpenses, analysisSpent]);

  // ── Category breakdown for smart tip (all expenses) ──
  const categoryBreakdown = useMemo(() => {
    const map: Record<string, number> = {};
    for (const e of expenses) map[e.category] = (map[e.category] || 0) + e.amount;
    return Object.entries(map)
      .map(([cat, total]) => ({
        name: cat,
        cat, total,
        pct: spent > 0 ? (total / spent) * 100 : 0,
        fill: CATEGORY_COLORS[cat] || '#818CF8',
      }))
      .sort((a, b) => b.total - a.total)
      .slice(0, 5);
  }, [expenses, spent]);

  // ── Grouped expenses ──
  const groupedExpenses = useMemo(() => {
    const groups: Record<string, Expense[]> = {};
    for (const e of expenses) {
      const key = formatDate(e.date);
      if (!groups[key]) groups[key] = [];
      groups[key].push(e);
    }
    return Object.entries(groups);
  }, [expenses]);

  // ── Smart tip ──
  const smartTip = useMemo(() => {
    if (expenses.length === 0) return null;
    const top = categoryBreakdown[0];
    if (!top) return null;
    if (isOverBudget) return `⚠️ Over budget by ${formatCurrency(spent - budget)}. Review your ${top.cat} expenses.`;
    if (top.pct > 40) return `${top.cat} takes up ${Math.round(top.pct)}% of your spending. Consider a sub-limit.`;
    if (budget > 0 && budgetPct > 0.7) return `You've used ${Math.round(budgetPct * 100)}% of your budget. Slow down on ${top.cat}!`;
    return `Top category: ${top.cat} at ${formatCurrency(top.total)}. You're doing well! 🎉`;
  }, [categoryBreakdown, expenses, isOverBudget, spent, budget, budgetPct]);

  // ── Analysis swipe gesture ──
  const handleAnalysisTouchStart = (e: React.TouchEvent) => {
    analysisTouchRef.current = { startX: e.touches[0].clientX, startY: e.touches[0].clientY };
  };
  const handleAnalysisTouchEnd = (e: React.TouchEvent) => {
    if (!analysisTouchRef.current) return;
    const dx = e.changedTouches[0].clientX - analysisTouchRef.current.startX;
    const dy = e.changedTouches[0].clientY - analysisTouchRef.current.startY;
    analysisTouchRef.current = null;
    if (Math.abs(dx) < 42 || Math.abs(dy) > Math.abs(dx)) return;
    const dir: 1 | -1 = dx < 0 ? 1 : -1;
    const next = analysisPage + dir;
    if (next < 0 || next >= ANALYSIS_PERIODS.length) return;
    setAnalysisDir(dir);
    setAnalysisPage(next);
  };

  const changePage = (dir: 1 | -1) => {
    const next = analysisPage + dir;
    if (next < 0 || next >= ANALYSIS_PERIODS.length) return;
    setAnalysisDir(dir);
    setAnalysisPage(next);
  };

  return (
    <div className="flex flex-col pb-32">

      {/* ══ TOTAL BALANCE CARD ══ */}
      <motion.div
        key={`card-${isOverBudget}-${budgetPct > 0.75}`}
        initial={{ opacity: 0, y: 12 }}
        animate={{
          opacity: 1,
          y: 0,
          boxShadow: isOverBudget
            ? ['0 8px 44px rgba(239,68,68,0.35)', '0 8px 64px rgba(239,68,68,0.65)', '0 8px 44px rgba(239,68,68,0.35)']
            : cardTheme.shadow,
        }}
        transition={{
          opacity: { duration: 0.4 },
          y: { duration: 0.4 },
          boxShadow: isOverBudget
            ? { duration: 1.8, repeat: Infinity, ease: 'easeInOut' }
            : { duration: 0.6 },
        }}
        className="mx-4 mt-4 rounded-2xl px-5 pt-4 pb-5 overflow-hidden"
        style={{ background: cardTheme.gradient }}
      >
        {/* Row 1: label + status chip */}
        <div className="flex items-center justify-between mb-3">
          <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.45)', fontFamily: font, letterSpacing: 2, fontWeight: 700 }}>
            TOTAL BALANCE
          </span>
          <motion.div
            key={cardTheme.statusLabel}
            initial={{ scale: 0.8, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            className="flex items-center gap-1.5 rounded-full px-2.5 py-1"
            style={{ background: cardTheme.statusBg, border: `1px solid ${cardTheme.ringColor}40` }}
          >
            <motion.span
              animate={isOverBudget ? { scale: [1, 1.4, 1], opacity: [1, 0.6, 1] } : {}}
              transition={isOverBudget ? { duration: 1.2, repeat: Infinity } : {}}
              style={{
                width: 6, height: 6, borderRadius: '50%',
                background: cardTheme.ringColor,
                display: 'inline-block',
              }}
            />
            <span style={{ fontSize: 9, fontWeight: 800, color: cardTheme.statusColor, fontFamily: font, letterSpacing: 0.8 }}>
              {cardTheme.statusLabel}
            </span>
          </motion.div>
        </div>

        {/* Row 2: balance + SVG ring */}
        <div className="flex items-center justify-between">
          <div>
            <motion.p
              key={balance}
              initial={{ y: 8, opacity: 0 }}
              animate={{ y: 0, opacity: 1 }}
              transition={{ duration: 0.35 }}
              style={{
                fontSize: 34, fontWeight: 800, color: '#fff',
                fontFamily: font, letterSpacing: '-1px', lineHeight: 1,
              }}
            >
              {balance < 0 ? '−' : ''}{formatCurrency(Math.abs(balance))}
            </motion.p>
            <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.4)', fontFamily: font, marginTop: 5 }}>
              {budget > 0 ? 'available balance' : 'total spent · no budget set'}
            </p>
          </div>

          {/* SVG Donut Ring */}
          <div style={{ position: 'relative', width: 84, height: 84, flexShrink: 0 }}>
            <svg width={84} height={84} viewBox="0 0 84 84">
              {/* Glow filter */}
              <defs>
                <filter id="ring-glow">
                  <feGaussianBlur stdDeviation="2" result="blur" />
                  <feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
                </filter>
              </defs>
              {/* Track */}
              <circle cx={42} cy={42} r={ringR} fill="none" stroke={cardTheme.ringTrack} strokeWidth={7} />
              {/* Progress arc */}
              <motion.circle
                cx={42} cy={42} r={ringR}
                fill="none"
                stroke={cardTheme.ringColor}
                strokeWidth={7}
                strokeLinecap="round"
                strokeDasharray={ringCircum}
                initial={{ strokeDashoffset: ringCircum }}
                animate={{ strokeDashoffset: ringOffset }}
                transition={{ duration: 1.3, ease: 'easeOut' }}
                style={{ transform: 'rotate(-90deg)', transformOrigin: '50% 50%' }}
                filter="url(#ring-glow)"
              />
            </svg>
            <div style={{
              position: 'absolute', inset: 0,
              display: 'flex', flexDirection: 'column',
              alignItems: 'center', justifyContent: 'center',
            }}>
              <motion.span
                key={Math.round(budgetPct * 100)}
                initial={{ scale: 0.75, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                style={{ fontSize: 17, fontWeight: 800, color: cardTheme.ringColor, fontFamily: font, lineHeight: 1 }}
              >
                {budget > 0 ? `${Math.round(budgetPct * 100)}%` : '—'}
              </motion.span>
              <span style={{ fontSize: 8, color: 'rgba(255,255,255,0.35)', fontFamily: font, letterSpacing: 1, marginTop: 2 }}>
                {budget > 0 ? 'USED' : 'NO LIMIT'}
              </span>
            </div>
          </div>
        </div>

        {/* Divider */}
        <div style={{ height: 1, background: 'rgba(255,255,255,0.08)', margin: '14px 0 12px' }} />

        {/* Row 3: Budget / Spent / Remaining */}
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-4">
            <div>
              <p style={{ fontSize: 9, color: 'rgba(255,255,255,0.38)', fontFamily: font, letterSpacing: 1.2, marginBottom: 2 }}>
                BUDGET
              </p>
              <p style={{ fontSize: 14, fontWeight: 700, color: '#6EE7B7', fontFamily: font }}>
                {budget > 0 ? `+${formatCurrency(budget)}` : '—'}
              </p>
            </div>
            <div style={{ width: 1, height: 28, background: 'rgba(255,255,255,0.1)' }} />
            <div>
              <p style={{ fontSize: 9, color: 'rgba(255,255,255,0.38)', fontFamily: font, letterSpacing: 1.2, marginBottom: 2 }}>
                SPENT
              </p>
              <p style={{ fontSize: 14, fontWeight: 700, color: '#FCA5A5', fontFamily: font }}>
                -{formatCurrency(spent)}
              </p>
            </div>
          </div>
          {budget > 0 && (
            <div style={{ textAlign: 'right' }}>
              <p style={{ fontSize: 9, color: 'rgba(255,255,255,0.38)', fontFamily: font, letterSpacing: 1.2, marginBottom: 2 }}>
                LEFT
              </p>
              <p style={{ fontSize: 14, fontWeight: 700, fontFamily: font, color: isOverBudget ? '#FCA5A5' : '#6EE7B7' }}>
                {isOverBudget ? `−${formatCurrency(spent - budget)}` : formatCurrency(budget - spent)}
              </p>
            </div>
          )}
        </div>

        {/* Progress bar */}
        {budget > 0 && (
          <div style={{ marginTop: 12, height: 4, borderRadius: 4, background: 'rgba(255,255,255,0.07)', overflow: 'hidden' }}>
            <motion.div
              initial={{ width: 0 }}
              animate={{ width: `${Math.min(budgetPct * 100, 100)}%` }}
              transition={{ duration: 1.3, ease: 'easeOut' }}
              style={{
                height: '100%', borderRadius: 4,
                background: `linear-gradient(90deg, ${cardTheme.ringColor}80, ${cardTheme.ringColor})`,
              }}
            />
          </div>
        )}

        {/* ── Action buttons: Set Budget + History ── */}
        <div
          className="flex items-center gap-2 mt-3"
          style={{ borderTop: '1px solid rgba(255,255,255,0.07)', paddingTop: 12 }}
        >
          <motion.button
            whileTap={{ scale: 0.95 }}
            onClick={onOpenBudget}
            className="flex-1 flex items-center justify-center gap-1.5 rounded-xl py-2.5"
            style={{
              background: 'rgba(255,255,255,0.09)',
              border: '1px solid rgba(255,255,255,0.14)',
            }}
          >
            <span style={{ fontSize: 13 }}>💰</span>
            <span style={{ fontSize: 12, fontWeight: 700, color: 'rgba(255,255,255,0.8)', fontFamily: font }}>
              {budget > 0 ? 'Change Budget' : 'Set Budget'}
            </span>
          </motion.button>

          <motion.button
            whileTap={{ scale: 0.92 }}
            onClick={onOpenHistory}
            className="flex items-center justify-center gap-1.5 rounded-xl py-2.5 px-3.5"
            style={{
              background: 'rgba(99,102,241,0.15)',
              border: '1px solid rgba(99,102,241,0.3)',
            }}
          >
            <History size={14} color="#818CF8" />
            <span style={{ fontSize: 12, fontWeight: 700, color: '#818CF8', fontFamily: font }}>
              History
            </span>
          </motion.button>
        </div>
      </motion.div>

      {/* ══ SPENDING ANALYSIS (swipeable) ══ */}
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.08 }}
        className="mx-4 mt-4 rounded-2xl px-4 pt-4 pb-4"
        style={{
          background: 'rgba(255,255,255,0.03)',
          border: '1px solid rgba(255,255,255,0.08)',
          overflow: 'hidden',
        }}
        onTouchStart={handleAnalysisTouchStart}
        onTouchEnd={handleAnalysisTouchEnd}
      >
        {/* Header row */}
        <div className="flex items-center justify-between mb-3">
          <span style={{ fontSize: 16, fontWeight: 700, color: '#fff', fontFamily: font }}>
            Spending Analysis
          </span>

          {/* Period navigator */}
          <div className="flex items-center gap-1">
            <motion.button
              whileTap={{ scale: 0.82 }}
              onClick={() => changePage(-1)}
              style={{
                opacity: analysisPage > 0 ? 1 : 0.2,
                background: 'none', border: 'none', padding: 2, cursor: analysisPage > 0 ? 'pointer' : 'default',
              }}
            >
              <ChevronLeft size={15} color="#818CF8" />
            </motion.button>

            <AnimatePresence mode="wait" initial={false}>
              <motion.span
                key={analysisPage}
                initial={{ opacity: 0, y: analysisDir > 0 ? 7 : -7 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: analysisDir > 0 ? -7 : 7 }}
                transition={{ duration: 0.16 }}
                className="rounded-full px-2.5 py-1"
                style={{
                  fontSize: 10, fontWeight: 700, color: '#818CF8',
                  background: 'rgba(99,102,241,0.15)',
                  border: '1px solid rgba(99,102,241,0.28)',
                  fontFamily: font, whiteSpace: 'nowrap',
                  minWidth: 72, textAlign: 'center',
                  display: 'inline-block',
                }}
              >
                {ANALYSIS_PERIODS[analysisPage]}
              </motion.span>
            </AnimatePresence>

            <motion.button
              whileTap={{ scale: 0.82 }}
              onClick={() => changePage(1)}
              style={{
                opacity: analysisPage < ANALYSIS_PERIODS.length - 1 ? 1 : 0.2,
                background: 'none', border: 'none', padding: 2,
                cursor: analysisPage < ANALYSIS_PERIODS.length - 1 ? 'pointer' : 'default',
              }}
            >
              <ChevronRight size={15} color="#818CF8" />
            </motion.button>
          </div>
        </div>

        {/* Swipeable chart content */}
        <AnimatePresence mode="wait" initial={false}>
          <motion.div
            key={analysisPage}
            initial={{ x: analysisDir > 0 ? 55 : -55, opacity: 0 }}
            animate={{ x: 0, opacity: 1 }}
            exit={{ x: analysisDir > 0 ? -55 : 55, opacity: 0 }}
            transition={{ duration: 0.22, ease: 'easeOut' }}
          >
            {analysisPeriodExpenses.length === 0 ? (
              <div className="flex flex-col items-center justify-center py-8">
                <span style={{ fontSize: 40, marginBottom: 10 }}>📊</span>
                <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.35)', fontFamily: font }}>
                  No expenses for {ANALYSIS_PERIODS[analysisPage].toLowerCase()}
                </p>
                <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.2)', fontFamily: font, marginTop: 4 }}>
                  Swipe to browse other periods
                </p>
              </div>
            ) : (
              <>
                {/* Donut chart */}
                <div style={{ position: 'relative', height: 180 }}>
                  <ResponsiveContainer width="100%" height={180}>
                    <PieChart>
                      <Pie
                        data={analysisCategoryBreakdown}
                        cx="50%"
                        cy="50%"
                        innerRadius={58}
                        outerRadius={82}
                        dataKey="total"
                        strokeWidth={2}
                        stroke="transparent"
                        paddingAngle={3}
                      />
                      <Tooltip
                        contentStyle={{ background: '#0d0d1a', border: '1px solid rgba(99,102,241,0.3)', borderRadius: 10, fontSize: 12, fontFamily: font }}
                        formatter={(v: number) => [formatCurrency(v)]}
                        itemStyle={{ color: '#fff' }}
                      />
                    </PieChart>
                  </ResponsiveContainer>
                  <div className="absolute inset-0 flex flex-col items-center justify-center pointer-events-none">
                    <p style={{ fontSize: 20, fontWeight: 800, color: '#fff', fontFamily: font, lineHeight: 1 }}>
                      {formatCurrency(analysisSpent)}
                    </p>
                    <p style={{ fontSize: 9, color: 'rgba(255,255,255,0.4)', letterSpacing: 1.5, fontFamily: font, marginTop: 3 }}>
                      TOTAL SPENT
                    </p>
                  </div>
                </div>

                {/* Legend */}
                <div className="grid grid-cols-2 gap-x-4 gap-y-2.5 mt-1">
                  {analysisCategoryBreakdown.map(item => (
                    <div key={item.cat} className="flex items-center gap-2">
                      <div className="w-2 h-2 rounded-full shrink-0" style={{ background: item.fill, boxShadow: `0 0 5px ${item.fill}80` }} />
                      <div className="min-w-0">
                        <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.7)', fontFamily: font }}>{item.cat} </span>
                        <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.35)', fontFamily: font }}>
                          {formatCurrency(item.total)} ({Math.round(item.pct)}%)
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              </>
            )}
          </motion.div>
        </AnimatePresence>

        {/* Page dots */}
        <div className="flex items-center justify-center gap-1.5 mt-4">
          {ANALYSIS_PERIODS.map((_, i) => (
            <motion.button
              key={i}
              onClick={() => { setAnalysisDir(i > analysisPage ? 1 : -1); setAnalysisPage(i); }}
              animate={{
                width: i === analysisPage ? 18 : 5,
                background: i === analysisPage ? '#818CF8' : 'rgba(255,255,255,0.18)',
              }}
              style={{ height: 5, borderRadius: 5, border: 'none', padding: 0, cursor: 'pointer' }}
            />
          ))}
        </div>
      </motion.div>

      {/* ══ EXPENSE TREND ══ */}
      <motion.div
        initial={{ opacity: 0, y: 12 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ delay: 0.12 }}
        className="mx-4 mt-4"
      >
        <div className="flex items-center justify-between mb-3">
          <span style={{ fontSize: 16, fontWeight: 700, color: '#fff', fontFamily: font }}>
            Expense Trend
          </span>
          <motion.button
            whileTap={{ scale: 0.92 }}
            onClick={() => setShowTrend(true)}
            className="flex items-center gap-0.5"
            style={{ fontSize: 13, fontWeight: 600, color: '#818CF8', fontFamily: font, background: 'none', border: 'none', cursor: 'pointer', padding: 0 }}
          >
            Details <ChevronRight size={14} color="#818CF8" />
          </motion.button>
        </div>

        <div className="grid grid-cols-2 gap-3">
          {/* Today */}
          <div className="rounded-2xl px-4 py-4" style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.07)' }}>
            <div className="flex items-center justify-between mb-2">
              <span style={{ fontSize: 12, color: 'rgba(255,255,255,0.5)', fontFamily: font }}>Today</span>
              <TrendingDown size={14} color={todayTotal > yesterdayTotal ? '#EF4444' : '#34D399'} />
            </div>
            <div style={{ height: 50, marginBottom: 8 }}>
              <ResponsiveContainer width="100%" height={50}>
                <BarChart data={todayData} margin={{ top: 0, right: 0, bottom: 0, left: 0 }}>
                  <Bar dataKey="amount" radius={3} fill="rgba(124,58,237,0.75)" />
                  <XAxis dataKey="name" hide />
                  <YAxis hide />
                </BarChart>
              </ResponsiveContainer>
            </div>
            <p style={{ fontSize: 16, fontWeight: 700, color: '#fff', fontFamily: font }}>
              {formatCurrency(todayTotal)}
            </p>
          </div>

          {/* Yesterday */}
          <div className="rounded-2xl px-4 py-4" style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.07)' }}>
            <div className="flex items-center justify-between mb-2">
              <span style={{ fontSize: 12, color: 'rgba(255,255,255,0.5)', fontFamily: font }}>Yesterday</span>
              <TrendingUp size={14} color="rgba(255,255,255,0.3)" />
            </div>
            <div style={{ height: 50, marginBottom: 8 }}>
              <ResponsiveContainer width="100%" height={50}>
                <BarChart data={yesterdayData} margin={{ top: 0, right: 0, bottom: 0, left: 0 }}>
                  <Bar dataKey="amount" radius={3} fill="rgba(99,102,241,0.6)" />
                  <XAxis dataKey="name" hide />
                  <YAxis hide />
                </BarChart>
              </ResponsiveContainer>
            </div>
            <p style={{ fontSize: 16, fontWeight: 700, color: 'rgba(255,255,255,0.6)', fontFamily: font }}>
              {formatCurrency(yesterdayTotal)}
            </p>
          </div>
        </div>
      </motion.div>

      {/* ══ SMART TIP ══ */}
      {smartTip && (
        <motion.div
          initial={{ opacity: 0, y: 12 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ delay: 0.16 }}
          className="mx-4 mt-4 rounded-2xl px-4 py-4 flex items-start gap-3"
          style={{
            background: 'rgba(71,37,244,0.1)',
            border: '1px solid rgba(71,37,244,0.28)',
            borderLeft: '3px solid #7C3AED',
          }}
        >
          <div className="shrink-0 rounded-xl p-2 mt-0.5" style={{ background: 'rgba(124,58,237,0.18)', border: '1px solid rgba(124,58,237,0.28)' }}>
            <span style={{ fontSize: 14 }}>✨</span>
          </div>
          <div>
            <p style={{ fontSize: 11, fontWeight: 700, color: 'rgba(255,255,255,0.6)', fontFamily: font, marginBottom: 3, letterSpacing: 0.5 }}>
              SMART TIP
            </p>
            <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.5)', fontFamily: font, lineHeight: 1.55 }}>
              {smartTip}
            </p>
          </div>
        </motion.div>
      )}

      {/* ══ RECENT TRANSACTIONS ══ */}
      <div className="mx-4 mt-5">
        <div className="flex items-center justify-between mb-1">
          <p style={{ fontSize: 14, fontWeight: 700, color: p.text2, fontFamily: font, letterSpacing: 0.3 }}>
            Recent Transactions
          </p>
          {expenses.length > 0 && (
            <div className="flex items-center gap-1 rounded-md px-2 py-1" style={{ background: 'rgba(255,255,255,0.05)' }}>
              <span style={{ fontSize: 9, color: 'rgba(255,255,255,0.3)', fontFamily: font }}>←</span>
              <span style={{ fontSize: 9, color: 'rgba(255,255,255,0.3)', fontFamily: font }}>swipe to edit/delete</span>
            </div>
          )}
        </div>

        {expenses.length === 0 ? (
          <motion.div
            initial={{ opacity: 0, y: 10 }}
            animate={{ opacity: 1, y: 0 }}
            className="flex flex-col items-center justify-center py-12"
          >
            <div className="text-5xl mb-4">💸</div>
            <p style={{ fontSize: 15, fontWeight: 600, color: 'rgba(255,255,255,0.4)', fontFamily: font }}>
              No expenses yet
            </p>
            <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.2)', marginTop: 6, fontFamily: font }}>
              Tap + to add your first expense
            </p>
          </motion.div>
        ) : (
          <>
            <AnimatePresence>
              {groupedExpenses.slice(0, visibleGroups).map(([dateLabel, items]) => (
                <motion.div key={dateLabel} className="mb-4 mt-3">
                  <div className="flex items-center gap-3 mb-2 px-1">
                    <p style={{ fontSize: 11, fontWeight: 700, color: p.text3, letterSpacing: 1.2, fontFamily: font }}>
                      {dateLabel.toUpperCase()}
                    </p>
                    <div className="flex-1 h-px" style={{ background: p.border }} />
                    <p style={{ fontSize: 11, fontWeight: 600, color: p.text4, fontFamily: font }}>
                      {formatCurrency(items.reduce((s, e) => s + e.amount, 0))}
                    </p>
                  </div>
                  <div className="flex flex-col gap-2">
                    <AnimatePresence>
                      {items.map((expense, i) => (
                        <ExpenseItem
                          key={expense.id}
                          expense={expense}
                          onDelete={onDeleteExpense}
                          onEdit={onEditExpense}
                          index={i}
                        />
                      ))}
                    </AnimatePresence>
                  </div>
                </motion.div>
              ))}
            </AnimatePresence>

            {/* ── Pagination footer ── */}
            {groupedExpenses.length > visibleGroups ? (
              <motion.div className="mt-2 mb-4">
                {/* Progress bar */}
                <div className="flex items-center gap-2 mb-3 px-1">
                  <div className="flex-1 rounded-full overflow-hidden" style={{ height: 3, background: 'rgba(255,255,255,0.07)' }}>
                    <motion.div
                      initial={{ width: 0 }}
                      animate={{ width: `${(visibleGroups / groupedExpenses.length) * 100}%` }}
                      transition={{ duration: 0.4, ease: 'easeOut' }}
                      style={{ height: '100%', borderRadius: 99, background: 'linear-gradient(90deg, #7C3AED, #A78BFA)' }}
                    />
                  </div>
                  <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.28)', fontFamily: font, whiteSpace: 'nowrap' }}>
                    {Math.min(visibleGroups, groupedExpenses.length)} of {groupedExpenses.length} days
                  </span>
                </div>
                {/* Load more button */}
                <motion.button
                  whileTap={{ scale: 0.96 }}
                  onClick={() => setVisibleGroups(v => v + 7)}
                  className="w-full flex items-center justify-center gap-2 rounded-2xl py-3.5"
                  style={{ background: 'rgba(124,58,237,0.1)', border: '1px solid rgba(124,58,237,0.25)' }}>
                  <span style={{ fontSize: 13, fontWeight: 700, color: '#A78BFA', fontFamily: font }}>
                    Load {Math.min(7, groupedExpenses.length - visibleGroups)} more days
                  </span>
                  <ChevronRight size={14} color="#A78BFA" style={{ transform: 'rotate(90deg)' }} />
                </motion.button>
              </motion.div>
            ) : groupedExpenses.length > 7 ? (
              /* All loaded — show summary */
              <motion.div initial={{ opacity: 0 }} animate={{ opacity: 1 }}
                className="flex items-center justify-center gap-2 mt-2 mb-4 py-3 rounded-2xl"
                style={{ background: 'rgba(52,211,153,0.05)', border: '1px solid rgba(52,211,153,0.15)' }}>
                <span style={{ fontSize: 12 }}>✅</span>
                <span style={{ fontSize: 12, color: 'rgba(52,211,153,0.7)', fontFamily: font }}>
                  All {expenses.length} transactions loaded
                </span>
                <motion.button whileTap={{ scale: 0.9 }} onClick={() => setVisibleGroups(7)}
                  style={{ background: 'none', border: 'none', cursor: 'pointer', padding: 0, marginLeft: 4 }}>
                  <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.25)', fontFamily: font }}>Collapse</span>
                </motion.button>
              </motion.div>
            ) : null}
          </>
        )}
      </div>

      <ExpenseTrendModal
        open={showTrend}
        onClose={() => setShowTrend(false)}
        expenses={expenses}
        budget={budget}
      />
    </div>
  );
}