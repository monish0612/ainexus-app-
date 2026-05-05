import { useState, useMemo, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
  Search, X, TrendingUp, TrendingDown, Activity,
  Calendar, Hash, Sparkles, ChevronDown, ChevronUp, Zap,
} from 'lucide-react';
import {
  AreaChart, Area, BarChart, Bar, XAxis, YAxis,
  Tooltip, ResponsiveContainer, Cell,
} from 'recharts';
import type { Expense } from '../../types/expense';
import { CATEGORY_COLORS, CATEGORY_ICONS } from '../../types/expense';
import { formatCurrency } from '../../utils/categoryUtils';
import { usePalette } from '../../utils/palette';

const F = "'Plus Jakarta Sans', sans-serif";
const PERIODS = ['Today', '7D', '1M', '6M', 'All'] as const;
type Period = typeof PERIODS[number];

const PERIOD_LABEL: Record<Period, string> = {
  Today: 'today', '7D': 'last 7 days', '1M': 'last 30 days',
  '6M': 'last 6 months', All: 'all time',
};

// ─── Data helpers ─────────────────────────────────────────────────────────────

function cutoff(period: Period): Date {
  const d = new Date();
  if (period === 'Today') { d.setHours(0, 0, 0, 0); return d; }
  if (period === '7D')    { d.setDate(d.getDate() - 7); return d; }
  if (period === '1M')    { d.setDate(d.getDate() - 30); return d; }
  if (period === '6M')    { d.setMonth(d.getMonth() - 6); return d; }
  return new Date(0); // All
}

function buildTrendSeries(expenses: Expense[], period: Period) {
  if (!expenses.length) return [];

  if (period === 'All') {
    const mm: Record<string, number> = {};
    expenses.forEach(e => { const m = e.date.slice(0, 7); mm[m] = (mm[m] || 0) + e.amount; });
    const keys = Object.keys(mm).sort();
    if (!keys.length) return [];
    const start = new Date(keys[0] + '-01'), end = new Date();
    const cur = new Date(start), out: { label: string; amount: number }[] = [];
    while (cur <= end) {
      const k = cur.toISOString().slice(0, 7);
      out.push({ label: cur.toLocaleDateString('en', { month: 'short', year: '2-digit' }), amount: mm[k] || 0 });
      cur.setMonth(cur.getMonth() + 1);
    }
    return out;
  }

  if (period === 'Today') {
    const today = new Date().toISOString().slice(0, 10);
    const te = expenses.filter(e => e.date.slice(0, 10) === today);
    return Array.from({ length: 8 }, (_, i) => {
      const h = i * 3;
      return {
        label: h === 0 ? '12a' : h < 12 ? `${h}a` : h === 12 ? '12p' : `${h - 12}p`,
        amount: te.filter(e => { const eh = new Date(e.date).getHours(); return eh >= h && eh < h + 3; })
                  .reduce((s, e) => s + e.amount, 0),
      };
    });
  }

  const grouped: Record<string, number> = {};
  expenses.forEach(e => { const k = e.date.slice(0, 10); grouped[k] = (grouped[k] || 0) + e.amount; });

  if (period === '6M') {
    return Array.from({ length: 24 }, (_, i) => {
      const d = new Date(); d.setDate(d.getDate() - (23 - i) * 7);
      let amt = 0;
      for (let x = -3; x <= 3; x++) {
        const dd = new Date(d); dd.setDate(dd.getDate() + x);
        amt += grouped[dd.toISOString().slice(0, 10)] || 0;
      }
      return {
        label: i % 4 === 0 ? d.toLocaleDateString('en', { month: 'short', day: 'numeric' }) : '',
        amount: amt,
      };
    });
  }

  const days = period === '7D' ? 7 : 30;
  return Array.from({ length: days }, (_, i) => {
    const d = new Date(); d.setDate(d.getDate() - (days - 1 - i));
    const key = d.toISOString().slice(0, 10);
    const DOW = ['Su', 'Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa'];
    const label = period === '7D' ? DOW[d.getDay()] : (i % 6 === 0 || i === days - 1 ? String(d.getDate()) : '');
    return { label, amount: grouped[key] || 0 };
  });
}

function buildDowSeries(expenses: Expense[]) {
  const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const totals = new Array(7).fill(0);
  expenses.forEach(e => { totals[(new Date(e.date).getDay() + 6) % 7] += e.amount; });
  return DAYS.map((day, i) => ({ day, amount: totals[i] }));
}

/** Smart-grouped trend for a search-result set */
function buildSearchTrendSeries(expenses: Expense[]) {
  if (!expenses.length) return [];
  const sorted = [...expenses].sort((a, b) => a.date.localeCompare(b.date));
  const first = new Date(sorted[0].date);
  first.setHours(0, 0, 0, 0);
  const last  = new Date(sorted[sorted.length - 1].date);
  last.setHours(23, 59, 59, 999);
  const span  = Math.ceil((last.getTime() - first.getTime()) / 86_400_000) + 1;

  if (span <= 62) {
    // daily grouping
    const gd: Record<string, number> = {};
    expenses.forEach(e => { const k = e.date.slice(0, 10); gd[k] = (gd[k] || 0) + e.amount; });
    const result: { label: string; amount: number }[] = [];
    const cur = new Date(first);
    while (cur <= last) {
      const k = cur.toISOString().slice(0, 10);
      result.push({
        label: result.length % 4 === 0
          ? cur.toLocaleDateString('en', { month: 'short', day: 'numeric' })
          : '',
        amount: gd[k] || 0,
      });
      cur.setDate(cur.getDate() + 1);
    }
    return result;
  }
  // monthly grouping
  const mm: Record<string, number> = {};
  expenses.forEach(e => { const m = e.date.slice(0, 7); mm[m] = (mm[m] || 0) + e.amount; });
  return Object.entries(mm).sort(([a], [b]) => a.localeCompare(b)).map(([m, amount]) => ({
    label: new Date(m + '-01').toLocaleDateString('en', { month: 'short', year: '2-digit' }),
    amount,
  }));
}

