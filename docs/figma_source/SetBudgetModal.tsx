import { useState, useEffect, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X } from 'lucide-react';

interface SetBudgetModalProps {
  open: boolean;
  current: number;
  onClose: () => void;
  onSet: (amount: number) => void;
}

export function SetBudgetModal({ open, current, onClose, onSet }: SetBudgetModalProps) {
  const [value, setValue] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (open) {
      setValue(current > 0 ? String(current) : '');
      setTimeout(() => inputRef.current?.focus(), 300);
    }
  }, [open, current]);

  const handleSet = () => {
    const num = parseFloat(value.replace(/,/g, ''));
    if (num > 0) {
      onSet(num);
      onClose();
    }
  };

  const presets = [5000, 10000, 20000, 50000];

  return (
    <AnimatePresence>
      {open && (
        <>
          <motion.div
            className="fixed inset-0 z-40"
            style={{ background: 'rgba(0,0,0,0.6)', backdropFilter: 'blur(4px)' }}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          />
          <motion.div
            className="fixed bottom-0 left-0 right-0 z-50 flex justify-center"
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', damping: 30, stiffness: 300 }}
          >
            <div
              className="w-full max-w-[430px] rounded-t-3xl px-5 pt-4 pb-10"
              style={{ background: '#0a0a0a', border: '1px solid rgba(255,255,255,0.1)', borderBottom: 'none' }}
            >
              <div className="flex justify-center mb-4">
                <div className="w-10 h-1 rounded-full" style={{ background: 'rgba(255,255,255,0.15)' }} />
              </div>
              <div className="flex items-center justify-between mb-5">
                <h3 style={{ fontSize: 18, fontWeight: 700, color: '#fff', fontFamily: "'Plus Jakarta Sans', sans-serif" }}>
                  Set Budget
                </h3>
                <motion.button
                  whileTap={{ scale: 0.88 }}
                  onClick={onClose}
                  className="rounded-xl p-2"
                  style={{ background: 'rgba(255,255,255,0.07)' }}
                >
                  <X size={16} color="rgba(255,255,255,0.6)" />
                </motion.button>
              </div>

              <div
                className="rounded-2xl px-4 py-4 mb-4 flex items-center gap-3"
                style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
              >
                <span style={{ fontSize: 26, fontWeight: 700, color: 'rgba(255,255,255,0.4)', fontFamily: "'Plus Jakarta Sans', sans-serif" }}>₹</span>
                <input
                  ref={inputRef}
                  type="number"
                  inputMode="numeric"
                  placeholder="Enter budget"
                  value={value}
                  onChange={e => setValue(e.target.value)}
                  onKeyDown={e => e.key === 'Enter' && handleSet()}
                  className="flex-1 bg-transparent outline-none placeholder-white/20"
                  style={{ fontSize: 32, fontWeight: 700, color: '#fff', fontFamily: "'Plus Jakarta Sans', sans-serif", letterSpacing: '-0.5px' }}
                />
              </div>

              <div className="flex gap-2 mb-5">
                {presets.map(p => (
                  <motion.button
                    key={p}
                    whileTap={{ scale: 0.93 }}
                    onClick={() => setValue(String(p))}
                    className="flex-1 py-2 rounded-xl"
                    style={{
                      fontSize: 12, fontWeight: 600, fontFamily: "'Plus Jakarta Sans', sans-serif",
                      background: value === String(p) ? 'rgba(124,99,226,0.2)' : 'rgba(255,255,255,0.05)',
                      border: `1px solid ${value === String(p) ? 'rgba(124,99,226,0.5)' : 'rgba(255,255,255,0.08)'}`,
                      color: value === String(p) ? '#A78BFA' : 'rgba(255,255,255,0.45)',
                    }}
                  >
                    ₹{p >= 1000 ? `${p / 1000}k` : p}
                  </motion.button>
                ))}
              </div>

              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={handleSet}
                disabled={!value}
                className="w-full py-4 rounded-2xl"
                style={{
                  background: value ? 'linear-gradient(135deg, #7C3AED, #6366F1)' : 'rgba(255,255,255,0.06)',
                  border: value ? '1px solid rgba(124,58,237,0.5)' : '1px solid rgba(255,255,255,0.08)',
                  fontSize: 15, fontWeight: 700, color: value ? '#fff' : 'rgba(255,255,255,0.25)',
                  fontFamily: "'Plus Jakarta Sans', sans-serif",
                  boxShadow: value ? '0 4px 20px rgba(124,58,237,0.35)' : 'none',
                }}
              >
                Set Budget
              </motion.button>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}