import { useState, useRef } from 'react';
import { motion, useMotionValue, animate } from 'motion/react';
import { Trash2, Pencil } from 'lucide-react';
import type { Expense } from '../../types/expense';
import { CATEGORY_COLORS, CATEGORY_ICONS, BANK_COLORS } from '../../types/expense';
import { formatCurrency, formatTime } from '../../utils/categoryUtils';

const REVEAL_WIDTH = 130;
const font = "'Plus Jakarta Sans', sans-serif";

interface ExpenseItemProps {
  expense: Expense;
  onDelete: (id: string) => void;
  onEdit: (expense: Expense) => void;
  index: number;
}

export function ExpenseItem({ expense, onDelete, onEdit, index }: ExpenseItemProps) {
  const color = CATEGORY_COLORS[expense.category] || '#868E96';
  const icon = CATEGORY_ICONS[expense.category] || '📦';
  const bankColor = BANK_COLORS[expense.bank] || '#555';

  const x = useMotionValue(0);
  const [revealed, setRevealed] = useState(false);
  const touchRef = useRef<{ startX: number; startY: number; locked: 'h' | 'v' | null } | null>(null);

  const snapOpen = () => {
    animate(x, -REVEAL_WIDTH, { type: 'spring', stiffness: 380, damping: 38 });
    setRevealed(true);
  };

  const snapClose = () => {
    animate(x, 0, { type: 'spring', stiffness: 380, damping: 38 });
    setRevealed(false);
  };

  const handleTouchStart = (e: React.TouchEvent) => {
    touchRef.current = { startX: e.touches[0].clientX, startY: e.touches[0].clientY, locked: null };
  };

  const handleTouchMove = (e: React.TouchEvent) => {
    if (!touchRef.current) return;
    const dx = e.touches[0].clientX - touchRef.current.startX;
    const dy = e.touches[0].clientY - touchRef.current.startY;

    if (!touchRef.current.locked) {
      if (Math.abs(dx) > 6 && Math.abs(dx) > Math.abs(dy)) touchRef.current.locked = 'h';
      else if (Math.abs(dy) > 6) { touchRef.current = null; return; }
      else return;
    }

    if (touchRef.current.locked === 'h') {
      const base = revealed ? -REVEAL_WIDTH : 0;
      x.set(Math.max(-REVEAL_WIDTH, Math.min(0, base + dx)));
    }
  };

  const handleTouchEnd = (e: React.TouchEvent) => {
    if (!touchRef.current || touchRef.current.locked !== 'h') { touchRef.current = null; return; }
    const dx = e.changedTouches[0].clientX - touchRef.current.startX;
    touchRef.current = null;
    if (revealed) { dx > 30 ? snapClose() : snapOpen(); }
    else { dx < -48 ? snapOpen() : snapClose(); }
  };

  return (
    // Outer wrapper — handles ONLY entrance animation (NOT overflow-hidden, because
    // animated transforms break overflow clipping in some browsers)
    <motion.div
      initial={{ opacity: 0, y: 14 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -6, transition: { duration: 0.18 } }}
      transition={{ duration: 0.26, delay: index * 0.04, ease: 'easeOut' }}
    >
      {/* Clipping container — non-animated so overflow-hidden works reliably */}
      <div className="relative rounded-2xl overflow-hidden">

        {/* ── Action panel (hidden behind main content at x=0) ── */}
        <div
          className="absolute right-0 top-0 bottom-0 flex items-stretch"
          style={{ width: REVEAL_WIDTH }}
        >
          {/* Edit */}
          <motion.button
            whileTap={{ scale: 0.88 }}
            onClick={() => { snapClose(); setTimeout(() => onEdit(expense), 80); }}
            className="flex-1 flex flex-col items-center justify-center gap-1.5"
            style={{
              background: 'rgba(99,102,241,0.28)',
              borderTop: '1px solid rgba(99,102,241,0.35)',
              borderBottom: '1px solid rgba(99,102,241,0.35)',
            }}
          >
            <div
              className="rounded-xl flex items-center justify-center"
              style={{ width: 34, height: 34, background: 'rgba(99,102,241,0.3)', border: '1.5px solid rgba(129,140,248,0.5)' }}
            >
              <Pencil size={15} color="#818CF8" />
            </div>
            <span style={{ fontSize: 9, fontWeight: 800, color: '#818CF8', fontFamily: font, letterSpacing: 0.8 }}>EDIT</span>
          </motion.button>

          {/* Delete */}
          <motion.button
            whileTap={{ scale: 0.88 }}
            onClick={() => { snapClose(); setTimeout(() => onDelete(expense.id), 80); }}
            className="flex-1 flex flex-col items-center justify-center gap-1.5 rounded-r-2xl"
            style={{
              background: 'rgba(239,68,68,0.22)',
              borderTop: '1px solid rgba(239,68,68,0.35)',
              borderBottom: '1px solid rgba(239,68,68,0.35)',
              borderRight: '1px solid rgba(239,68,68,0.35)',
            }}
          >
            <div
              className="rounded-xl flex items-center justify-center"
              style={{ width: 34, height: 34, background: 'rgba(239,68,68,0.22)', border: '1.5px solid rgba(239,68,68,0.5)' }}
            >
              <Trash2 size={15} color="#EF4444" />
            </div>
            <span style={{ fontSize: 9, fontWeight: 800, color: '#EF4444', fontFamily: font, letterSpacing: 0.8 }}>DELETE</span>
          </motion.button>
        </div>

        {/* ── Main swipeable content ──
            SOLID opaque background (#0f0f0f) so action buttons are fully hidden at x=0.
            z-index: 2 ensures it sits above the action panel. ── */}
        <motion.div
          style={{
            x,
            background: '#0f0f0f',
            border: '1px solid rgba(255,255,255,0.08)',
            borderRadius: 16,
            position: 'relative',
            zIndex: 2,
            touchAction: 'pan-y',
            userSelect: 'none',
          }}
          className="flex items-center gap-3 px-4 py-3"
          onTouchStart={handleTouchStart}
          onTouchMove={handleTouchMove}
          onTouchEnd={handleTouchEnd}
        >
          {/* Category icon */}
          <div
            className="flex items-center justify-center rounded-xl shrink-0"
            style={{ width: 42, height: 42, background: `${color}18`, border: `1px solid ${color}35` }}
          >
            <span style={{ fontSize: 19 }}>{icon}</span>
          </div>

          {/* Info */}
          <div className="flex-1 min-w-0">
            <p
              className="truncate"
              style={{ fontSize: 14, fontWeight: 600, color: 'rgba(255,255,255,0.9)', fontFamily: font }}
            >
              {expense.description}
            </p>
            <div className="flex items-center gap-1.5 mt-0.5 flex-wrap">
              <span
                className="rounded-md px-1.5 py-0.5"
                style={{ fontSize: 10, fontWeight: 600, letterSpacing: 0.4, background: `${color}22`, color, fontFamily: font }}
              >
                {expense.category}
              </span>
              <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.2)' }}>·</span>
              <span
                className="rounded-md px-1.5 py-0.5"
                style={{
                  fontSize: 10, fontWeight: 600, letterSpacing: 0.3,
                  background: `${bankColor}28`,
                  color: bankColor === '#555' ? 'rgba(255,255,255,0.45)' : bankColor,
                  filter: bankColor === '#555' ? 'none' : 'brightness(1.5)',
                  fontFamily: font,
                }}
              >
                {expense.bank}
              </span>
              <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.2)' }}>·</span>
              <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.35)', fontFamily: font }}>
                {expense.cardType === 'Cash' ? '💵' : expense.cardType === 'Credit Card' ? '💳' : '🏦'} {expense.cardType}
              </span>
            </div>
          </div>

          {/* Amount + time + swipe hint */}
          <div className="flex flex-col items-end gap-1 shrink-0">
            <p style={{ fontSize: 15, fontWeight: 700, color: '#EF4444', fontFamily: font }}>
              -{formatCurrency(expense.amount)}
            </p>
            <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.3)', fontFamily: font }}>
              {formatTime(expense.date)}
            </p>
            {/* Swipe hint chevrons */}
            <div className="flex items-center gap-0.5 mt-0.5">
              {[0, 1, 2].map(i => (
                <motion.div
                  key={i}
                  animate={revealed
                    ? { opacity: 0.7 - i * 0.2, x: 0 }
                    : { opacity: 0.15 - i * 0.04, x: 0 }
                  }
                  style={{
                    width: 4, height: 4, borderRadius: '50%',
                    background: revealed ? '#EF4444' : 'rgba(255,255,255,0.4)',
                  }}
                />
              ))}
            </div>
          </div>
        </motion.div>
      </div>
    </motion.div>
  );
}