// ─── Micro-components ─────────────────────────────────────────────────────────

const ChartTip = ({ active, payload, label }: any) => {
  if (!active || !payload?.length) return null;
  return (
    <div style={{
      background: 'rgba(8,3,20,0.97)',
      border: '1px solid rgba(124,58,237,0.45)',
      borderRadius: 12, padding: '8px 14px', fontFamily: F,
      boxShadow: '0 8px 32px rgba(0,0,0,0.6)',
    }}>
      {label && <p style={{ color: 'rgba(255,255,255,0.38)', fontSize: 10, marginBottom: 3 }}>{label}</p>}
      <p style={{ color: '#fff', fontSize: 14, fontWeight: 800 }}>{formatCurrency(payload[0].value)}</p>
    </div>
  );
};

function KPICard({ label, value, sub, accent = '#7C3AED', icon }: {
  label: string; value: string; sub?: string; accent?: string; icon: React.ReactNode;
}) {
  return (
    <motion.div
      className="rounded-2xl p-4 flex flex-col relative overflow-hidden"
      style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', minHeight: 90 }}
      whileTap={{ scale: 0.97 }}
    >
      {/* Corner glow */}
      <div className="absolute top-0 right-0 rounded-full pointer-events-none"
        style={{ width: 70, height: 70, background: `${accent}18`, filter: 'blur(20px)', transform: 'translate(20px,-20px)' }} />
      <div className="flex items-center gap-1.5 mb-2">
        <div className="flex items-center justify-center rounded-lg"
          style={{ width: 22, height: 22, background: `${accent}20`, color: accent }}>
          {icon}
        </div>
        <span style={{ fontSize: 9, fontWeight: 700, color: 'rgba(255,255,255,0.38)', fontFamily: F, letterSpacing: 1.3 }}>
          {label.toUpperCase()}
        </span>
      </div>
      <span style={{ fontSize: 21, fontWeight: 900, color: '#fff', fontFamily: F, letterSpacing: '-0.4px', lineHeight: 1.15 }}>
        {value}
      </span>
      {sub && (
        <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.32)', fontFamily: F, marginTop: 3 }}>{sub}</span>
      )}
    </motion.div>
  );
}

function SectionHead({ title, sub, accent }: { title: string; sub?: string; accent?: string }) {
  return (
    <div className="px-5 mb-4 flex items-end justify-between">
      <div>
        <p style={{ fontSize: 16, fontWeight: 800, color: '#fff', fontFamily: F }}>{title}</p>
        {sub && <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', fontFamily: F, marginTop: 2 }}>{sub}</p>}
      </div>
      {accent && <div className="rounded-full px-2 py-0.5"
        style={{ background: 'rgba(124,58,237,0.15)', border: '1px solid rgba(124,58,237,0.3)' }}>
        <span style={{ fontSize: 9, fontWeight: 700, color: '#A78BFA', fontFamily: F, letterSpacing: 0.8 }}>{accent}</span>
      </div>}
    </div>
  );
}

function ChartCard({ children, accent }: { children: React.ReactNode; accent?: string }) {
  return (
    <div className="mx-5 mb-6 rounded-3xl p-5 relative overflow-hidden"
      style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}>
      {accent && (
        <div className="absolute top-0 right-0 pointer-events-none rounded-full"
          style={{ width: 160, height: 160, background: `${accent}10`, filter: 'blur(40px)', transform: 'translate(40px,-40px)' }} />
      )}
      <div className="relative">{children}</div>
    </div>
  );
}

function TrendDelta({ delta, label }: { delta: number; label?: string }) {
  const up = delta >= 0;
  return (
    <div className="flex items-center gap-1.5 rounded-full px-2.5 py-1"
      style={{ background: up ? 'rgba(248,113,113,0.12)' : 'rgba(52,211,153,0.12)', border: `1px solid ${up ? 'rgba(248,113,113,0.25)' : 'rgba(52,211,153,0.25)'}` }}>
      {up ? <TrendingUp size={11} color="#F87171" /> : <TrendingDown size={11} color="#34D399" />}
      <span style={{ fontSize: 11, fontWeight: 800, color: up ? '#F87171' : '#34D399', fontFamily: F }}>
        {up ? '+' : ''}{delta.toFixed(1)}%{label ? ` ${label}` : ''}
      </span>
    </div>
  );
}

