import { useMemo, useState, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, TrendingUp, TrendingDown, Minus, Sparkles, AlertTriangle, ArrowDownRight, Zap } from 'lucide-react';
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis,
  Tooltip, ResponsiveContainer, CartesianGrid,
} from 'recharts';
import type { Expense } from '../../types/expense';
import { CATEGORY_COLORS, CATEGORY_ICONS } from '../../types/expense';
import { formatCurrency } from '../../utils/categoryUtils';

type FilterKey = 'This Week' | 'Last Week' | 'This Month' | 'Last Month' | 'Last 3M' | 'Last 6M' | 'All Time';
const FILTERS: FilterKey[] = ['This Week', 'Last Week', 'This Month', 'Last Month', 'Last 3M', 'Last 6M', 'All Time'];
const font = "'Plus Jakarta Sans', sans-serif";

// ── Date range helper ──────────────────────────────────────────────────────
function getDateRange(filter: FilterKey) {
  const now = new Date();
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  switch (filter) {
    case 'This Week': {
      const s = new Date(today); s.setDate(today.getDate() - today.getDay());
      const e = new Date(s); e.setDate(s.getDate() + 6);
      const ps = new Date(s); ps.setDate(s.getDate() - 7);
      const pe = new Date(e); pe.setDate(e.getDate() - 7);
      return { start: s, end: e, prevStart: ps, prevEnd: pe };
    }
    case 'Last Week': {
      const e = new Date(today); e.setDate(today.getDate() - today.getDay() - 1);
      const s = new Date(e); s.setDate(e.getDate() - 6);
      const pe = new Date(s); pe.setDate(s.getDate() - 1);
      const ps = new Date(pe); ps.setDate(pe.getDate() - 6);
      return { start: s, end: e, prevStart: ps, prevEnd: pe };
    }
    case 'This Month': {
      const s = new Date(now.getFullYear(), now.getMonth(), 1);
      const e = new Date(now.getFullYear(), now.getMonth() + 1, 0);
      const ps = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      const pe = new Date(now.getFullYear(), now.getMonth(), 0);
      return { start: s, end: e, prevStart: ps, prevEnd: pe };
    }
    case 'Last Month': {
      const e = new Date(now.getFullYear(), now.getMonth(), 0);
      const s = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      const pe = new Date(now.getFullYear(), now.getMonth() - 1, 0);
      const ps = new Date(now.getFullYear(), now.getMonth() - 2, 1);
      return { start: s, end: e, prevStart: ps, prevEnd: pe };
    }
    case 'Last 3M': {
      const s = new Date(now.getFullYear(), now.getMonth() - 2, 1);
      const e = new Date(now.getFullYear(), now.getMonth() + 1, 0);
      const ps = new Date(now.getFullYear(), now.getMonth() - 5, 1);
      const pe = new Date(s); pe.setDate(pe.getDate() - 1);
      return { start: s, end: e, prevStart: ps, prevEnd: pe };
    }
    case 'Last 6M': {
      const s = new Date(now.getFullYear(), now.getMonth() - 5, 1);
      const e = new Date(now.getFullYear(), now.getMonth() + 1, 0);
      const ps = new Date(now.getFullYear(), now.getMonth() - 11, 1);
      const pe = new Date(s); pe.setDate(pe.getDate() - 1);
      return { start: s, end: e, prevStart: ps, prevEnd: pe };
    }
    default:
      return { start: new Date(0), end: today, prevStart: new Date(0), prevEnd: today };
  }
}

function filterByRange(expenses: Expense[], start: Date, end: Date) {
  return expenses.filter(e => {
    const d = new Date(e.date);
    return d >= start && d <= new Date(end.getTime() + 86399999);
  });
}

