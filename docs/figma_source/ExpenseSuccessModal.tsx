import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Check, Sparkles, Brain, Plus } from 'lucide-react';
import { CATEGORY_COLORS, CATEGORY_ICONS } from '../../types/expense';
import { formatCurrency } from '../../utils/categoryUtils';

const font = "'Plus Jakarta Sans', sans-serif";

export type SuccessConfidence = 'learned' | 'matched' | 'default' | 'manual';

export interface SuccessMeta {
  confidence: SuccessConfidence;
  reasoning: string;
  capturedImageUrl: string | null;
}

export interface SuccessExpense {
  amount: number;
  description: string;
  category: string;
  bank: string;
  cardType: string;
}

interface Props {
  open: boolean;
  expense: SuccessExpense | null;
  meta: SuccessMeta | null;
  budget: number;
  totalSpent: number; // month total INCLUDING this expense
  onAddAnother: () => void;
  onDone: () => void;
}

const CONF: Record<SuccessConfidence, { label: string; score: string | null; color: string; bg: string; Icon: typeof Sparkles }> = {
  learned: { label: 'AI Remembered',   score: '97', color: '#818CF8', bg: 'rgba(129,140,248,0.15)', Icon: Brain     },
  matched: { label: 'AI Detected',     score: '82', color: '#34D399', bg: 'rgba(52,211,153,0.12)',  Icon: Sparkles  },
  default: { label: 'Low Confidence',  score: '30', color: '#F59E0B', bg: 'rgba(245,158,11,0.12)',  Icon: Sparkles  },
  manual:  { label: 'Manual Override', score: null, color: '#FBBF24', bg: 'rgba(251,191,36,0.12)',  Icon: Sparkles  },
};