function TxRow({ e, highlight }: { e: Expense; highlight?: string }) {
  const color = CATEGORY_COLORS[e.category] || '#818CF8';
  const icon  = CATEGORY_ICONS[e.category]  || '📦';
  const d     = new Date(e.date);
  const dateS = d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
  const timeS = d.toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' });

  const desc = () => {
    if (!highlight) return (
      <span style={{ fontSize: 14, fontWeight: 700, color: '#fff', fontFamily: F }}>{e.description}</span>
    );
    const q = highlight.toLowerCase();
    const idx = e.description.toLowerCase().indexOf(q);
    if (idx < 0) return <span style={{ fontSize: 14, fontWeight: 700, color: '#fff', fontFamily: F }}>{e.description}</span>;
    return (
      <span style={{ fontSize: 14, fontWeight: 700, fontFamily: F }}>
        <span style={{ color: '#fff' }}>{e.description.slice(0, idx)}</span>
        <span style={{ color: color, background: `${color}25`, borderRadius: 4, padding: '0 3px' }}>
          {e.description.slice(idx, idx + highlight.length)}
        </span>
        <span style={{ color: '#fff' }}>{e.description.slice(idx + highlight.length)}</span>
      </span>
    );
  };

  return (
    <div className="flex items-center gap-3 px-4 py-3.5 relative"
      style={{ borderBottom: '1px solid rgba(255,255,255,0.05)' }}>
      {/* Left category accent line */}
      <div className="absolute left-0 top-3 bottom-3 rounded-full" style={{ width: 3, background: `${color}60` }} />
      <div className="flex items-center justify-center rounded-xl shrink-0"
        style={{ width: 42, height: 42, background: `${color}18`, fontSize: 20 }}>
        {icon}
      </div>
      <div className="flex-1 min-w-0">
        {desc()}
        <div className="flex items-center gap-1.5 mt-0.5 flex-wrap">
          <span style={{ fontSize: 11, fontWeight: 600, color: `${color}cc`, fontFamily: F }}>{e.category}</span>
          <span style={{ color: 'rgba(255,255,255,0.2)', fontSize: 9 }}>●</span>
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.3)', fontFamily: F }}>{dateS}</span>
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.2)', fontFamily: F }}>{timeS}</span>
        </div>
      </div>
      <div className="text-right shrink-0">
        <span style={{ fontSize: 14, fontWeight: 900, color: '#fff', fontFamily: F }}>
          -{formatCurrency(e.amount)}
        </span>
        <p style={{ fontSize: 9, color: 'rgba(255,255,255,0.28)', fontFamily: F, marginTop: 2 }}>{e.bank}</p>
      </div>
    </div>
  );
}

// shared area chart gradient ids
const AG_ID  = 'ag_norm';
const AG2_ID = 'ag_search';
const AG3_ID = 'ag_srch_trend';

// ─── Main ─────────────────────────────────────────────────────────────────────

interface InsightsTabProps { expenses: Expense[]; budget: number; }

