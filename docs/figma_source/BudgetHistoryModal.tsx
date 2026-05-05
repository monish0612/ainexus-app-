import { useMemo } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, TrendingUp, TrendingDown } from 'lucide-react';
import {
  AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts';
import type { Expense, BudgetHistoryEntry } from '../../types/expense';
import { formatCurrency } from '../../utils/categoryUtils';

interface BudgetHistoryModalProps {
  open: boolean;
  onClose: () => void;
  budgetHistory: BudgetHistoryEntry[];
  expenses: Expense[];
  currentBudget: number;
}

type StatusKey = 'healthy' | 'warning' | 'danger' | 'drained' | 'empty';

const STATUS: Record<StatusKey, {
  color: string; dimBg: string; border: string; label: string; leftBorder: string;
}> = {
  healthy: { color: '#22C55E', dimBg: 'rgba(34,197,94,0.08)', border: 'rgba(34,197,94,0.2)', label: 'ON TRACK', leftBorder: '#22C55E' },
  warning: { color: '#F59E0B', dimBg: 'rgba(245,158,11,0.09)', border: 'rgba(245,158,11,0.25)', label: 'AT RISK', leftBorder: '#F59E0B' },
  danger: { color: '#F97316', dimBg: 'rgba(249,115,22,0.09)', border: 'rgba(249,115,22,0.25)', label: 'HIGH USAGE', leftBorder: '#F97316' },
  drained: { color: '#EF4444', dimBg: 'rgba(239,68,68,0.1)', border: 'rgba(239,68,68,0.3)', label: 'DRAINED 🔥', leftBorder: '#EF4444' },
  empty: { color: '#6366F1', dimBg: 'rgba(99,102,241,0.07)', border: 'rgba(99,102,241,0.18)', label: 'NO DATA', leftBorder: '#6366F1' },
};

const font = "'Plus Jakarta Sans', sans-serif";

// Custom bar shape for per-item colors in the bar chart
function CustomBarShape(props: Record<string, unknown>) {
  const x = props.x as number;
  const y = props.y as number;
  const width = props.width as number;
  const height = props.height as number;
  const fill = props.fill as string;
  if (!height || height <= 0) return null;
  return <rect x={x} y={y} width={width} height={Math.max(0, height)} fill={fill || '#6366F1'} rx={3} ry={3} />;
}

export function BudgetHistoryModal({ open, onClose, budgetHistory, expenses, currentBudget }: BudgetHistoryModalProps) {

  const { monthlyPerf, changes, trendData, stats, spendingChart } = useMemo(() => {
    const now = new Date();
    const currentMonthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

    // Collect all months that have expense data
    const monthSet = new Set<string>();
    expenses.forEach(e => {
      const d = new Date(e.date);
      monthSet.add(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`);
    });
    if (currentBudget > 0) monthSet.add(currentMonthKey);

    const months = Array.from(monthSet).sort((a, b) => b.localeCompare(a)); // newest first

    // Sort budget history newest → oldest
    const sorted = [...budgetHistory].sort((a, b) =>
      new Date(b.setAt).getTime() - new Date(a.setAt).getTime()
    );

    // Get the applicable budget for a given month key
    const getBudget = (monthKey: string): number => {
      const [y, m] = monthKey.split('-').map(Number);
      const endOfMonth = new Date(y, m, 0, 23, 59, 59);
      const entry = sorted.find(h => new Date(h.setAt) <= endOfMonth);
      return entry?.amount ?? (currentBudget > 0 ? currentBudget : 0);
    };

    // Sum spending for a month
    const getSpent = (monthKey: string): number => {
      const [y, m] = monthKey.split('-').map(Number);
      const start = new Date(y, m - 1, 1);
      const end = new Date(y, m, 0, 23, 59, 59);
      return expenses
        .filter(e => { const d = new Date(e.date); return d >= start && d <= end; })
        .reduce((sum, e) => sum + e.amount, 0);
    };

    // e.g. "Mar '25"
    const fmtMonth = (key: string) => {
      const [y, m] = key.split('-').map(Number);
      const name = new Date(y, m - 1, 1).toLocaleString('en', { month: 'short' });
      return `${name} '${String(y).slice(2)}`;
    };

    // ── Monthly performance ──
    const monthlyPerf = months.map(month => {
      const budget = getBudget(month);
      const spent = getSpent(month);
      const pct = budget > 0 ? spent / budget : 0;
      let status: StatusKey;
      if (budget === 0) status = 'empty';
      else if (pct >= 1) status = 'drained';
      else if (pct > 0.85) status = 'danger';
      else if (pct > 0.6) status = 'warning';
      else status = 'healthy';

      return {
        month, label: fmtMonth(month),
        budget, spent,
        pct: Math.min(pct, 1),
        rawPct: pct,
        status,
        isCurrent: month === currentMonthKey,
        overspent: pct >= 1 ? spent - budget : 0,
      };
    });

    // ── Budget change timeline ──
    const changes = sorted.map((entry, i) => {
      const prev = sorted[i + 1];
      const delta = prev ? entry.amount - prev.amount : null;
      const deltaPct = prev ? Math.round(((entry.amount - prev.amount) / prev.amount) * 100) : null;
      return {
        ...entry,
        delta,
        deltaPct,
        isFirst: !prev,
        displayDate: new Date(entry.setAt).toLocaleDateString('en-IN', {
          day: 'numeric', month: 'short', year: '2-digit',
        }),
      };
    });

    // ── Area chart: budget evolution (oldest first, max 10 entries) ──
    const trendData = sorted.slice(0, 10).reverse().map((entry, i) => ({
      name: `__${i}`, // unique key using index
      label: new Date(entry.setAt).toLocaleDateString('en', { month: 'short', day: 'numeric' }),
      amount: entry.amount,
    }));

    // ── Bar chart: last 6 months spending vs budget ──
    const spendingChart = months.slice(0, 6).reverse().map(month => {
      const budget = getBudget(month);
      const spent = getSpent(month);
      const pct = budget > 0 ? spent / budget : 0;
      let fill: string;
      if (pct >= 1) fill = '#EF4444';
      else if (pct > 0.85) fill = '#F97316';
      else if (pct > 0.6) fill = '#F59E0B';
      else fill = '#22C55E';
      return { name: fmtMonth(month), budget, spent, fill };
    });

    // ── Summary stats ──
    const valid = monthlyPerf.filter(m => m.budget > 0);
    const drained = valid.filter(m => m.status === 'drained');
    const avgBudget = valid.length > 0
      ? Math.round(valid.reduce((s, m) => s + m.budget, 0) / valid.length)
      : 0;

    return {
      monthlyPerf,
      changes,
      trendData,
      spendingChart,
      stats: {
        totalMonths: valid.length,
        drainedCount: drained.length,
        avgBudget,
      },
    };
  }, [budgetHistory, expenses, currentBudget]);

  const hasData = budgetHistory.length > 0;

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-50 flex flex-col"
          style={{ background: '#000' }}
          initial={{ y: '100%' }}
          animate={{ y: 0 }}
          exit={{ y: '100%' }}
          transition={{ type: 'spring', damping: 32, stiffness: 300 }}
        >
          {/* ── Header ── */}
          <div
            className="shrink-0 flex items-center justify-between px-4"
            style={{ height: 56, borderBottom: '1px solid rgba(255,255,255,0.08)', background: '#000' }}
          >
            <div style={{ width: 36 }} />
            <div className="text-center">
              <p style={{ fontSize: 16, fontWeight: 800, color: '#fff', fontFamily: font, letterSpacing: '-0.2px' }}>
                Budget History
              </p>
              <p style={{ fontSize: 9, color: 'rgba(255,255,255,0.32)', fontFamily: font, letterSpacing: 1.2 }}>
                MONTHLY OVERVIEW
              </p>
            </div>
            <motion.button
              whileTap={{ scale: 0.85 }}
              onClick={onClose}
              className="flex items-center justify-center rounded-full"
              style={{ width: 36, height: 36, background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.1)' }}
            >
              <X size={18} color="rgba(255,255,255,0.7)" />
            </motion.button>
          </div>

          {/* ── Scrollable Content ── */}
          <div className="flex-1 overflow-y-auto pb-12">

            {!hasData ? (
              /* Empty state */
              <motion.div
                className="flex flex-col items-center justify-center py-24 px-8"
                initial={{ opacity: 0, y: 24 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.12 }}
              >
                <motion.div
                  animate={{ y: [0, -8, 0] }}
                  transition={{ duration: 2.5, repeat: Infinity, ease: 'easeInOut' }}
                >
                  <div
                    className="flex items-center justify-center rounded-3xl mb-6"
                    style={{
                      width: 96, height: 96,
                      background: 'linear-gradient(135deg, rgba(124,58,237,0.2), rgba(99,102,241,0.1))',
                      border: '1px solid rgba(124,58,237,0.3)',
                      fontSize: 44,
                    }}
                  >
                    📅
                  </div>
                </motion.div>
                <p style={{ fontSize: 18, fontWeight: 800, color: 'rgba(255,255,255,0.65)', fontFamily: font, textAlign: 'center' }}>
                  No Budget History Yet
                </p>
                <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.3)', fontFamily: font, textAlign: 'center', marginTop: 10, lineHeight: 1.7 }}>
                  Every time you set or update your budget,{'\n'}it gets recorded here automatically.
                </p>
                <div
                  className="mt-6 rounded-2xl px-5 py-3 flex items-center gap-2"
                  style={{ background: 'rgba(124,58,237,0.12)', border: '1px solid rgba(124,58,237,0.28)' }}
                >
                  <span>💰</span>
                  <span style={{ fontSize: 12, fontWeight: 600, color: '#C4B5FD', fontFamily: font }}>
                    Tap "Set Budget" on the balance card to start
                  </span>
                </div>
              </motion.div>

            ) : (
              <>

                {/* ── Summary Stats ── */}
                <motion.div
                  initial={{ opacity: 0, y: 14 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.06 }}
                  className="grid grid-cols-3 gap-2 mx-4 mt-4"
                >
                  {[
                    { label: 'MONTHS', value: stats.totalMonths, icon: '📅', color: '#818CF8' },
                    { label: 'AVG BUDGET', value: formatCurrency(stats.avgBudget), icon: '💰', color: '#34D399' },
                    {
                      label: 'DRAINED',
                      value: stats.drainedCount,
                      icon: stats.drainedCount > 0 ? '🔥' : '✅',
                      color: stats.drainedCount > 0 ? '#EF4444' : '#22C55E',
                    },
                  ].map(({ label, value, icon, color }) => (
                    <motion.div
                      key={label}
                      initial={{ scale: 0.85, opacity: 0 }}
                      animate={{ scale: 1, opacity: 1 }}
                      transition={{ delay: 0.1 }}
                      className="rounded-2xl p-3 flex flex-col items-center"
                      style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}
                    >
                      <span style={{ fontSize: 22, marginBottom: 4 }}>{icon}</span>
                      <p style={{ fontSize: 15, fontWeight: 800, color, fontFamily: font, lineHeight: 1 }}>{value}</p>
                      <p style={{ fontSize: 8, color: 'rgba(255,255,255,0.3)', fontFamily: font, letterSpacing: 1, marginTop: 3 }}>{label}</p>
                    </motion.div>
                  ))}
                </motion.div>

                {/* ── Budget Evolution Chart ── */}
                {trendData.length >= 2 && (
                  <motion.div
                    initial={{ opacity: 0, y: 14 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.1 }}
                    className="mx-4 mt-4 rounded-2xl p-4"
                    style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.07)' }}
                  >
                    <div className="flex items-center justify-between mb-3">
                      <p style={{ fontSize: 13, fontWeight: 700, color: 'rgba(255,255,255,0.6)', fontFamily: font }}>
                        Budget Evolution
                      </p>
                      <span
                        className="rounded-full px-2 py-0.5"
                        style={{ fontSize: 9, fontWeight: 700, color: '#A78BFA', background: 'rgba(124,58,237,0.15)', fontFamily: font, letterSpacing: 0.6 }}
                      >
                        TREND
                      </span>
                    </div>
                    <div style={{ height: 110 }}>
                      <ResponsiveContainer width="100%" height={110}>
                        <AreaChart data={trendData} margin={{ top: 5, right: 4, bottom: 0, left: 4 }}>
                          <defs>
                            <linearGradient id="budgetAreaGrad" x1="0" y1="0" x2="0" y2="1">
                              <stop offset="0%" stopColor="#7C3AED" stopOpacity={0.5} />
                              <stop offset="100%" stopColor="#7C3AED" stopOpacity={0.02} />
                            </linearGradient>
                          </defs>
                          <CartesianGrid stroke="rgba(255,255,255,0.04)" vertical={false} />
                          <XAxis
                            dataKey="name"
                            tickFormatter={n => {
                              const item = trendData.find(t => t.name === n);
                              return item?.label ?? '';
                            }}
                            tick={{ fill: 'rgba(255,255,255,0.28)', fontSize: 9, fontFamily: font }}
                            axisLine={false}
                            tickLine={false}
                          />
                          <YAxis hide />
                          <Tooltip
                            contentStyle={{ background: '#111', border: '1px solid rgba(124,58,237,0.35)', borderRadius: 10, fontSize: 11, fontFamily: font }}
                            formatter={(v: number) => [formatCurrency(v), 'Budget']}
                            labelFormatter={n => {
                              const item = trendData.find(t => t.name === n);
                              return item?.label ?? '';
                            }}
                            itemStyle={{ color: '#A78BFA' }}
                            labelStyle={{ color: 'rgba(255,255,255,0.4)' }}
                          />
                          <Area
                            type="monotone"
                            dataKey="amount"
                            stroke="#7C3AED"
                            strokeWidth={2.5}
                            fill="url(#budgetAreaGrad)"
                            dot={{ fill: '#A78BFA', r: 3, strokeWidth: 0 }}
                            activeDot={{ r: 5, fill: '#C4B5FD', strokeWidth: 0 }}
                          />
                        </AreaChart>
                      </ResponsiveContainer>
                    </div>
                  </motion.div>
                )}

                {/* ── Spending vs Budget Chart ── */}
                {spendingChart.length > 0 && (
                  <motion.div
                    initial={{ opacity: 0, y: 14 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.13 }}
                    className="mx-4 mt-4 rounded-2xl p-4"
                    style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.07)' }}
                  >
                    <div className="flex items-center justify-between mb-3">
                      <p style={{ fontSize: 13, fontWeight: 700, color: 'rgba(255,255,255,0.6)', fontFamily: font }}>
                        Spending vs Budget
                      </p>
                      <div className="flex items-center gap-3">
                        <div className="flex items-center gap-1">
                          <div style={{ width: 8, height: 8, borderRadius: 2, background: 'rgba(255,255,255,0.15)' }} />
                          <span style={{ fontSize: 9, color: 'rgba(255,255,255,0.35)', fontFamily: font }}>Budget</span>
                        </div>
                        <div className="flex items-center gap-1">
                          <div style={{ width: 8, height: 8, borderRadius: 2, background: '#22C55E' }} />
                          <span style={{ fontSize: 9, color: 'rgba(255,255,255,0.35)', fontFamily: font }}>Spent</span>
                        </div>
                      </div>
                    </div>
                    <div style={{ height: 120 }}>
                      <ResponsiveContainer width="100%" height={120}>
                        <AreaChart data={spendingChart} margin={{ top: 0, right: 4, bottom: 0, left: 4 }}>
                          <defs>
                            <linearGradient id="budgetBgGrad" x1="0" y1="0" x2="0" y2="1">
                              <stop offset="0%" stopColor="rgba(255,255,255,0.12)" stopOpacity={1} />
                              <stop offset="100%" stopColor="rgba(255,255,255,0.02)" stopOpacity={1} />
                            </linearGradient>
                          </defs>
                          <XAxis
                            dataKey="name"
                            tick={{ fill: 'rgba(255,255,255,0.28)', fontSize: 9, fontFamily: font }}
                            axisLine={false}
                            tickLine={false}
                          />
                          <YAxis hide />
                          <Tooltip
                            contentStyle={{ background: '#111', border: '1px solid rgba(255,255,255,0.12)', borderRadius: 10, fontSize: 11, fontFamily: font }}
                            formatter={(v: number, name: string) => [formatCurrency(v), name === 'budget' ? 'Budget' : 'Spent']}
                            itemStyle={{ color: 'rgba(255,255,255,0.7)' }}
                            labelStyle={{ color: 'rgba(255,255,255,0.4)' }}
                          />
                          <Area type="monotone" dataKey="budget" stroke="rgba(255,255,255,0.2)" strokeWidth={1.5} fill="url(#budgetBgGrad)" dot={false} name="budget" />
                          <Area
                            type="monotone"
                            dataKey="spent"
                            stroke="#22C55E"
                            strokeWidth={2}
                            fill="rgba(34,197,94,0.1)"
                            dot={{ r: 3, fill: '#22C55E', strokeWidth: 0 }}
                            activeDot={{ r: 5, strokeWidth: 0 }}
                            name="spent"
                          />
                        </AreaChart>
                      </ResponsiveContainer>
                    </div>
                  </motion.div>
                )}

                {/* ── Budget Changes Timeline ── */}
                <motion.div
                  initial={{ opacity: 0, y: 14 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.16 }}
                  className="mx-4 mt-5"
                >
                  <p style={{ fontSize: 15, fontWeight: 700, color: '#fff', fontFamily: font, marginBottom: 14 }}>
                    Budget Changes
                  </p>

                  <div className="relative flex flex-col gap-0">
                    {/* Vertical connector line */}
                    <div
                      className="absolute left-[11px] top-4 bottom-4"
                      style={{ width: 1, background: 'linear-gradient(to bottom, rgba(124,58,237,0.5), rgba(124,58,237,0.05))' }}
                    />

                    {changes.map((ch, i) => {
                      const isUp = ch.delta !== null && ch.delta > 0;
                      const isDown = ch.delta !== null && ch.delta < 0;
                      const dotColor = ch.isFirst ? '#818CF8' : isUp ? '#22C55E' : isDown ? '#EF4444' : '#6B7280';

                      return (
                        <motion.div
                          key={ch.id}
                          initial={{ opacity: 0, x: -14 }}
                          animate={{ opacity: 1, x: 0 }}
                          transition={{ delay: 0.18 + i * 0.07 }}
                          className="flex items-start gap-3 pb-3"
                        >
                          {/* Timeline dot */}
                          <div
                            className="shrink-0 flex items-center justify-center rounded-full"
                            style={{
                              width: 24, height: 24, marginTop: 2,
                              background: `${dotColor}1A`,
                              border: `2px solid ${dotColor}`,
                              zIndex: 1,
                            }}
                          >
                            {ch.isFirst
                              ? <span style={{ fontSize: 10 }}>🌟</span>
                              : isUp
                                ? <TrendingUp size={10} color={dotColor} />
                                : <TrendingDown size={10} color={dotColor} />
                            }
                          </div>

                          {/* Card */}
                          <div
                            className="flex-1 rounded-2xl px-3 py-3"
                            style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}
                          >
                            <div className="flex items-center justify-between mb-1">
                              <span style={{ fontSize: 18, fontWeight: 800, color: '#fff', fontFamily: font }}>
                                {formatCurrency(ch.amount)}
                              </span>
                              {ch.isFirst ? (
                                <span
                                  className="rounded-lg px-2 py-0.5"
                                  style={{ fontSize: 9, fontWeight: 800, color: '#818CF8', background: 'rgba(99,102,241,0.2)', letterSpacing: 0.8, fontFamily: font }}
                                >
                                  INITIAL BUDGET
                                </span>
                              ) : (
                                <span
                                  className="rounded-lg px-2 py-0.5"
                                  style={{
                                    fontSize: 9, fontWeight: 800, letterSpacing: 0.6, fontFamily: font,
                                    color: isUp ? '#22C55E' : '#EF4444',
                                    background: isUp ? 'rgba(34,197,94,0.12)' : 'rgba(239,68,68,0.12)',
                                  }}
                                >
                                  {isUp ? '+' : ''}{ch.deltaPct}%
                                </span>
                              )}
                            </div>
                            <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.32)', fontFamily: font }}>
                              {ch.displayDate}
                            </p>
                            {ch.delta !== null && ch.delta !== 0 && (
                              <p style={{
                                fontSize: 11, fontFamily: font, marginTop: 3,
                                color: isUp ? '#86EFAC' : '#FCA5A5',
                              }}>
                                {isUp ? '↑ Increased by ' : '↓ Decreased by '}{formatCurrency(Math.abs(ch.delta))}
                              </p>
                            )}
                          </div>
                        </motion.div>
                      );
                    })}
                  </div>
                </motion.div>

                {/* ── Monthly Performance ── */}
                {monthlyPerf.length > 0 && (
                  <motion.div
                    initial={{ opacity: 0, y: 14 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.2 }}
                    className="mx-4 mt-5"
                  >
                    <p style={{ fontSize: 15, fontWeight: 700, color: '#fff', fontFamily: font, marginBottom: 14 }}>
                      Monthly Performance
                    </p>

                    <div className="flex flex-col gap-3">
                      {monthlyPerf.map((m, i) => {
                        const cfg = STATUS[m.status];
                        const isDrained = m.status === 'drained';

                        return (
                          <motion.div
                            key={m.month}
                            initial={{ opacity: 0, y: 10 }}
                            animate={{ opacity: 1, y: 0 }}
                            transition={{ delay: 0.22 + i * 0.05 }}
                            className="rounded-2xl overflow-hidden"
                            style={{
                              background: isDrained
                                ? 'linear-gradient(135deg, rgba(239,68,68,0.1), rgba(239,68,68,0.04))'
                                : cfg.dimBg,
                              border: `1px solid ${cfg.border}`,
                              borderLeft: isDrained ? `4px solid ${cfg.color}` : `1px solid ${cfg.border}`,
                            }}
                          >
                            <div className="px-4 py-3">
                              {/* Top row: label + status */}
                              <div className="flex items-center justify-between mb-2.5">
                                <div className="flex items-center gap-2">
                                  {isDrained && (
                                    <motion.span
                                      animate={{ scale: [1, 1.25, 1] }}
                                      transition={{ duration: 1.4, repeat: Infinity }}
                                      style={{ fontSize: 16, lineHeight: 1 }}
                                    >
                                      🔥
                                    </motion.span>
                                  )}
                                  <span style={{ fontSize: 14, fontWeight: 700, color: '#fff', fontFamily: font }}>
                                    {m.label}
                                  </span>
                                  {m.isCurrent && (
                                    <span
                                      className="rounded-full px-2 py-0.5"
                                      style={{ fontSize: 9, fontWeight: 700, color: '#818CF8', background: 'rgba(99,102,241,0.2)', letterSpacing: 0.6, fontFamily: font }}
                                    >
                                      CURRENT
                                    </span>
                                  )}
                                </div>
                                <motion.span
                                  animate={isDrained ? { opacity: [1, 0.45, 1] } : {}}
                                  transition={isDrained ? { duration: 1.4, repeat: Infinity } : {}}
                                  className="rounded-full px-2.5 py-1"
                                  style={{
                                    fontSize: 9, fontWeight: 800, letterSpacing: 0.7, fontFamily: font,
                                    color: cfg.color,
                                    background: cfg.dimBg,
                                    border: `1px solid ${cfg.border}`,
                                  }}
                                >
                                  {cfg.label}
                                </motion.span>
                              </div>

                              {/* Animated progress bar */}
                              <div
                                className="rounded-full overflow-hidden mb-2.5"
                                style={{ height: 6, background: 'rgba(255,255,255,0.07)' }}
                              >
                                <motion.div
                                  className="h-full rounded-full"
                                  initial={{ width: 0 }}
                                  animate={{ width: `${m.pct * 100}%` }}
                                  transition={{ duration: 1, delay: 0.28 + i * 0.05, ease: 'easeOut' }}
                                  style={{
                                    background: isDrained
                                      ? `linear-gradient(90deg, #EF4444, #FCA5A5)`
                                      : cfg.color,
                                    boxShadow: isDrained ? `0 0 10px rgba(239,68,68,0.6)` : 'none',
                                  }}
                                />
                              </div>

                              {/* Amounts row */}
                              <div className="flex items-center justify-between">
                                <span style={{ fontSize: 12, fontWeight: 600, color: 'rgba(255,255,255,0.55)', fontFamily: font }}>
                                  {formatCurrency(m.spent)} spent
                                </span>
                                {m.budget > 0 && (
                                  <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.32)', fontFamily: font }}>
                                    of {formatCurrency(m.budget)} · {Math.round(m.rawPct * 100)}%
                                  </span>
                                )}
                              </div>

                              {/* Drained overspent banner */}
                              {isDrained && m.overspent > 0 && (
                                <motion.div
                                  initial={{ opacity: 0, height: 0 }}
                                  animate={{ opacity: 1, height: 'auto' }}
                                  className="mt-2.5 rounded-xl px-3 py-2 flex items-center gap-2"
                                  style={{ background: 'rgba(239,68,68,0.18)', border: '1px solid rgba(239,68,68,0.35)' }}
                                >
                                  <span style={{ fontSize: 13 }}>⚠️</span>
                                  <div>
                                    <span style={{ fontSize: 12, fontWeight: 700, color: '#FCA5A5', fontFamily: font }}>
                                      Overspent by {formatCurrency(m.overspent)}
                                    </span>
                                    <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.3)', fontFamily: font, marginTop: 1 }}>
                                      Budget completely drained this period
                                    </p>
                                  </div>
                                </motion.div>
                              )}
                            </div>
                          </motion.div>
                        );
                      })}
                    </div>
                  </motion.div>
                )}

              </>
            )}
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