// ── AI Insight Generator ──────────────────────────────────────────────────
function generateAIInsights(
  curr: Expense[], prev: Expense[], filter: FilterKey, budget: number
): { headline: string; bullets: string[]; recommendation: string; score: number } {
  const currTotal = curr.reduce((s, e) => s + e.amount, 0);
  const prevTotal = prev.reduce((s, e) => s + e.amount, 0);
  const changePct = prevTotal > 0 ? Math.round(((currTotal - prevTotal) / prevTotal) * 100) : 0;

  const catMap: Record<string, number> = {};
  curr.forEach(e => { catMap[e.category] = (catMap[e.category] || 0) + e.amount; });
  const prevCatMap: Record<string, number> = {};
  prev.forEach(e => { prevCatMap[e.category] = (prevCatMap[e.category] || 0) + e.amount; });

  const sortedCats = Object.entries(catMap).sort((a, b) => b[1] - a[1]);
  const topCat = sortedCats[0];
  const topCatPct = currTotal > 0 && topCat ? Math.round((topCat[1] / currTotal) * 100) : 0;

  const dayMap: Record<number, number> = {};
  curr.forEach(e => {
    const d = new Date(e.date).getDay();
    dayMap[d] = (dayMap[d] || 0) + e.amount;
  });
  const dayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
  const topDayEntry = Object.entries(dayMap).sort((a, b) => Number(b[1]) - Number(a[1]))[0];

  const avgTxn = curr.length > 0 ? Math.round(currTotal / curr.length) : 0;

  if (currTotal === 0) {
    return {
      headline: 'No spending activity this period',
      bullets: [
        'Your account has no transactions recorded for the selected period.',
        'Add expenses using the + button to start seeing AI-powered insights.',
        'Insights compare current vs previous period to surface trends.',
      ],
      recommendation: 'Start logging expenses to unlock personalised spending intelligence.',
      score: 100,
    };
  }

  let headline = '';
  if (changePct > 30) headline = `⚠️ Spending is up ${changePct}% — significantly above last period`;
  else if (changePct > 10) headline = `Spending up ${changePct}% vs last period`;
  else if (changePct < -20) headline = `🎉 Down ${Math.abs(changePct)}% — excellent financial discipline`;
  else if (changePct < -5) headline = `Spending eased ${Math.abs(changePct)}% from last period`;
  else if (prevTotal > 0) headline = `Spending is steady (${changePct >= 0 ? '+' : ''}${changePct}% vs last period)`;
  else headline = `${curr.length} transaction${curr.length !== 1 ? 's' : ''} recorded this period`;

  const bullets: string[] = [];

  if (topCat && topCatPct > 30) {
    const prevTopAmt = prevCatMap[topCat[0]] || 0;
    const catChange = prevTopAmt > 0 ? Math.round(((topCat[1] - prevTopAmt) / prevTopAmt) * 100) : 0;
    bullets.push(
      `${topCat[0]} is your top category at ${topCatPct}% (${formatCurrency(topCat[1])})${catChange !== 0 ? `, ${catChange > 0 ? 'up' : 'down'} ${Math.abs(catChange)}% vs last period` : ''}.`
    );
  }

  if (topDayEntry) {
    bullets.push(
      `${dayNames[parseInt(topDayEntry[0])]} is your peak spending day (${formatCurrency(Number(topDayEntry[1]))}).`
    );
  }

  if (budget > 0 && (filter === 'This Month' || filter === 'Last Month')) {
    const pct = Math.round((currTotal / budget) * 100);
    if (pct >= 100) {
      bullets.push(`Budget exceeded by ${formatCurrency(currTotal - budget)} (${pct}% of ${formatCurrency(budget)} limit).`);
    } else {
      bullets.push(`Budget utilisation at ${pct}% — ${formatCurrency(budget - currTotal)} remaining from ${formatCurrency(budget)}.`);
    }
  } else if (curr.length > 1) {
    bullets.push(`${curr.length} transactions averaging ${formatCurrency(avgTxn)} each.`);
  }

  if (bullets.length < 3 && sortedCats.length > 1) {
    const second = sortedCats[1];
    const secondPct = Math.round((second[1] / currTotal) * 100);
    bullets.push(`${second[0]} is your 2nd biggest category at ${secondPct}% (${formatCurrency(second[1])}).`);
  }

  let recommendation = '';
  let score = 75;
  if (changePct > 30) { recommendation = `Review your ${topCat?.[0] ?? 'top'} spending — it's the primary driver of this spike.`; score = 40; }
  else if (changePct > 10) { recommendation = `Keep an eye on ${topCat?.[0] ?? 'top'} expenses to prevent a runaway trend.`; score = 62; }
  else if (changePct < -15) { recommendation = `Great momentum! Reallocate savings toward an emergency fund or investments.`; score = 92; }
  else if (topCatPct > 50) { recommendation = `${topCat?.[0]} dominates your budget. Set a category limit to diversify.`; score = 65; }
  else { recommendation = `Spending is well-balanced. Maintain this pattern to hit your savings goals.`; score = 82; }

  return { headline, bullets: bullets.slice(0, 3), recommendation, score };
}

// ── Typing animation hook ──────────────────────────────────────────────────
function useTypedText(text: string, speed = 18, delay = 300) {
  const [displayed, setDisplayed] = useState('');
  const [done, setDone] = useState(false);
  const prevText = useRef('');

  useEffect(() => {
    if (text === prevText.current) return;
    prevText.current = text;
    setDisplayed('');
    setDone(false);
    let i = 0;
    const timer = setTimeout(() => {
      const interval = setInterval(() => {
        i++;
        setDisplayed(text.slice(0, i));
        if (i >= text.length) { clearInterval(interval); setDone(true); }
      }, speed);
      return () => clearInterval(interval);
    }, delay);
    return () => clearTimeout(timer);
  }, [text, speed, delay]);

  return { displayed, done };
}

interface Props { open: boolean; onClose: () => void; expenses: Expense[]; budget: number; }