export function InsightsTab({ expenses, budget }: InsightsTabProps) {
  const p = usePalette();
  const [query,     setQuery]     = useState('');
  const [period,    setPeriod]    = useState<Period>('7D');
  const [showAll,   setShowAll]   = useState(false);
  const inputRef = useRef<HTMLInputElement>(null);

  const isSearching = query.trim().length > 0;
  const q           = query.trim().toLowerCase();

  // ── Period-filtered ────────────────────────────────────────────────────────
  const periodExp = useMemo(
    () => expenses.filter(e => new Date(e.date) >= cutoff(period)),
    [expenses, period],
  );

  // ── KPIs ──────────────────────────────────────────────────────────────────
  const kpi = useMemo(() => {
    const total = periodExp.reduce((s, e) => s + e.amount, 0);
    let days: number;
    if (period === 'All') {
      if (periodExp.length) {
        const oldest = Math.min(...periodExp.map(e => new Date(e.date).getTime()));
        days = Math.max(1, Math.ceil((Date.now() - oldest) / 86_400_000));
      } else days = 1;
    } else {
      days = period === 'Today' ? 1 : period === '7D' ? 7 : period === '1M' ? 30 : 180;
    }
    const largest = periodExp.length ? Math.max(...periodExp.map(e => e.amount)) : 0;
    return { total, avgDay: total / days, count: periodExp.length, largest };
  }, [periodExp, period]);

  // ── Charts ─────────────────────────────────────────────────────────────────
  const trendData = useMemo(() => buildTrendSeries(periodExp, period), [periodExp, period]);
  const dowData   = useMemo(() => buildDowSeries(periodExp),           [periodExp]);

  const trendDelta = useMemo(() => {
    if (trendData.length < 4) return null;
    const mid = Math.floor(trendData.length / 2);
    const a   = trendData.slice(0, mid).reduce((s, d) => s + d.amount, 0);
    const b   = trendData.slice(mid).reduce((s, d)  => s + d.amount, 0);
    return a > 0 ? ((b - a) / a) * 100 : null;
  }, [trendData]);

  // ── Categories ─────────────────────────────────────────────────────────────
  const catData = useMemo(() => {
    const m: Record<string, number> = {};
    periodExp.forEach(e => { m[e.category] = (m[e.category] || 0) + e.amount; });
    return Object.entries(m)
      .map(([cat, amt]) => ({ cat, amt, pct: kpi.total > 0 ? (amt / kpi.total) * 100 : 0, color: CATEGORY_COLORS[cat] || '#818CF8' }))
      .sort((a, b) => b.amt - a.amt);
  }, [periodExp, kpi.total]);

  // ── Bank ───────────────────────────────────────────────────────────────────
  const bankData = useMemo(() => {
    const m: Record<string, number> = {};
    periodExp.forEach(e => { m[e.bank] = (m[e.bank] || 0) + e.amount; });
    return Object.entries(m).sort(([, a], [, b]) => b - a);
  }, [periodExp]);

  // ── Search ──────────────────────────────────────────────────────────────────
  const searchResults = useMemo(() => {
    if (!q) return [];
    return [...expenses.filter(e =>
      e.description.toLowerCase().includes(q) ||
      e.category.toLowerCase().includes(q) ||
      e.bank.toLowerCase().includes(q)
    )].sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  }, [expenses, q]);

  const searchStats = useMemo(() => {
    if (!searchResults.length) return null;
    const total    = searchResults.reduce((s, e) => s + e.amount, 0);
    const avg      = total / searchResults.length;
    const largest  = Math.max(...searchResults.map(e => e.amount));
    const smallest = Math.min(...searchResults.map(e => e.amount));
    const cats     = [...new Set(searchResults.map(e => e.category))];
    const trend    = buildSearchTrendSeries(searchResults);
    const dow      = buildDowSeries(searchResults);

    // overall trend arrow: earlier half vs later half by date
    const dated = [...searchResults].sort((a, b) => a.date.localeCompare(b.date));
    const mid = Math.floor(dated.length / 2);
    const first = dated.slice(0, mid).reduce((s, e) => s + e.amount, 0);
    const last  = dated.slice(mid).reduce((s, e)  => s + e.amount, 0);
    const delta = first > 0 ? ((last - first) / first) * 100 : 0;

    return { total, avg, largest, smallest, cats, trend, dow, count: searchResults.length, delta };
  }, [searchResults]);

  const sortedPeriodExp = useMemo(
    () => [...periodExp].sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime()),
    [periodExp],
  );

  // ─────────────────────────────────────────────────────────────────────────────

  return (
    <div style={{ background: p.bg, minHeight: '100%', paddingBottom: 32 }}>

      {/* ── Sticky search bar ── */}
      <div className="sticky top-0 z-20 px-5 pt-4 pb-3"
        style={{ background: p.isDark ? 'rgba(0,0,0,0.94)' : 'rgba(248,250,252,0.97)', backdropFilter: 'blur(16px)' }}>
        <motion.div
          className="flex items-center gap-3 rounded-2xl px-4"
          animate={{
            borderColor: isSearching ? 'rgba(124,58,237,0.55)' : 'rgba(255,255,255,0.1)',
            boxShadow: isSearching ? '0 0 0 3px rgba(124,58,237,0.14), 0 4px 24px rgba(124,58,237,0.2)' : 'none',
          }}
          transition={{ duration: 0.2 }}
          style={{ background: 'rgba(255,255,255,0.06)', height: 50, border: '1px solid rgba(255,255,255,0.1)' }}
        >
          <motion.div animate={{ color: isSearching ? '#7C3AED' : 'rgba(255,255,255,0.3)' }} transition={{ duration: 0.2 }}>
            <Search size={16} />
          </motion.div>
          <input
            ref={inputRef}
            value={query}
            onChange={e => setQuery(e.target.value)}
            placeholder="Search merchant, category, bank…"
            style={{ flex: 1, background: 'transparent', border: 'none', outline: 'none', fontSize: 14, color: '#fff', fontFamily: F }}
          />
          <AnimatePresence>
            {isSearching && (
              <motion.button
                initial={{ opacity: 0, scale: 0.5, rotate: -90 }}
                animate={{ opacity: 1, scale: 1, rotate: 0 }}
                exit={{ opacity: 0, scale: 0.5, rotate: 90 }}
                transition={{ type: 'spring', damping: 14, stiffness: 220 }}
                onClick={() => setQuery('')}
                className="flex items-center justify-center rounded-full"
                style={{ width: 22, height: 22, background: 'rgba(255,255,255,0.13)', flexShrink: 0 }}
              >
                <X size={12} color="rgba(255,255,255,0.7)" />
              </motion.button>
            )}
          </AnimatePresence>
        </motion.div>
      </div>

      {/* ── Main content ── */}
      <AnimatePresence mode="wait">

        {/* ══ SEARCH MODE ═══════════════════════════════════════════════════════ */}
        {isSearching ? (
          <motion.div key="search"
            initial={{ opacity: 0, y: 16 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -10 }}
            transition={{ duration: 0.22 }}>

            {/* Header */}
            <div className="px-5 pt-3 pb-5">
              <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.32)', fontFamily: F, letterSpacing: 0.5 }}>
                Showing results for
              </p>
              <h2 style={{ fontSize: 28, fontWeight: 900, color: '#fff', fontFamily: F, letterSpacing: '-0.6px', lineHeight: 1.15 }}>
                "{query}"
              </h2>
              <div className="flex items-center gap-2 mt-2 flex-wrap">
                <motion.span
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  className="rounded-full px-3 py-1"
                  style={{
                    fontSize: 12, fontWeight: 700, fontFamily: F,
                    background: searchResults.length ? 'rgba(124,58,237,0.2)' : 'rgba(248,113,113,0.15)',
                    color: searchResults.length ? '#A78BFA' : '#F87171',
                    border: `1px solid ${searchResults.length ? 'rgba(124,58,237,0.35)' : 'rgba(248,113,113,0.3)'}`,
                  }}
                >
                  {searchResults.length} transaction{searchResults.length !== 1 ? 's' : ''}
                </motion.span>
                {searchStats && <TrendDelta delta={searchStats.delta} />}
              </div>
            </div>

            {searchStats ? (
              <>
                {/* Stats */}
                <div className="grid grid-cols-2 gap-3 px-5 mb-6">
                  <KPICard label="Total Spent"  value={formatCurrency(searchStats.total)}    sub={`${searchStats.count} purchases`}    accent="#7C3AED" icon={<Activity      size={11} />} />
                  <KPICard label="Avg Per Visit" value={formatCurrency(searchStats.avg)}      sub="per transaction"                     accent="#34D399" icon={<Zap           size={11} />} />
                  <KPICard label="Largest"       value={formatCurrency(searchStats.largest)}  sub="single transaction"                  accent="#F59E0B" icon={<TrendingUp    size={11} />} />
                  <KPICard label="Smallest"      value={formatCurrency(searchStats.smallest)} sub="single transaction"                  accent="#818CF8" icon={<TrendingDown  size={11} />} />
                </div>

                {/* Category chips */}
                <div className="px-5 mb-6">
                  <p style={{ fontSize: 9, fontWeight: 700, color: 'rgba(255,255,255,0.3)', fontFamily: F, letterSpacing: 1.5, marginBottom: 10 }}>
                    SPANS CATEGORIES
                  </p>
                  <div className="flex flex-wrap gap-2">
                    {searchStats.cats.map(cat => {
                      const cc  = CATEGORY_COLORS[cat] || '#818CF8';
                      const amt = searchResults.filter(e => e.category === cat).reduce((s, e) => s + e.amount, 0);
                      return (
                        <motion.div key={cat}
                          initial={{ opacity: 0, scale: 0.8 }}
                          animate={{ opacity: 1, scale: 1 }}
                          className="flex items-center gap-1.5 rounded-full px-3 py-1.5"
                          style={{ background: `${cc}15`, border: `1px solid ${cc}30` }}>
                          <span style={{ fontSize: 13 }}>{CATEGORY_ICONS[cat] || '📦'}</span>
                          <span style={{ fontSize: 11, fontWeight: 700, color: cc, fontFamily: F }}>{cat}</span>
                          <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.38)', fontFamily: F }}>
                            {formatCurrency(amt)}
                          </span>
                        </motion.div>
                      );
                    })}
                  </div>
                </div>

                {/* Spending Trend for keyword */}
                {searchStats.trend.length > 1 && (
                  <>
                    <SectionHead
                      title="Spending Trend"
                      sub={`When you spend on "${query}"`}
                      accent="KEYWORD"
                    />
                    <ChartCard accent="#7C3AED">
                      <div className="flex items-end justify-between mb-4">
                        <div>
                          <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', fontFamily: F, marginBottom: 3 }}>
                            Total across all time
                          </p>
                          <p style={{ fontSize: 24, fontWeight: 900, color: '#fff', fontFamily: F, letterSpacing: '-0.4px' }}>
                            {formatCurrency(searchStats.total)}
                          </p>
                        </div>
                        <TrendDelta delta={searchStats.delta} />
                      </div>
                      <ResponsiveContainer width="100%" height={130}>
                        <AreaChart data={searchStats.trend} margin={{ left: -22, right: 4 }}>
                          <defs>
                            <linearGradient id={AG3_ID} x1="0" y1="0" x2="0" y2="1">
                              <stop offset="0%"   stopColor="#7C3AED" stopOpacity={0.55} />
                              <stop offset="100%" stopColor="#7C3AED" stopOpacity={0.02} />
                            </linearGradient>
                          </defs>
                          <XAxis dataKey="label"
                            tick={{ fill: 'rgba(255,255,255,0.3)', fontSize: 9, fontFamily: F }}
                            axisLine={false} tickLine={false} interval="preserveStartEnd" />
                          <Tooltip content={<ChartTip />}
                            cursor={{ stroke: 'rgba(124,58,237,0.35)', strokeWidth: 1, strokeDasharray: '4 4' }} />
                          <Area type="monotone" dataKey="amount"
                            stroke="#7C3AED" strokeWidth={2.5}
                            fill={`url(#${AG3_ID})`} dot={false}
                            activeDot={{ r: 5, fill: '#7C3AED', stroke: '#fff', strokeWidth: 2 }} />
                        </AreaChart>
                      </ResponsiveContainer>
                    </ChartCard>
                  </>
                )}

                {/* Spending by Day for keyword */}
                {(() => {
                  const maxDow = Math.max(...searchStats.dow.map(d => d.amount), 1);
                  const hasData = searchStats.dow.some(d => d.amount > 0);
                  if (!hasData) return null;
                  return (
                    <>
                      <SectionHead
                        title="Spending by Day"
                        sub={`Which days you buy "${query}"`}
                        accent="KEYWORD"
                      />
                      <ChartCard accent="#6366F1">
                        <ResponsiveContainer width="100%" height={120}>
                          <BarChart data={searchStats.dow} margin={{ left: -22, right: 4 }}>
                            <XAxis dataKey="day"
                              tick={{ fill: 'rgba(255,255,255,0.38)', fontSize: 10, fontFamily: F }}
                              axisLine={false} tickLine={false} />
                            <Tooltip content={<ChartTip />}
                              cursor={{ fill: 'rgba(255,255,255,0.04)', radius: 8 }} />
                            <Bar dataKey="amount" radius={[6, 6, 2, 2]} maxBarSize={28}>
                              {searchStats.dow.map((entry, i) => (
                                <Cell key={i}
                                  fill={`rgba(99,102,241,${entry.amount > 0 ? 0.22 + (entry.amount / maxDow) * 0.78 : 0.12})`} />
                              ))}
                            </Bar>
                          </BarChart>
                        </ResponsiveContainer>
                        {/* Busiest day badge */}
                        {(() => {
                          const best = [...searchStats.dow].sort((a, b) => b.amount - a.amount)[0];
                          if (!best.amount) return null;
                          return (
                            <div className="flex items-center gap-2 mt-3 rounded-xl px-3 py-2.5"
                              style={{ background: 'rgba(99,102,241,0.12)', border: '1px solid rgba(99,102,241,0.22)' }}>
                              <Sparkles size={12} color="#818CF8" />
                              <p style={{ fontSize: 11, fontWeight: 700, color: '#A5B4FC', fontFamily: F }}>
                                You buy "{query}" most on <span style={{ color: '#fff' }}>{best.day}</span>s — {formatCurrency(best.amount)} total
                              </p>
                            </div>
                          );
                        })()}
                      </ChartCard>
                    </>
                  );
                })()}

                {/* All matches */}
                <SectionHead
                  title="All Matches"
                  sub={`${searchResults.length} transactions · newest first`}
                />
                <div className="mx-5 rounded-2xl overflow-hidden mb-4"
                  style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.07)' }}>
                  {searchResults.map((e, i) => (
                    <motion.div key={e.id}
                      initial={{ opacity: 0, x: -10 }}
                      animate={{ opacity: 1, x: 0 }}
                      transition={{ delay: Math.min(i * 0.03, 0.35), duration: 0.2 }}>
                      <TxRow e={e} highlight={query} />
                    </motion.div>
                  ))}
                </div>

                {/* Grand total footer */}
                <motion.div
                  className="mx-5 mb-2 rounded-2xl px-5 py-4 flex items-center justify-between"
                  initial={{ opacity: 0, y: 8 }}
                  animate={{ opacity: 1, y: 0 }}
                  transition={{ delay: 0.15 }}
                  style={{ background: 'linear-gradient(135deg,rgba(124,58,237,0.18),rgba(99,102,241,0.12))', border: '1px solid rgba(124,58,237,0.3)' }}
                >
                  <div className="flex items-center gap-2">
                    <Sparkles size={14} color="#A78BFA" />
                    <span style={{ fontSize: 13, fontWeight: 700, color: '#A78BFA', fontFamily: F }}>
                      Grand total · "{query}"
                    </span>
                  </div>
                  <span style={{ fontSize: 17, fontWeight: 900, color: '#fff', fontFamily: F }}>
                    {formatCurrency(searchStats.total)}
                  </span>
                </motion.div>
              </>
            ) : (
              <div className="flex flex-col items-center py-24 px-8">
                <motion.span
                  animate={{ scale: [1, 1.08, 1] }}
                  transition={{ duration: 2, repeat: Infinity }}
                  style={{ fontSize: 52, display: 'block', marginBottom: 16 }}>🔍</motion.span>
                <p style={{ fontSize: 16, fontWeight: 800, color: 'rgba(255,255,255,0.5)', fontFamily: F, textAlign: 'center' }}>
                  No results for "{query}"
                </p>
                <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.26)', fontFamily: F, textAlign: 'center', marginTop: 6, lineHeight: 1.7 }}>
                  Try a merchant name, a category like "Food" or "Bills", or a bank like "HDFC"
                </p>
              </div>
            )}
          </motion.div>

        ) : (

          /* ══ INSIGHTS MODE ════════════════════════════════════════════════════ */
          <motion.div key="normal"
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -8 }}
            transition={{ duration: 0.22 }}>

            {/* Period pills */}
            <div className="flex gap-2 px-5 pt-2 pb-5 overflow-x-auto" style={{ scrollbarWidth: 'none' }}>
              {PERIODS.map(p => (
                <motion.button key={p}
                  whileTap={{ scale: 0.88 }}
                  onClick={() => { setPeriod(p); setShowAll(false); }}
                  className="rounded-full px-5 py-2 shrink-0 relative"
                  style={{ fontFamily: F, fontSize: 13, fontWeight: 700, cursor: 'pointer', border: 'none', outline: 'none' }}
                  animate={{
                    background: period === p ? '#7C3AED' : 'rgba(255,255,255,0.07)',
                    color: period === p ? '#fff' : 'rgba(255,255,255,0.48)',
                    boxShadow: period === p ? '0 4px 20px rgba(124,58,237,0.5), 0 0 0 1px rgba(124,58,237,0.3)' : '0 0 0 1px rgba(255,255,255,0.1)',
                  }}
                  transition={{ duration: 0.18 }}
                >
                  {p}
                </motion.button>
              ))}
            </div>

            {/* KPI grid */}
            <div className="grid grid-cols-2 gap-3 px-5 mb-6">
              <KPICard label="Total Spent"   value={formatCurrency(kpi.total)}   sub={`${kpi.count} transactions`}              accent="#7C3AED" icon={<Activity     size={11} />} />
              <KPICard label="Avg / Day"     value={formatCurrency(kpi.avgDay)}  sub={PERIOD_LABEL[period]}                     accent="#34D399" icon={<Calendar     size={11} />} />
              <KPICard label="Transactions"  value={String(kpi.count)}           sub={PERIOD_LABEL[period]}                     accent="#818CF8" icon={<Hash          size={11} />} />
              <KPICard label="Biggest"       value={kpi.largest ? formatCurrency(kpi.largest) : '—'} sub="single expense"     accent="#F59E0B" icon={<TrendingUp    size={11} />} />
            </div>

            {/* Budget bar */}
            {budget > 0 && (() => {
              const pct  = Math.min((kpi.total / budget) * 100, 100);
              const over = kpi.total > budget;
              const warn = !over && pct > 75;
              return (
                <div className="mx-5 mb-6 rounded-3xl p-5 relative overflow-hidden"
                  style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}>
                  <div className="absolute top-0 right-0 rounded-full pointer-events-none"
                    style={{ width: 120, height: 120, background: over ? 'rgba(239,68,68,0.12)' : 'rgba(52,211,153,0.1)', filter: 'blur(30px)', transform: 'translate(30px,-30px)' }} />
                  <div className="relative">
                    <div className="flex items-center justify-between mb-3">
                      <span style={{ fontSize: 13, fontWeight: 800, color: '#fff', fontFamily: F }}>Budget Progress</span>
                      <span style={{ fontSize: 14, fontWeight: 900, fontFamily: F, color: over ? '#F87171' : warn ? '#F59E0B' : '#34D399' }}>
                        {pct.toFixed(0)}%
                      </span>
                    </div>
                    <div className="rounded-full overflow-hidden" style={{ height: 9, background: 'rgba(255,255,255,0.08)' }}>
                      <motion.div className="h-full rounded-full"
                        style={{ background: over ? 'linear-gradient(90deg,#F87171,#EF4444)' : warn ? 'linear-gradient(90deg,#F59E0B,#FBBF24)' : 'linear-gradient(90deg,#7C3AED,#34D399)' }}
                        initial={{ width: 0 }}
                        animate={{ width: `${pct}%` }}
                        transition={{ duration: 0.9, ease: [0.34, 1.1, 0.64, 1] }}
                      />
                    </div>
                    <div className="flex justify-between mt-2.5">
                      <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.36)', fontFamily: F }}>{formatCurrency(kpi.total)} spent</span>
                      <span style={{ fontSize: 11, fontFamily: F, color: over ? '#F87171' : 'rgba(255,255,255,0.36)' }}>
                        {over ? `${formatCurrency(kpi.total - budget)} over` : `${formatCurrency(budget - kpi.total)} left`}
                      </span>
                    </div>
                  </div>
                </div>
              );
            })()}

            {/* Spending Trend */}
            <SectionHead
              title="Spending Trend"
              sub={period === 'All' ? 'Monthly totals · all time' : `Daily totals · ${PERIOD_LABEL[period]}`}
            />
            <ChartCard accent="#7C3AED">
              <div className="flex items-end gap-3 mb-5">
                <span style={{ fontSize: 28, fontWeight: 900, color: '#fff', fontFamily: F, letterSpacing: '-0.6px' }}>
                  {formatCurrency(kpi.total)}
                </span>
                {trendDelta !== null && <TrendDelta delta={trendDelta} />}
              </div>
              <ResponsiveContainer width="100%" height={140}>
                <AreaChart data={trendData} margin={{ left: -22, right: 4 }}>
                  <defs>
                    <linearGradient id={AG_ID} x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%"   stopColor="#7C3AED" stopOpacity={0.55} />
                      <stop offset="100%" stopColor="#7C3AED" stopOpacity={0.02} />
                    </linearGradient>
                  </defs>
                  <XAxis dataKey="label"
                    tick={{ fill: 'rgba(255,255,255,0.3)', fontSize: 9, fontFamily: F }}
                    axisLine={false} tickLine={false} interval="preserveStartEnd" />
                  <Tooltip content={<ChartTip />}
                    cursor={{ stroke: 'rgba(124,58,237,0.35)', strokeWidth: 1, strokeDasharray: '4 4' }} />
                  <Area type="monotone" dataKey="amount"
                    stroke="#7C3AED" strokeWidth={2.5}
                    fill={`url(#${AG_ID})`} dot={false}
                    activeDot={{ r: 5, fill: '#7C3AED', stroke: '#fff', strokeWidth: 2 }} />
                </AreaChart>
              </ResponsiveContainer>
            </ChartCard>

            {/* Spending by Day */}
            <SectionHead title="Spending by Day" sub="Your weekly spending pattern" />
            <ChartCard accent="#6366F1">
              {(() => {
                const maxAmt = Math.max(...dowData.map(d => d.amount), 1);
                const best   = [...dowData].sort((a, b) => b.amount - a.amount)[0];
                return (
                  <>
                    <ResponsiveContainer width="100%" height={120}>
                      <BarChart data={dowData} margin={{ left: -22, right: 4 }}>
                        <XAxis dataKey="day"
                          tick={{ fill: 'rgba(255,255,255,0.36)', fontSize: 10, fontFamily: F }}
                          axisLine={false} tickLine={false} />
                        <Tooltip content={<ChartTip />}
                          cursor={{ fill: 'rgba(255,255,255,0.04)', radius: 8 }} />
                        <Bar dataKey="amount" radius={[6, 6, 2, 2]} maxBarSize={28}>
                          {dowData.map((entry, i) => (
                            <Cell key={i}
                              fill={`rgba(99,102,241,${entry.amount > 0 ? 0.22 + (entry.amount / maxAmt) * 0.78 : 0.1})`} />
                          ))}
                        </Bar>
                      </BarChart>
                    </ResponsiveContainer>
                    {best.amount > 0 && (
                      <div className="flex items-center gap-2 mt-3 rounded-xl px-3 py-2.5"
                        style={{ background: 'rgba(99,102,241,0.1)', border: '1px solid rgba(99,102,241,0.2)' }}>
                        <Sparkles size={12} color="#818CF8" />
                        <p style={{ fontSize: 11, fontWeight: 700, color: '#A5B4FC', fontFamily: F }}>
                          Highest spending on <span style={{ color: '#fff' }}>{best.day}</span>s — {formatCurrency(best.amount)} total
                        </p>
                      </div>
                    )}
                  </>
                );
              })()}
            </ChartCard>

            {/* By Category */}
            <SectionHead
              title="By Category"
              sub={`${catData.length} categor${catData.length !== 1 ? 'ies' : 'y'} · ${PERIOD_LABEL[period]}`}
            />
            <div className="mx-5 mb-6 rounded-3xl overflow-hidden"
              style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)' }}>
              {catData.length === 0 ? (
                <div className="py-10 flex items-center justify-center">
                  <p style={{ color: 'rgba(255,255,255,0.28)', fontFamily: F, fontSize: 13 }}>No expenses this period</p>
                </div>
              ) : catData.map((item, i) => (
                <motion.div key={item.cat} className="px-5 py-4"
                  style={{ borderBottom: i < catData.length - 1 ? '1px solid rgba(255,255,255,0.05)' : 'none' }}
                  initial={{ opacity: 0, x: -8 }}
                  animate={{ opacity: 1, x: 0 }}
                  transition={{ delay: i * 0.04 }}
                >
                  <div className="flex items-center justify-between mb-2.5">
                    <div className="flex items-center gap-2.5">
                      <div className="flex items-center justify-center rounded-xl"
                        style={{ width: 38, height: 38, background: `${item.color}18`, fontSize: 19 }}>
                        {CATEGORY_ICONS[item.cat] || '📦'}
                      </div>
                      <div>
                        <p style={{ fontSize: 13, fontWeight: 700, color: '#fff', fontFamily: F }}>{item.cat}</p>
                        <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.32)', fontFamily: F, marginTop: 1 }}>
                          {periodExp.filter(e => e.category === item.cat).length} transactions
                        </p>
                      </div>
                    </div>
                    <div className="text-right">
                      <p style={{ fontSize: 15, fontWeight: 900, color: '#fff', fontFamily: F }}>{formatCurrency(item.amt)}</p>
                      <p style={{ fontSize: 10, color: `${item.color}cc`, fontFamily: F, marginTop: 1, fontWeight: 700 }}>
                        {item.pct.toFixed(1)}%
                      </p>
                    </div>
                  </div>
                  <div className="rounded-full overflow-hidden" style={{ height: 5, background: 'rgba(255,255,255,0.07)' }}>
                    <motion.div className="h-full rounded-full" style={{ background: item.color }}
                      initial={{ width: 0 }}
                      animate={{ width: `${item.pct}%` }}
                      transition={{ duration: 0.7, delay: i * 0.055, ease: 'easeOut' }}
                    />
                  </div>
                </motion.div>
              ))}
            </div>

            {/* By Bank */}
            {bankData.length > 0 && (
              <>
                <SectionHead title="By Bank" sub="Spending source breakdown" />
                <div className="flex gap-3 px-5 mb-6 overflow-x-auto" style={{ scrollbarWidth: 'none' }}>
                  {bankData.map(([bank, amt]) => (
                    <div key={bank} className="rounded-2xl p-4 shrink-0 relative overflow-hidden"
                      style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', minWidth: 140 }}>
                      <div className="absolute top-0 right-0 rounded-full pointer-events-none"
                        style={{ width: 70, height: 70, background: 'rgba(124,58,237,0.12)', filter: 'blur(16px)', transform: 'translate(20px,-20px)' }} />
                      <p style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.38)', fontFamily: F, marginBottom: 8 }}>
                        🏦 {bank}
                      </p>
                      <p style={{ fontSize: 19, fontWeight: 900, color: '#fff', fontFamily: F }}>{formatCurrency(amt)}</p>
                      <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.28)', fontFamily: F, marginTop: 4 }}>
                        {kpi.total > 0 ? ((amt / kpi.total) * 100).toFixed(1) : 0}% of total
                      </p>
                    </div>
                  ))}
                </div>
              </>
            )}

            {/* Transactions */}
            <SectionHead
              title="Transactions"
              sub={`${sortedPeriodExp.length} total · newest first`}
            />
            <div className="mx-5 rounded-2xl overflow-hidden"
              style={{ background: 'rgba(255,255,255,0.03)', border: '1px solid rgba(255,255,255,0.07)' }}>
              {sortedPeriodExp.length === 0 ? (
                <div className="py-16 flex flex-col items-center gap-3">
                  <span style={{ fontSize: 40 }}>📭</span>
                  <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.3)', fontFamily: F }}>
                    No transactions {PERIOD_LABEL[period]}
                  </p>
                </div>
              ) : (
                (showAll ? sortedPeriodExp : sortedPeriodExp.slice(0, 5)).map(e => (
                  <TxRow key={e.id} e={e} />
                ))
              )}
            </div>

            {sortedPeriodExp.length > 5 && (
              <motion.button
                whileTap={{ scale: 0.96 }}
                onClick={() => setShowAll(v => !v)}
                className="flex items-center justify-center gap-2 mx-5 mt-3 py-3.5 rounded-2xl"
                style={{
                  width: 'calc(100% - 40px)',
                  background: 'rgba(124,58,237,0.1)', border: '1px solid rgba(124,58,237,0.22)',
                  fontSize: 13, fontWeight: 700, color: '#A78BFA', fontFamily: F, cursor: 'pointer',
                }}
              >
                {showAll
                  ? <><ChevronUp   size={14} /> Show less</>
                  : <><ChevronDown size={14} /> Show all {sortedPeriodExp.length} transactions</>
                }
              </motion.button>
            )}
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}