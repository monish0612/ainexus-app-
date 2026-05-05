import { motion } from 'motion/react';
import { formatCurrency } from '../../utils/categoryUtils';

interface BudgetRingProps {
  budget: number;
  spent: number;
}

function interpolateColor(color1: string, color2: string, t: number): string {
  const c1 = hexToRgb(color1);
  const c2 = hexToRgb(color2);
  const r = Math.round(c1.r + (c2.r - c1.r) * t);
  const g = Math.round(c1.g + (c2.g - c1.g) * t);
  const b = Math.round(c1.b + (c2.b - c1.b) * t);
  return `rgb(${r},${g},${b})`;
}

function hexToRgb(hex: string) {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  return result
    ? { r: parseInt(result[1], 16), g: parseInt(result[2], 16), b: parseInt(result[3], 16) }
    : { r: 255, g: 255, b: 255 };
}

function getBudgetColor(spentPercent: number): string {
  const clamped = Math.min(Math.max(spentPercent, 0), 100);
  if (clamped < 40) return interpolateColor('#22C55E', '#22C55E', 0);
  if (clamped < 65) return interpolateColor('#22C55E', '#F59E0B', (clamped - 40) / 25);
  if (clamped < 85) return interpolateColor('#F59E0B', '#F97316', (clamped - 65) / 20);
  return interpolateColor('#F97316', '#EF4444', (clamped - 85) / 15);
}