export function ExpenseSuccessModal({ open, expense, meta, budget, totalSpent, onAddAnother, onDone }: Props) {
  const [phase, setPhase] = useState(0);

  useEffect(() => {
    if (!open) { setPhase(0); return; }
    const t = [
      setTimeout(() => setPhase(1), 120),   // ring draws
      setTimeout(() => setPhase(2), 720),   // check appears
      setTimeout(() => setPhase(3), 1020),  // title
      setTimeout(() => setPhase(4), 1280),  // summary card
      setTimeout(() => setPhase(5), 1520),  // impact + buttons
    ];
    return () => t.forEach(clearTimeout);
  }, [open]);

  if (!expense || !meta) return null;

  const catColor = CATEGORY_COLORS[expense.category] || '#818CF8';
  const catIcon  = CATEGORY_ICONS[expense.category]  || '📦';
  const conf     = CONF[meta.confidence] ?? CONF.matched;
  const ConfIcon = conf.Icon;

  const remaining      = budget > 0 ? budget - totalSpent : 0;
  const thisExpensePct = budget > 0 ? (expense.amount / budget) * 100 : 0;
  const usedPct        = budget > 0 ? Math.min((totalSpent / budget) * 100, 100) : 0;
  const overBudget     = budget > 0 && remaining < 0;

  return (
    <AnimatePresence>
      {open && (
        <motion.div
          className="fixed inset-0 z-[60] flex flex-col"
          style={{ background: '#000', maxWidth: 430, margin: '0 auto' }}
          initial={{ y: '100%' }}
          animate={{ y: 0 }}
          exit={{ y: '100%' }}
          transition={{ type: 'spring', damping: 28, stiffness: 260 }}
        >
          {/* Purple radial gradient layers — matches Figma vibe */}
          <div className="absolute inset-0 pointer-events-none" style={{
            background: [
              'radial-gradient(ellipse 90% 55% at 50% -5%, rgba(124,58,237,0.28) 0%, transparent 65%)',
              'radial-gradient(ellipse 60% 40% at 0% 100%, rgba(99,102,241,0.14) 0%, transparent 55%)',
            ].join(', '),
          }} />

          {/* Scrollable body */}
          <div className="relative flex-1 overflow-y-auto">

            {/* ── Top bar ── */}
            <div className="flex items-center justify-between px-5 pt-4 pb-2">
              <motion.button
                whileTap={{ scale: 0.88 }}
                onClick={onDone}
                className="flex items-center justify-center rounded-full"
                style={{ width: 38, height: 38, background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.12)' }}
              >
                <X size={16} color="rgba(255,255,255,0.65)" />
              </motion.button>
              <span style={{ fontSize: 12, fontWeight: 700, color: 'rgba(255,255,255,0.5)', fontFamily: font, letterSpacing: 2.5 }}>
                SUCCESS
              </span>
              <div style={{ width: 38 }} />
            </div>

            {/* ── Hero: animated glowing ring + checkmark ── */}
            <div className="flex flex-col items-center pt-6 pb-6 px-6">
              <div className="relative flex items-center justify-center mb-7" style={{ width: 148, height: 148 }}>

                {/* Pulsing outer glow */}
                <motion.div
                  className="absolute rounded-full"
                  style={{
                    width: 210, height: 210,
                    left: '50%', top: '50%',
                    x: '-50%', y: '-50%',
                    background: 'radial-gradient(circle, rgba(124,58,237,0.32) 0%, transparent 68%)',
                  }}
                  animate={phase >= 2
                    ? { scale: [1, 1.14, 1], opacity: [0.5, 0.85, 0.5] }
                    : { scale: 1, opacity: 0 }}
                  transition={{ duration: 2.6, repeat: Infinity, ease: 'easeInOut' }}
                />

                {/* SVG animated ring */}
                <svg className="absolute inset-0 w-full h-full" viewBox="0 0 148 148"
                  style={{ transform: 'rotate(-90deg)' }}>
                  {/* Track */}
                  <circle cx="74" cy="74" r="64" stroke="rgba(124,58,237,0.14)" strokeWidth="1.5" fill="none" />
                  {/* Animated fill */}
                  <motion.circle
                    cx="74" cy="74" r="64"
                    stroke="url(#ringGrad)"
                    strokeWidth="3"
                    fill="none"
                    strokeLinecap="round"
                    initial={{ pathLength: 0, opacity: 0 }}
                    animate={{ pathLength: phase >= 1 ? 1 : 0, opacity: phase >= 1 ? 1 : 0 }}
                    transition={{ duration: 0.85, ease: [0.4, 0, 0.2, 1] }}
                  />
                  <defs>
                    <linearGradient id="ringGrad" x1="0%" y1="0%" x2="100%" y2="0%">
                      <stop offset="0%" stopColor="#6366F1" />
                      <stop offset="100%" stopColor="#7C3AED" />
                    </linearGradient>
                  </defs>
                </svg>

                {/* Dark circle fill */}
                <div className="absolute rounded-full"
                  style={{
                    inset: 10,
                    background: 'rgba(6,0,18,0.88)',
                    boxShadow: 'inset 0 0 32px rgba(124,58,237,0.18)',
                  }}
                />

                {/* Checkmark */}
                <motion.div
                  className="relative z-10 flex items-center justify-center"
                  initial={{ scale: 0, opacity: 0 }}
                  animate={phase >= 2 ? { scale: 1, opacity: 1 } : { scale: 0, opacity: 0 }}
                  transition={{ type: 'spring', damping: 9, stiffness: 190, delay: 0.05 }}
                >
                  <Check size={50} color="#7C3AED" strokeWidth={3} />
                </motion.div>
              </div>

              {/* Title + subtitle */}
              <motion.div
                className="flex flex-col items-center gap-2"
                initial={{ opacity: 0, y: 18 }}
                animate={phase >= 3 ? { opacity: 1, y: 0 } : { opacity: 0, y: 18 }}
                transition={{ duration: 0.42, ease: 'easeOut' }}
              >
                <h1 style={{ fontSize: 30, fontWeight: 900, color: '#fff', fontFamily: font, letterSpacing: '-0.6px', textAlign: 'center' }}>
                  Expense Logged
                </h1>
                <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.42)', fontFamily: font, textAlign: 'center', lineHeight: 1.65, maxWidth: 260 }}>
                  AI has successfully analyzed and categorized your transaction.
                </p>
              </motion.div>
            </div>

            {/* ── Summary Card ── */}
            <motion.div
              className="mx-5 mb-4 rounded-3xl relative overflow-hidden"
              style={{
                background: 'rgba(255,255,255,0.035)',
                border: '1px solid rgba(255,255,255,0.1)',
                backdropFilter: 'blur(16px)',
              }}
              initial={{ opacity: 0, y: 28 }}
              animate={phase >= 4 ? { opacity: 1, y: 0 } : { opacity: 0, y: 28 }}
              transition={{ duration: 0.42, ease: 'easeOut' }}
            >
              {/* Top-right glow blob */}
              <div className="absolute top-[-50px] right-[-50px] rounded-full pointer-events-none"
                style={{ width: 130, height: 130, background: 'rgba(124,58,237,0.18)', filter: 'blur(35px)' }} />

              <div className="relative p-5">
                {/* Category + thumbnail */}
                <div className="flex items-start justify-between gap-4 mb-5">
                  <div className="flex-1 min-w-0">
                    <p style={{ fontSize: 10, fontWeight: 700, color: catColor, fontFamily: font, letterSpacing: 1.8, marginBottom: 6 }}>
                      CATEGORY
                    </p>
                    <p style={{ fontSize: 22, fontWeight: 900, color: '#fff', fontFamily: font, lineHeight: 1.2 }}>
                      {expense.category}
                    </p>
                  </div>
                  {/* Thumbnail: scanned image OR category emoji */}
                  <div className="rounded-2xl overflow-hidden shrink-0"
                    style={{ width: 88, height: 88, background: `${catColor}12`, border: '1px solid rgba(255,255,255,0.1)' }}>
                    {meta.capturedImageUrl ? (
                      <>
                        <img src={meta.capturedImageUrl} alt="Bill" className="w-full h-full object-cover" />
                        {/* Desaturation overlay — like Figma's mix-blend saturation */}
                        <div className="absolute inset-0" style={{ background: 'rgba(255,255,255,0.08)', mixBlendMode: 'saturation' }} />
                      </>
                    ) : (
                      <div className="w-full h-full flex items-center justify-center" style={{ fontSize: 42 }}>
                        {catIcon}
                      </div>
                    )}
                  </div>
                </div>

                {/* Amount | Merchant */}
                <div className="flex items-center gap-4 mb-5">
                  <div className="flex-1">
                    <p style={{ fontSize: 9, fontWeight: 700, color: 'rgba(255,255,255,0.35)', fontFamily: font, letterSpacing: 1.4, marginBottom: 5 }}>
                      AMOUNT
                    </p>
                    <p style={{ fontSize: 24, fontWeight: 900, color: '#fff', fontFamily: font, letterSpacing: '-0.3px' }}>
                      {formatCurrency(expense.amount)}
                    </p>
                  </div>
                  <div style={{ width: 1, height: 38, background: 'rgba(255,255,255,0.1)', flexShrink: 0 }} />
                  <div className="flex-1 min-w-0">
                    <p style={{ fontSize: 9, fontWeight: 700, color: 'rgba(255,255,255,0.35)', fontFamily: font, letterSpacing: 1.4, marginBottom: 5 }}>
                      MERCHANT
                    </p>
                    <p style={{ fontSize: 14, fontWeight: 700, color: '#fff', fontFamily: font, lineHeight: 1.35, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {expense.description}
                    </p>
                  </div>
                </div>

                {/* Bank + card pills */}
                <div className="flex gap-2 mb-5 flex-wrap">
                  <span className="rounded-full px-3 py-1"
                    style={{ fontSize: 10, fontWeight: 700, color: '#A78BFA', background: 'rgba(124,58,237,0.18)', fontFamily: font }}>
                    🏦 {expense.bank}
                  </span>
                  <span className="rounded-full px-3 py-1"
                    style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.5)', background: 'rgba(255,255,255,0.07)', fontFamily: font }}>
                    {expense.cardType === 'Cash' ? '💵' : expense.cardType === 'Credit Card' ? '💳' : '🏦'} {expense.cardType}
                  </span>
                </div>

                {/* AI confidence pill */}
                <motion.div
                  className="flex items-center gap-2 rounded-full px-4 py-2"
                  style={{
                    background: conf.bg,
                    border: `1px solid ${conf.color}35`,
                    display: 'inline-flex',
                  }}
                  initial={{ scale: 0.85, opacity: 0 }}
                  animate={phase >= 4 ? { scale: 1, opacity: 1 } : {}}
                  transition={{ delay: 0.2, type: 'spring', damping: 14 }}
                >
                  <ConfIcon size={11} color={conf.color} />
                  <span style={{ fontSize: 10, fontWeight: 700, color: conf.color, fontFamily: font, letterSpacing: 0.8 }}>
                    {conf.label.toUpperCase()}
                    {conf.score ? ` • ${conf.score}% CONFIDENCE` : ''}
                  </span>
                </motion.div>

                {/* Reasoning text */}
                {meta.reasoning && (
                  <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.25)', fontFamily: font, marginTop: 8, lineHeight: 1.5 }}>
                    {meta.reasoning}
                  </p>
                )}
              </div>
            </motion.div>

            {/* ── Budget Impact cards ── */}
            <motion.div
              className="mx-5 mb-4 grid grid-cols-2 gap-3"
              initial={{ opacity: 0, y: 16 }}
              animate={phase >= 5 ? { opacity: 1, y: 0 } : { opacity: 0, y: 16 }}
              transition={{ duration: 0.35 }}
            >
              {/* Budget Impact */}
              <div className="rounded-2xl p-4"
                style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', backdropFilter: 'blur(10px)' }}>
                <p style={{ fontSize: 11, fontWeight: 500, color: 'rgba(255,255,255,0.4)', fontFamily: font, marginBottom: 7 }}>
                  Budget Impact
                </p>
                <div className="flex items-baseline gap-1.5 flex-wrap">
                  <span style={{ fontSize: 21, fontWeight: 900, fontFamily: font, color: overBudget ? '#F87171' : '#fff' }}>
                    {budget > 0 ? `-${thisExpensePct.toFixed(1)}%` : 'N/A'}
                  </span>
                  {budget > 0 && (
                    <span style={{ fontSize: 10, fontWeight: 700, color: usedPct > 85 ? '#F87171' : '#F59E0B', fontFamily: font }}>
                      {usedPct.toFixed(0)}% used
                    </span>
                  )}
                </div>
              </div>

              {/* Remaining / Balance */}
              <div className="rounded-2xl p-4"
                style={{ background: 'rgba(255,255,255,0.04)', border: '1px solid rgba(255,255,255,0.08)', backdropFilter: 'blur(10px)' }}>
                <p style={{ fontSize: 11, fontWeight: 500, color: 'rgba(255,255,255,0.4)', fontFamily: font, marginBottom: 7 }}>
                  {budget > 0 ? 'Remaining' : 'Total Logged'}
                </p>
                <div className="flex items-baseline gap-1.5 flex-wrap">
                  <span style={{ fontSize: 21, fontWeight: 900, fontFamily: font, color: overBudget ? '#F87171' : '#fff' }}>
                    {formatCurrency(budget > 0 ? remaining : totalSpent)}
                  </span>
                  {budget > 0 && (
                    <span style={{ fontSize: 10, fontWeight: 700, color: overBudget ? '#F87171' : '#34D399', fontFamily: font }}>
                      {overBudget ? 'Over' : 'Left'}
                    </span>
                  )}
                </div>
              </div>
            </motion.div>

            {/* ── Action buttons ── */}
            <motion.div
              className="mx-5 mb-10 flex flex-col gap-3"
              initial={{ opacity: 0, y: 12 }}
              animate={phase >= 5 ? { opacity: 1, y: 0 } : { opacity: 0, y: 12 }}
              transition={{ duration: 0.3, delay: 0.12 }}
            >
              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={onAddAnother}
                className="w-full py-4 rounded-2xl flex items-center justify-center gap-2"
                style={{
                  background: 'linear-gradient(135deg, #7C3AED, #6366F1)',
                  boxShadow: '0 8px 28px rgba(124,58,237,0.45)',
                  fontSize: 15, fontWeight: 800, color: '#fff', fontFamily: font,
                  letterSpacing: 0.2,
                }}
              >
                <Plus size={18} color="#fff" strokeWidth={2.5} />
                Add Another Expense
              </motion.button>

              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={onDone}
                className="w-full py-4 rounded-2xl flex items-center justify-center"
                style={{
                  background: 'rgba(255,255,255,0.05)',
                  border: '1px solid rgba(255,255,255,0.12)',
                  backdropFilter: 'blur(10px)',
                  fontSize: 15, fontWeight: 700, color: 'rgba(255,255,255,0.65)', fontFamily: font,
                }}
              >
                Go to Dashboard
              </motion.button>
            </motion.div>

          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}