export function ExpenseTrendModal({ open, onClose, expenses, budget }: Props) {
  const [filter, setFilter] = useState<FilterKey>('This Month');

  const data = useMemo(() => {
    const { start, end, prevStart, prevEnd } = getDateRange(filter);
    const curr = filterByRange(expenses, start, end);
    const prev = filterByRange(expenses, prevStart, prevEnd);

    const currTotal = curr.reduce((s, e) => s + e.amount, 0);
    const prevTotal = prev.reduce((s, e) => s + e.amount, 0);
    const changePct = prevTotal > 0 ? Math.round(((currTotal - prevTotal) / prevTotal) * 100) : 0;

    // ── Area chart: spending over time ──
    const barMap: Record<string, number> = {};
    curr.forEach(e => {
      const d = new Date(e.date);
      let key = '';
      if (filter === 'This Week' || filter === 'Last Week') {
        key = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d.getDay()];
      } else if (filter === 'This Month' || filter === 'Last Month') {
        key = `${d.getDate()}`;
      } else {
        const mo = d.toLocaleString('en', { month: 'short' });
        const yr = String(d.getFullYear()).slice(2);
        key = `${mo} '${yr}`;
      }
      barMap[key] = (barMap[key] || 0) + e.amount;
    });

    let chartData: { name: string; amount: number }[] = [];
    if (filter === 'This Week' || filter === 'Last Week') {
      chartData = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map(k => ({ name: k, amount: barMap[k] || 0 }));
    } else {
      chartData = Object.entries(barMap).map(([name, amount]) => ({ name, amount }));
    }

    // ── Category breakdown ──
    const catMap: Record<string, number> = {};
    curr.forEach(e => { catMap[e.category] = (catMap[e.category] || 0) + e.amount; });
    const prevCatMap: Record<string, number> = {};
    prev.forEach(e => { prevCatMap[e.category] = (prevCatMap[e.category] || 0) + e.amount; });

    const categories = Object.entries(catMap)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([cat, amt]) => {
        const prevAmt = prevCatMap[cat] || 0;
        const shift = prevAmt > 0 ? Math.round(((amt - prevAmt) / prevAmt) * 100) : amt > 0 ? 100 : 0;
        return {
          cat, amt,
          pct: currTotal > 0 ? Math.round((amt / currTotal) * 100) : 0,
          prevAmt, shift,
          color: CATEGORY_COLORS[cat] || '#818CF8',
          icon: CATEGORY_ICONS[cat] || '📦',
        };
      });

    // ── Day-of-week pattern ──
    const dayPattern = [0, 1, 2, 3, 4, 5, 6].map(d => {
      const total = curr.filter(e => new Date(e.date).getDay() === d).reduce((s, e) => s + e.amount, 0);
      return { name: ['S', 'M', 'T', 'W', 'T', 'F', 'S'][d], day: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d], amount: total };
    });
    const maxDay = [...dayPattern].sort((a, b) => b.amount - a.amount)[0];

    // ── Stats ──
    const days = (end.getTime() - start.getTime()) / 86400000 + 1;
    const activeDays = new Set(curr.map(e => new Date(e.date).toDateString())).size;
    const avgPerDay = activeDays > 0 ? Math.round(currTotal / activeDays) : 0;
    const maxDayAmt = Math.max(...chartData.map(d => d.amount), 0);

    // ── Anomalies ──
    const anomalies: { type: 'spike' | 'drop'; cat: string; msg: string }[] = [];
    categories.forEach(item => {
      if (item.shift > 40 && item.amt > 0) {
        anomalies.push({ type: 'spike', cat: item.cat, msg: `+${item.shift}% increase vs last period. ${formatCurrency(item.amt)} spent.` });
      } else if (item.shift < -30 && item.prevAmt > 0) {
        anomalies.push({ type: 'drop', cat: item.cat, msg: `${item.shift}% lower than last period. Saved ${formatCurrency(item.prevAmt - item.amt)}.` });
      }
    });

    // ── Forecast (for monthly views) ──
    const now = new Date();
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const daysPassed = now.getDate();
    const forecastAmt = filter === 'This Month' && daysPassed > 0
      ? Math.round((currTotal / daysPassed) * daysInMonth)
      : null;

    const aiInsights = generateAIInsights(curr, prev, filter, budget);

    return {
      curr, prev, currTotal, prevTotal, changePct,
      chartData, categories, dayPattern, maxDay,
      stats: { avgPerDay, maxDayAmt, txnCount: curr.length, activeDays, days },
      anomalies: anomalies.slice(0, 3),
      forecastAmt,
      aiInsights,
    };
  }, [filter, expenses, budget]);

  const { displayed: typedHeadline } = useTypedText(
    open ? data.aiInsights.headline : '',
    14, 400
  );

  const isEmpty = data.curr.length === 0;
  const isUp = data.changePct > 0;
  const isStable = data.prevTotal === 0 || Math.abs(data.changePct) <= 3;

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
            <div className="flex items-center gap-2">
              <span style={{ fontSize: 16, fontWeight: 800, color: '#fff', fontFamily: font, letterSpacing: '-0.3px' }}>
                Expense Trend
              </span>
              <div
                className="flex items-center gap-1 rounded-full px-2 py-0.5"
                style={{ background: 'rgba(239,68,68,0.18)', border: '1px solid rgba(239,68,68,0.35)' }}
              >
                <motion.div
                  animate={{ opacity: [1, 0.3, 1], scale: [1, 1.3, 1] }}
                  transition={{ duration: 1.5, repeat: Infinity }}
                  style={{ width: 5, height: 5, borderRadius: '50%', background: '#EF4444' }}
                />
                <span style={{ fontSize: 9, fontWeight: 800, color: '#EF4444', letterSpacing: 1, fontFamily: font }}>LIVE</span>
              </div>
            </div>
            <motion.button
              whileTap={{ scale: 0.85 }}
              onClick={onClose}
              className="flex items-center justify-center rounded-full"
              style={{ width: 36, height: 36, background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.1)' }}
            >
              <X size={18} color="rgba(255,255,255,0.8)" />
            </motion.button>
          </div>

          {/* ── Filter chips ── */}
          <div
            className="shrink-0 flex gap-2 overflow-x-auto px-4 py-3 scrollbar-hide"
            style={{ borderBottom: '1px solid rgba(255,255,255,0.07)' }}
          >
            {FILTERS.map(f => (
              <motion.button
                key={f}
                whileTap={{ scale: 0.94 }}
                onClick={() => setFilter(f)}
                className="shrink-0 rounded-full px-3.5 py-1.5"
                style={{
                  background: filter === f ? 'linear-gradient(135deg, #7C3AED, #6366F1)' : 'rgba(255,255,255,0.06)',
                  border: `1px solid ${filter === f ? 'transparent' : 'rgba(255,255,255,0.1)'}`,
                  fontSize: 12, fontWeight: filter === f ? 700 : 500,
                  color: filter === f ? '#fff' : 'rgba(255,255,255,0.45)',
                  fontFamily: font, whiteSpace: 'nowrap',
                  boxShadow: filter === f ? '0 2px 14px rgba(124,58,237,0.45)' : 'none',
                  transition: 'all 0.22s',
                }}
              >
                {f}
              </motion.button>
            ))}
          </div>

          {/* ── Scrollable body ── */}
          <div className="flex-1 overflow-y-auto pb-10">

            {/* ━━━━ HERO SECTION ━━━━ */}
            <AnimatePresence mode="wait">
              <motion.div
                key={filter}
                initial={{ opacity: 0, y: 16 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -10 }}
                transition={{ duration: 0.28 }}
                className="mx-4 mt-4 rounded-3xl overflow-hidden"
                style={{
                  background: 'linear-gradient(145deg, #110826 0%, #1a0d36 50%, #0d1a3a 100%)',
                  border: '1px solid rgba(124,58,237,0.3)',
                }}
              >
                <div className="px-5 pt-5 pb-3">
                  {/* Top row */}
                  <div className="flex items-start justify-between mb-1">
                    <div>
                      <p style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.35)', fontFamily: font, letterSpacing: 1.5, marginBottom: 4 }}>
                        {filter.toUpperCase()} TOTAL
                      </p>
                      <motion.p
                        key={`${filter}-total`}
                        initial={{ scale: 0.85, opacity: 0 }}
                        animate={{ scale: 1, opacity: 1 }}
                        transition={{ duration: 0.3, type: 'spring' }}
                        style={{ fontSize: 38, fontWeight: 900, color: '#fff', fontFamily: font, letterSpacing: '-1.5px', lineHeight: 1 }}
                      >
                        {formatCurrency(data.currTotal)}
                      </motion.p>
                    </div>

                    {/* vs previous badge */}
                    {data.prevTotal > 0 && (
                      <motion.div
                        initial={{ scale: 0, opacity: 0 }}
                        animate={{ scale: 1, opacity: 1 }}
                        transition={{ delay: 0.15, type: 'spring' }}
                        className="flex items-center gap-1 rounded-2xl px-3 py-1.5"
                        style={{
                          background: isStable ? 'rgba(255,255,255,0.08)' : isUp ? 'rgba(239,68,68,0.18)' : 'rgba(34,197,94,0.18)',
                          border: `1px solid ${isStable ? 'rgba(255,255,255,0.12)' : isUp ? 'rgba(239,68,68,0.4)' : 'rgba(34,197,94,0.4)'}`,
                          marginTop: 8,
                        }}
                      >
                        {isStable
                          ? <Minus size={12} color="rgba(255,255,255,0.5)" />
                          : isUp
                            ? <TrendingUp size={12} color="#EF4444" />
                            : <TrendingDown size={12} color="#22C55E" />
                        }
                        <span style={{
                          fontSize: 12, fontWeight: 800, fontFamily: font,
                          color: isStable ? 'rgba(255,255,255,0.5)' : isUp ? '#FCA5A5' : '#86EFAC',
                        }}>
                          {isStable ? 'Stable' : `${isUp ? '+' : ''}${data.changePct}%`}
                        </span>
                      </motion.div>
                    )}
                  </div>

                  <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', fontFamily: font, marginTop: 4 }}>
                    {data.stats.txnCount} transaction{data.stats.txnCount !== 1 ? 's' : ''}
                    {data.prevTotal > 0 && ` · prev period ${formatCurrency(data.prevTotal)}`}
                  </p>
                </div>

                {/* Area chart */}
                <div style={{ height: 120 }}>
                  <ResponsiveContainer width="100%" height={120}>
                    <AreaChart data={data.chartData} margin={{ top: 4, right: 0, bottom: 0, left: 0 }}>
                      <defs>
                        <linearGradient id="heroGrad" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor="#7C3AED" stopOpacity={0.55} />
                          <stop offset="100%" stopColor="#7C3AED" stopOpacity={0.02} />
                        </linearGradient>
                      </defs>
                      <CartesianGrid stroke="rgba(255,255,255,0.04)" vertical={false} />
                      <XAxis
                        dataKey="name"
                        tick={{ fill: 'rgba(255,255,255,0.25)', fontSize: 9, fontFamily: font }}
                        axisLine={false}
                        tickLine={false}
                        interval="preserveStartEnd"
                      />
                      <YAxis hide />
                      <Tooltip
                        contentStyle={{ background: '#14082a', border: '1px solid rgba(124,58,237,0.4)', borderRadius: 12, fontSize: 12, fontFamily: font }}
                        formatter={(v: number) => [formatCurrency(v), 'Spent']}
                        labelStyle={{ color: 'rgba(255,255,255,0.45)', marginBottom: 2 }}
                        itemStyle={{ color: '#C4B5FD', fontWeight: 700 }}
                        cursor={{ stroke: 'rgba(124,58,237,0.4)', strokeWidth: 1 }}
                      />
                      <Area
                        type="monotone"
                        dataKey="amount"
                        stroke="#7C3AED"
                        strokeWidth={2.5}
                        fill="url(#heroGrad)"
                        dot={false}
                        activeDot={{ r: 5, fill: '#C4B5FD', strokeWidth: 0 }}
                      />
                    </AreaChart>
                  </ResponsiveContainer>
                </div>

                {/* Quick stats row */}
                <div
                  className="flex items-center divide-x px-2 pb-4 pt-3"
                  style={{ borderTop: '1px solid rgba(255,255,255,0.06)', marginTop: 8 }}
                >
                  {[
                    { label: 'AVG / DAY', value: data.stats.avgPerDay > 0 ? formatCurrency(data.stats.avgPerDay) : '—', icon: '📅' },
                    { label: 'PEAK DAY', value: data.stats.maxDayAmt > 0 ? formatCurrency(data.stats.maxDayAmt) : '—', icon: '📈' },
                    { label: 'TRANSACTIONS', value: data.stats.txnCount, icon: '🔢' },
                  ].map(({ label, value, icon }) => (
                    <div key={label} className="flex-1 flex flex-col items-center py-1">
                      <span style={{ fontSize: 14, marginBottom: 2 }}>{icon}</span>
                      <p style={{ fontSize: 13, fontWeight: 800, color: '#fff', fontFamily: font, lineHeight: 1 }}>{value}</p>
                      <p style={{ fontSize: 8, color: 'rgba(255,255,255,0.3)', fontFamily: font, letterSpacing: 0.8, marginTop: 2 }}>{label}</p>
                    </div>
                  ))}
                </div>
              </motion.div>
            </AnimatePresence>

            {/* ━━━━ FORECAST BANNER (This Month only) ━━━━ */}
            {data.forecastAmt !== null && data.currTotal > 0 && (
              <motion.div
                initial={{ opacity: 0, y: 12 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.08 }}
                className="mx-4 mt-3 rounded-2xl px-4 py-3 flex items-center gap-3"
                style={{
                  background: data.forecastAmt > budget && budget > 0
                    ? 'linear-gradient(135deg, rgba(239,68,68,0.12), rgba(239,68,68,0.06))'
                    : 'linear-gradient(135deg, rgba(34,197,94,0.1), rgba(34,197,94,0.04))',
                  border: `1px solid ${data.forecastAmt > budget && budget > 0 ? 'rgba(239,68,68,0.3)' : 'rgba(34,197,94,0.25)'}`,
                }}
              >
                <span style={{ fontSize: 24 }}>
                  {data.forecastAmt > budget && budget > 0 ? '⚠️' : '📊'}
                </span>
                <div>
                  <p style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.4)', fontFamily: font, letterSpacing: 1 }}>
                    MONTH-END FORECAST
                  </p>
                  <p style={{ fontSize: 15, fontWeight: 800, color: '#fff', fontFamily: font }}>
                    {formatCurrency(data.forecastAmt)}
                    <span style={{ fontSize: 11, fontWeight: 400, color: 'rgba(255,255,255,0.4)', marginLeft: 6 }}>
                      projected total
                    </span>
                  </p>
                  {budget > 0 && (
                    <p style={{ fontSize: 11, color: data.forecastAmt > budget ? '#FCA5A5' : '#86EFAC', fontFamily: font, marginTop: 1 }}>
                      {data.forecastAmt > budget
                        ? `~${formatCurrency(data.forecastAmt - budget)} over budget`
                        : `~${formatCurrency(budget - data.forecastAmt)} under budget`
                      }
                    </p>
                  )}
                </div>
              </motion.div>
            )}

            {/* ━━━━ AI ANALYSIS ━━━━ */}
            <motion.div
              initial={{ opacity: 0, y: 14 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ delay: 0.1 }}
              className="mx-4 mt-4 rounded-3xl overflow-hidden"
              style={{
                background: 'linear-gradient(145deg, #0a0a1a 0%, #0f0a24 100%)',
                border: '1px solid rgba(167,139,250,0.25)',
              }}
            >
              {/* AI header */}
              <div
                className="flex items-center justify-between px-4 pt-4 pb-3"
                style={{ borderBottom: '1px solid rgba(167,139,250,0.1)' }}
              >
                <div className="flex items-center gap-2">
                  <div
                    className="rounded-xl p-1.5"
                    style={{ background: 'linear-gradient(135deg, #7C3AED, #6366F1)', boxShadow: '0 2px 10px rgba(124,58,237,0.5)' }}
                  >
                    <Sparkles size={13} color="#fff" />
                  </div>
                  <span style={{ fontSize: 13, fontWeight: 800, color: '#A78BFA', fontFamily: font, letterSpacing: 0.3 }}>
                    AI ANALYSIS
                  </span>
                </div>

                {/* Health score */}
                <div className="flex items-center gap-2">
                  <svg width={28} height={28} viewBox="0 0 28 28">
                    <circle cx={14} cy={14} r={11} fill="none" stroke="rgba(255,255,255,0.08)" strokeWidth={3} />
                    <motion.circle
                      cx={14} cy={14} r={11}
                      fill="none"
                      stroke={data.aiInsights.score >= 80 ? '#22C55E' : data.aiInsights.score >= 60 ? '#F59E0B' : '#EF4444'}
                      strokeWidth={3}
                      strokeLinecap="round"
                      strokeDasharray={69.1}
                      initial={{ strokeDashoffset: 69.1 }}
                      animate={{ strokeDashoffset: 69.1 * (1 - data.aiInsights.score / 100) }}
                      transition={{ duration: 1.2, delay: 0.4, ease: 'easeOut' }}
                      style={{ transform: 'rotate(-90deg)', transformOrigin: '50% 50%' }}
                    />
                  </svg>
                  <div>
                    <p style={{ fontSize: 15, fontWeight: 800, lineHeight: 1, fontFamily: font, color: data.aiInsights.score >= 80 ? '#22C55E' : data.aiInsights.score >= 60 ? '#F59E0B' : '#EF4444' }}>
                      {data.aiInsights.score}
                    </p>
                    <p style={{ fontSize: 8, color: 'rgba(255,255,255,0.3)', fontFamily: font, letterSpacing: 0.6 }}>SCORE</p>
                  </div>
                </div>
              </div>

              <div className="px-4 pt-3 pb-4">
                {/* Typed headline */}
                <p style={{
                  fontSize: 14, fontWeight: 700, color: '#E2D9F3', fontFamily: font,
                  lineHeight: 1.55, marginBottom: 12, minHeight: 44,
                }}>
                  {typedHeadline}
                  {typedHeadline.length < data.aiInsights.headline.length && (
                    <motion.span
                      animate={{ opacity: [1, 0] }}
                      transition={{ duration: 0.5, repeat: Infinity }}
                      style={{ display: 'inline-block', width: 2, height: 13, background: '#A78BFA', marginLeft: 2, borderRadius: 1, verticalAlign: 'middle' }}
                    />
                  )}
                </p>

                {/* Bullet insights */}
                <div className="flex flex-col gap-2.5 mb-3">
                  {data.aiInsights.bullets.map((bullet, i) => (
                    <motion.div
                      key={`${filter}-bullet-${i}`}
                      initial={{ opacity: 0, x: -10 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ delay: 0.5 + i * 0.12 }}
                      className="flex items-start gap-2.5"
                    >
                      <div
                        className="shrink-0 rounded-full mt-1.5"
                        style={{ width: 5, height: 5, background: ['#818CF8', '#A78BFA', '#C4B5FD'][i] }}
                      />
                      <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.58)', fontFamily: font, lineHeight: 1.6 }}>
                        {bullet}
                      </p>
                    </motion.div>
                  ))}
                </div>

                {/* Recommendation */}
                <motion.div
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  transition={{ delay: 0.9 }}
                  className="rounded-xl px-3 py-2.5 flex items-start gap-2"
                  style={{ background: 'rgba(124,58,237,0.14)', border: '1px solid rgba(124,58,237,0.28)' }}
                >
                  <span style={{ fontSize: 13, flexShrink: 0, marginTop: 1 }}>💡</span>
                  <p style={{ fontSize: 12, fontWeight: 600, color: '#C4B5FD', fontFamily: font, lineHeight: 1.55 }}>
                    {data.aiInsights.recommendation}
                  </p>
                </motion.div>
              </div>
            </motion.div>

            {/* ━━━━ CATEGORY BREAKDOWN ━━━━ */}
            {data.categories.length > 0 && (
              <motion.div
                initial={{ opacity: 0, y: 14 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.14 }}
                className="mx-4 mt-4 rounded-3xl"
                style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.08)' }}
              >
                <div className="flex items-center justify-between px-4 pt-4 pb-3">
                  <p style={{ fontSize: 15, fontWeight: 700, color: '#fff', fontFamily: font }}>
                    Category Breakdown
                  </p>
                  <span style={{ fontSize: 10, fontWeight: 600, color: 'rgba(255,255,255,0.3)', fontFamily: font }}>
                    TOP {data.categories.length}
                  </span>
                </div>

                <div className="flex flex-col px-4 pb-4 gap-4">
                  {data.categories.map((item, i) => {
                    const isUp = item.shift > 5;
                    const isDown = item.shift < -5;
                    return (
                      <motion.div
                        key={item.cat}
                        initial={{ opacity: 0, x: -12 }}
                        animate={{ opacity: 1, x: 0 }}
                        transition={{ delay: 0.18 + i * 0.06 }}
                      >
                        {/* Row 1: icon, name, shift badge, amount */}
                        <div className="flex items-center gap-2 mb-2">
                          <div
                            className="flex items-center justify-center rounded-xl shrink-0"
                            style={{ width: 34, height: 34, background: `${item.color}18`, border: `1px solid ${item.color}35` }}
                          >
                            <span style={{ fontSize: 16 }}>{item.icon}</span>
                          </div>
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center justify-between">
                              <span style={{ fontSize: 13, fontWeight: 700, color: 'rgba(255,255,255,0.88)', fontFamily: font }}>
                                {item.cat}
                              </span>
                              <div className="flex items-center gap-1.5">
                                {/* Shift badge */}
                                {item.prevAmt > 0 && (
                                  <div className="flex items-center gap-0.5 rounded-md px-1.5 py-0.5"
                                    style={{
                                      background: isUp ? 'rgba(239,68,68,0.12)' : isDown ? 'rgba(34,197,94,0.12)' : 'rgba(255,255,255,0.07)',
                                    }}
                                  >
                                    {isUp
                                      ? <TrendingUp size={9} color="#EF4444" />
                                      : isDown
                                        ? <TrendingDown size={9} color="#22C55E" />
                                        : <Minus size={9} color="rgba(255,255,255,0.4)" />
                                    }
                                    <span style={{
                                      fontSize: 9, fontWeight: 700, fontFamily: font,
                                      color: isUp ? '#FCA5A5' : isDown ? '#86EFAC' : 'rgba(255,255,255,0.4)',
                                    }}>
                                      {isUp ? '+' : ''}{item.shift}%
                                    </span>
                                  </div>
                                )}
                                <span style={{ fontSize: 14, fontWeight: 800, color: '#fff', fontFamily: font }}>
                                  {formatCurrency(item.amt)}
                                </span>
                              </div>
                            </div>
                          </div>
                        </div>

                        {/* Progress bar */}
                        <div
                          className="rounded-full overflow-hidden"
                          style={{ height: 5, background: 'rgba(255,255,255,0.06)' }}
                        >
                          <motion.div
                            className="h-full rounded-full"
                            initial={{ width: 0 }}
                            animate={{ width: `${item.pct}%` }}
                            transition={{ duration: 0.9, delay: 0.22 + i * 0.06, ease: 'easeOut' }}
                            style={{ background: `linear-gradient(90deg, ${item.color}90, ${item.color})`, boxShadow: `0 0 8px ${item.color}40` }}
                          />
                        </div>

                        <div className="flex items-center justify-between mt-1">
                          <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.28)', fontFamily: font }}>
                            {item.pct}% of total spend
                          </span>
                          {item.prevAmt > 0 && (
                            <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.25)', fontFamily: font }}>
                              prev: {formatCurrency(item.prevAmt)}
                            </span>
                          )}
                        </div>
                      </motion.div>
                    );
                  })}
                </div>
              </motion.div>
            )}

            {/* ━━━━ ANOMALIES ━━━━ */}
            {data.anomalies.length > 0 && (
              <motion.div
                initial={{ opacity: 0, y: 14 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.18 }}
                className="mx-4 mt-4"
              >
                <div className="flex items-center gap-2 mb-3">
                  <p style={{ fontSize: 15, fontWeight: 700, color: '#fff', fontFamily: font }}>
                    Anomalies Detected
                  </p>
                  <Zap size={14} color="#FBBF24" />
                </div>
                <div className="flex flex-col gap-3">
                  {data.anomalies.map((a, i) => (
                    <motion.div
                      key={`${a.cat}-${i}`}
                      initial={{ opacity: 0, x: -12 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ delay: 0.22 + i * 0.07 }}
                      className="flex items-start gap-3 rounded-2xl p-4"
                      style={{
                        background: a.type === 'spike' ? 'rgba(251,191,36,0.06)' : 'rgba(52,211,153,0.06)',
                        border: `1px solid ${a.type === 'spike' ? 'rgba(251,191,36,0.22)' : 'rgba(52,211,153,0.22)'}`,
                        borderLeft: `3px solid ${a.type === 'spike' ? '#FBBF24' : '#34D399'}`,
                      }}
                    >
                      <div
                        className="rounded-xl p-2 shrink-0"
                        style={{ background: a.type === 'spike' ? 'rgba(251,191,36,0.15)' : 'rgba(52,211,153,0.15)' }}
                      >
                        {a.type === 'spike'
                          ? <AlertTriangle size={14} color="#FBBF24" />
                          : <ArrowDownRight size={14} color="#34D399" />
                        }
                      </div>
                      <div className="flex-1">
                        <div className="flex items-center gap-1.5 mb-0.5">
                          <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.35)', fontFamily: font, letterSpacing: 1 }}>
                            {a.cat.toUpperCase()}
                          </span>
                          <span
                            className="rounded px-1.5 py-0.5"
                            style={{ fontSize: 9, fontWeight: 700, fontFamily: font, letterSpacing: 0.5, color: a.type === 'spike' ? '#FBBF24' : '#34D399', background: a.type === 'spike' ? 'rgba(251,191,36,0.15)' : 'rgba(52,211,153,0.15)' }}
                          >
                            {a.type === 'spike' ? '▲ SPIKE' : '▼ DROP'}
                          </span>
                        </div>
                        <p style={{ fontSize: 13, fontWeight: 700, color: '#fff', fontFamily: font, marginBottom: 2 }}>
                          {a.type === 'spike' ? `Spending Surge: ${a.cat}` : `Savings Win: ${a.cat}`}
                        </p>
                        <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.42)', fontFamily: font, lineHeight: 1.5 }}>
                          {a.msg}
                        </p>
                      </div>
                    </motion.div>
                  ))}
                </div>
              </motion.div>
            )}

            {/* ━━━━ DAY-OF-WEEK PATTERN ━━━━ */}
            {!isEmpty && (
              <motion.div
                initial={{ opacity: 0, y: 14 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.22 }}
                className="mx-4 mt-4 rounded-3xl p-4"
                style={{ background: 'rgba(255,255,255,0.025)', border: '1px solid rgba(255,255,255,0.08)' }}
              >
                <div className="flex items-center justify-between mb-3">
                  <p style={{ fontSize: 15, fontWeight: 700, color: '#fff', fontFamily: font }}>
                    Spending by Day
                  </p>
                  {data.maxDay && data.maxDay.amount > 0 && (
                    <span
                      className="rounded-full px-2.5 py-1"
                      style={{ fontSize: 10, fontWeight: 700, color: '#F59E0B', background: 'rgba(245,158,11,0.12)', border: '1px solid rgba(245,158,11,0.25)', fontFamily: font }}
                    >
                      🔥 Peak: {data.maxDay.day}
                    </span>
                  )}
                </div>

                <div style={{ height: 110 }}>
                  <ResponsiveContainer width="100%" height={110}>
                    <BarChart data={data.dayPattern} margin={{ top: 4, right: 4, bottom: 0, left: 4 }} barCategoryGap="28%">
                      <defs>
                        <linearGradient id="dayBarGrad" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor="#7C3AED" stopOpacity={1} />
                          <stop offset="100%" stopColor="#4F46E5" stopOpacity={0.7} />
                        </linearGradient>
                      </defs>
                      <CartesianGrid stroke="rgba(255,255,255,0.04)" vertical={false} />
                      <XAxis
                        dataKey="name"
                        tick={{ fill: 'rgba(255,255,255,0.35)', fontSize: 11, fontFamily: font }}
                        axisLine={false}
                        tickLine={false}
                      />
                      <YAxis hide />
                      <Tooltip
                        contentStyle={{ background: '#0d0b1a', border: '1px solid rgba(124,58,237,0.35)', borderRadius: 12, fontSize: 11, fontFamily: font }}
                        formatter={(v: number) => [formatCurrency(v), 'Spent']}
                        labelFormatter={(n: string) => data.dayPattern.find(d => d.name === n)?.day ?? n}
                        itemStyle={{ color: '#A78BFA' }}
                        labelStyle={{ color: 'rgba(255,255,255,0.4)' }}
                        cursor={{ fill: 'rgba(124,58,237,0.08)' }}
                      />
                      <Bar dataKey="amount" fill="url(#dayBarGrad)" radius={[5, 5, 2, 2]} />
                    </BarChart>
                  </ResponsiveContainer>
                </div>

                {/* Day totals micro-row */}
                <div className="flex items-end justify-between mt-2 px-1">
                  {data.dayPattern.map(d => (
                    <div key={d.day} className="flex flex-col items-center gap-0.5">
                      {d.amount > 0 && (
                        <span style={{ fontSize: 7.5, color: 'rgba(255,255,255,0.25)', fontFamily: font }}>
                          {d.amount >= 1000 ? `₹${Math.round(d.amount / 1000)}k` : `₹${d.amount}`}
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              </motion.div>
            )}

            {/* ━━━━ EMPTY STATE ━━━━ */}
            {isEmpty && (
              <motion.div
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                transition={{ delay: 0.15 }}
                className="flex flex-col items-center justify-center py-16 px-8"
              >
                <motion.div
                  animate={{ y: [0, -8, 0] }}
                  transition={{ duration: 2.5, repeat: Infinity, ease: 'easeInOut' }}
                  style={{ fontSize: 52, marginBottom: 16, textAlign: 'center' }}
                >
                  📊
                </motion.div>
                <p style={{ fontSize: 15, fontWeight: 700, color: 'rgba(255,255,255,0.45)', fontFamily: font, textAlign: 'center' }}>
                  No data for {filter}
                </p>
                <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.25)', fontFamily: font, textAlign: 'center', marginTop: 8, lineHeight: 1.6 }}>
                  Add some expenses and come back to see AI-powered spending insights.
                </p>
              </motion.div>
            )}

          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