export function BudgetRing({ budget, spent }: BudgetRingProps) {
  const remaining = budget - spent;
  const spentPercent = budget > 0 ? (spent / budget) * 100 : 0;
  const remainingPercent = Math.max(0, 1 - spent / Math.max(budget, 1));
  const isOverBudget = remaining < 0;

  // SVG arc config
  const cx = 100, cy = 100, r = 78;
  const circumference = 2 * Math.PI * r; // ≈ 490.09
  const totalArcRatio = 0.75; // 270°
  const totalArc = circumference * totalArcRatio; // ≈ 367.57
  const gap = circumference - totalArc; // ≈ 122.52
  const progressLength = isOverBudget ? 0 : remainingPercent * totalArc;

  const arcColor = isOverBudget ? '#EF4444' : getBudgetColor(spentPercent);
  const glowColor = isOverBudget ? 'rgba(239,68,68,0.7)' : arcColor.replace('rgb', 'rgba').replace(')', ',0.5)');

  return (
    <div className="flex flex-col items-center">
      <div className="relative" style={{ width: 210, height: 210 }}>
        {/* Outer ambient glow */}
        {isOverBudget && (
          <motion.div
            className="absolute inset-0 rounded-full"
            style={{ background: 'radial-gradient(circle, rgba(239,68,68,0.15) 0%, transparent 70%)' }}
            animate={{ opacity: [0.4, 1, 0.4] }}
            transition={{ duration: 2, repeat: Infinity, ease: 'easeInOut' }}
          />
        )}

        <svg viewBox="0 0 200 200" width="210" height="210" style={{ overflow: 'visible' }}>
          <defs>
            <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
              <feGaussianBlur stdDeviation="4" result="blur" />
              <feMerge>
                <feMergeNode in="blur" />
                <feMergeNode in="SourceGraphic" />
              </feMerge>
            </filter>
          </defs>

          {/* Track (background arc) */}
          <circle
            cx={cx} cy={cy} r={r}
            fill="none"
            stroke="rgba(255,255,255,0.07)"
            strokeWidth="10"
            strokeLinecap="round"
            strokeDasharray={`${totalArc} ${gap}`}
            transform={`rotate(135, ${cx}, ${cy})`}
          />

          {/* Progress arc */}
          {!isOverBudget && (
            <motion.circle
              cx={cx} cy={cy} r={r}
              fill="none"
              stroke={arcColor}
              strokeWidth="10"
              strokeLinecap="round"
              strokeDasharray={`${progressLength} ${circumference}`}
              transform={`rotate(135, ${cx}, ${cy})`}
              style={{ filter: `drop-shadow(0 0 6px ${arcColor})` }}
              initial={{ strokeDasharray: `0 ${circumference}` }}
              animate={{ strokeDasharray: `${progressLength} ${circumference}` }}
              transition={{ duration: 1, ease: 'easeOut' }}
            />
          )}

          {/* Over-budget pulsing arc */}
          {isOverBudget && (
            <motion.circle
              cx={cx} cy={cy} r={r}
              fill="none"
              stroke="#EF4444"
              strokeWidth="10"
              strokeLinecap="round"
              strokeDasharray={`${totalArc} ${gap}`}
              transform={`rotate(135, ${cx}, ${cy})`}
              animate={{
                filter: [
                  'drop-shadow(0 0 4px #EF4444)',
                  'drop-shadow(0 0 18px #EF4444) drop-shadow(0 0 30px rgba(239,68,68,0.5))',
                  'drop-shadow(0 0 4px #EF4444)',
                ],
                opacity: [0.8, 1, 0.8],
              }}
              transition={{ duration: 1.8, repeat: Infinity, ease: 'easeInOut' }}
            />
          )}

          {/* Center dot at progress end (only when not over budget) */}
          {!isOverBudget && progressLength > 5 && (
            <circle
              cx={cx + r * Math.cos(((135 + remainingPercent * 270) * Math.PI) / 180)}
              cy={cy + r * Math.sin(((135 + remainingPercent * 270) * Math.PI) / 180)}
              r={5}
              fill={arcColor}
              style={{ filter: `drop-shadow(0 0 4px ${arcColor})` }}
            />
          )}
        </svg>

        {/* Center content */}
        <div className="absolute inset-0 flex flex-col items-center justify-center" style={{ paddingBottom: 12 }}>
          <motion.p
            key={remaining}
            initial={{ scale: 0.9, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            transition={{ duration: 0.3 }}
            className="text-center"
            style={{
              fontSize: remaining < 0 ? 22 : 26,
              fontWeight: 700,
              fontFamily: "'Plus Jakarta Sans', sans-serif",
              color: isOverBudget ? '#EF4444' : arcColor,
              textShadow: isOverBudget ? '0 0 20px rgba(239,68,68,0.6)' : `0 0 12px ${glowColor}`,
              lineHeight: 1.1,
              letterSpacing: '-0.5px',
            }}
          >
            {isOverBudget ? '-' : ''}{formatCurrency(Math.abs(remaining))}
          </motion.p>
          <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.4)', letterSpacing: 2, marginTop: 4, fontFamily: "'Plus Jakarta Sans', sans-serif", fontWeight: 500 }}>
            {isOverBudget ? 'OVER BUDGET' : 'REMAINING'}
          </p>
        </div>
      </div>

      {/* Stats row */}
      <div className="flex items-center gap-6 mt-1">
        <div className="text-center">
          <p style={{ fontSize: 13, color: '#EF4444', fontWeight: 600, fontFamily: "'Plus Jakarta Sans', sans-serif" }}>
            {formatCurrency(spent)}
          </p>
          <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.35)', letterSpacing: 1, fontFamily: "'Plus Jakarta Sans', sans-serif" }}>SPENT</p>
        </div>
        <div className="w-px h-8" style={{ background: 'rgba(255,255,255,0.1)' }} />
        <div className="text-center">
          <p style={{ fontSize: 13, color: 'rgba(255,255,255,0.7)', fontWeight: 600, fontFamily: "'Plus Jakarta Sans', sans-serif" }}>
            {formatCurrency(budget)}
          </p>
          <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.35)', letterSpacing: 1, fontFamily: "'Plus Jakarta Sans', sans-serif" }}>BUDGET</p>
        </div>
        <div className="w-px h-8" style={{ background: 'rgba(255,255,255,0.1)' }} />
        <div className="text-center">
          <p style={{ fontSize: 13, fontWeight: 600, fontFamily: "'Plus Jakarta Sans', sans-serif", color: isOverBudget ? '#EF4444' : arcColor }}>
            {isOverBudget ? '0%' : `${Math.round(remainingPercent * 100)}%`}
          </p>
          <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.35)', letterSpacing: 1, fontFamily: "'Plus Jakarta Sans', sans-serif" }}>LEFT</p>
        </div>
      </div>
    </div>
  );
}
