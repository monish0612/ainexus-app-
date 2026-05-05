import { useState, useEffect } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, ChevronDown } from 'lucide-react';
import type { Expense } from '../../types/expense';
import { BANKS, CARD_TYPES, CATEGORIES, CATEGORY_COLORS, CATEGORY_ICONS } from '../../types/expense';

interface EditExpenseModalProps {
  open: boolean;
  expense: Expense | null;
  onClose: () => void;
  onUpdate: (expense: Expense) => void;
}

const font = "'Plus Jakarta Sans', sans-serif";

export function EditExpenseModal({ open, expense, onClose, onUpdate }: EditExpenseModalProps) {
  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [bank, setBank] = useState('HDFC');
  const [cardType, setCardType] = useState('Debit Card');
  const [category, setCategory] = useState('Others');
  const [showCategoryPicker, setShowCategoryPicker] = useState(false);

  useEffect(() => {
    if (open && expense) {
      setAmount(String(expense.amount));
      setDescription(expense.description);
      setBank(expense.bank);
      setCardType(expense.cardType);
      setCategory(expense.category);
      setShowCategoryPicker(false);
    }
  }, [open, expense]);

  const handleSubmit = () => {
    if (!expense) return;
    const num = parseFloat(amount.replace(/,/g, ''));
    if (!num || num <= 0 || !description.trim()) return;
    onUpdate({ ...expense, amount: num, description: description.trim(), category, bank, cardType, isManualCategory: true });
    onClose();
  };

  const isValid = !!amount && !!description.trim();

  return (
    <AnimatePresence>
      {open && expense && (
        <>
          <motion.div
            className="fixed inset-0 z-40"
            style={{ background: 'rgba(0,0,0,0.65)', backdropFilter: 'blur(4px)' }}
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
              className="w-full max-w-[430px] rounded-t-3xl px-5 pt-4 pb-8"
              style={{
                background: '#0a0a0a',
                border: '1px solid rgba(255,255,255,0.1)',
                borderBottom: 'none',
              }}
            >
              {/* Handle */}
              <div className="flex justify-center mb-4">
                <div className="w-10 h-1 rounded-full" style={{ background: 'rgba(255,255,255,0.15)' }} />
              </div>

              {/* Header */}
              <div className="flex items-center justify-between mb-5">
                <div>
                  <h3 style={{ fontSize: 18, fontWeight: 700, color: '#fff', fontFamily: font }}>
                    Edit Expense
                  </h3>
                  <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.3)', fontFamily: font, marginTop: 2 }}>
                    Modify the details below
                  </p>
                </div>
                <motion.button
                  whileTap={{ scale: 0.88 }}
                  onClick={onClose}
                  className="rounded-xl p-2"
                  style={{ background: 'rgba(255,255,255,0.07)' }}
                >
                  <X size={16} color="rgba(255,255,255,0.6)" />
                </motion.button>
              </div>

              {/* Amount */}
              <div
                className="rounded-2xl px-4 py-4 mb-4 flex items-center gap-3"
                style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
              >
                <span style={{ fontSize: 26, fontWeight: 700, color: 'rgba(255,255,255,0.4)', fontFamily: font }}>₹</span>
                <input
                  type="number"
                  inputMode="decimal"
                  value={amount}
                  onChange={e => setAmount(e.target.value)}
                  className="flex-1 bg-transparent outline-none"
                  style={{ fontSize: 32, fontWeight: 700, color: '#fff', fontFamily: font, letterSpacing: '-0.5px' }}
                />
              </div>

              {/* Description */}
              <div
                className="rounded-2xl px-4 py-3 mb-4"
                style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
              >
                <input
                  type="text"
                  value={description}
                  onChange={e => setDescription(e.target.value)}
                  className="w-full bg-transparent outline-none"
                  style={{ fontSize: 14, color: 'rgba(255,255,255,0.85)', fontFamily: font }}
                />
              </div>

              {/* Category */}
              <div className="mb-4">
                <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', letterSpacing: 1, marginBottom: 8, fontFamily: font, fontWeight: 600 }}>
                  CATEGORY
                </p>
                <motion.button
                  whileTap={{ scale: 0.97 }}
                  onClick={() => setShowCategoryPicker(!showCategoryPicker)}
                  className="w-full flex items-center gap-3 rounded-2xl px-4 py-3"
                  style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}
                >
                  <span style={{ fontSize: 20 }}>{CATEGORY_ICONS[category]}</span>
                  <span style={{ flex: 1, textAlign: 'left', fontSize: 14, fontWeight: 600, color: CATEGORY_COLORS[category], fontFamily: font }}>
                    {category}
                  </span>
                  <ChevronDown
                    size={14}
                    color="rgba(255,255,255,0.35)"
                    style={{ transform: showCategoryPicker ? 'rotate(180deg)' : 'none', transition: 'transform 0.2s' }}
                  />
                </motion.button>

                <AnimatePresence>
                  {showCategoryPicker && (
                    <motion.div
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: 'auto' }}
                      exit={{ opacity: 0, height: 0 }}
                      className="overflow-hidden"
                    >
                      <div className="grid grid-cols-4 gap-2 mt-2">
                        {CATEGORIES.map(cat => (
                          <motion.button
                            key={cat}
                            whileTap={{ scale: 0.92 }}
                            onClick={() => { setCategory(cat); setShowCategoryPicker(false); }}
                            className="flex flex-col items-center gap-1 rounded-xl py-2.5 px-1"
                            style={{
                              background: category === cat ? `${CATEGORY_COLORS[cat]}20` : 'rgba(255,255,255,0.04)',
                              border: `1px solid ${category === cat ? CATEGORY_COLORS[cat] + '60' : 'rgba(255,255,255,0.07)'}`,
                            }}
                          >
                            <span style={{ fontSize: 20 }}>{CATEGORY_ICONS[cat]}</span>
                            <span style={{
                              fontSize: 9,
                              color: category === cat ? CATEGORY_COLORS[cat] : 'rgba(255,255,255,0.4)',
                              fontWeight: 600,
                              fontFamily: font,
                            }}>
                              {cat}
                            </span>
                          </motion.button>
                        ))}
                      </div>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>

              {/* Bank */}
              <div className="mb-4">
                <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', letterSpacing: 1, marginBottom: 8, fontFamily: font, fontWeight: 600 }}>
                  BANK
                </p>
                <div className="flex gap-2">
                  {BANKS.map(b => (
                    <motion.button
                      key={b}
                      whileTap={{ scale: 0.93 }}
                      onClick={() => setBank(b)}
                      className="flex-1 py-2 rounded-xl"
                      style={{
                        fontSize: 12, fontWeight: 700, letterSpacing: 0.3, fontFamily: font,
                        background: bank === b ? 'rgba(124,99,226,0.2)' : 'rgba(255,255,255,0.04)',
                        border: `1px solid ${bank === b ? 'rgba(124,99,226,0.6)' : 'rgba(255,255,255,0.07)'}`,
                        color: bank === b ? '#A78BFA' : 'rgba(255,255,255,0.45)',
                      }}
                    >
                      {b}
                    </motion.button>
                  ))}
                </div>
              </div>

              {/* Card type */}
              <div className="mb-6">
                <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', letterSpacing: 1, marginBottom: 8, fontFamily: font, fontWeight: 600 }}>
                  PAYMENT TYPE
                </p>
                <div className="flex gap-2">
                  {CARD_TYPES.map(ct => (
                    <motion.button
                      key={ct}
                      whileTap={{ scale: 0.93 }}
                      onClick={() => setCardType(ct)}
                      className="flex-1 py-2 rounded-xl"
                      style={{
                        fontSize: 12, fontWeight: 600, fontFamily: font,
                        background: cardType === ct ? 'rgba(52,211,153,0.15)' : 'rgba(255,255,255,0.04)',
                        border: `1px solid ${cardType === ct ? 'rgba(52,211,153,0.5)' : 'rgba(255,255,255,0.07)'}`,
                        color: cardType === ct ? '#34D399' : 'rgba(255,255,255,0.45)',
                      }}
                    >
                      {ct === 'Cash' ? '💵' : ct === 'Credit Card' ? '💳' : '🏦'} {ct}
                    </motion.button>
                  ))}
                </div>
              </div>

              {/* Save */}
              <motion.button
                whileTap={{ scale: 0.97 }}
                onClick={handleSubmit}
                disabled={!isValid}
                className="w-full py-4 rounded-2xl"
                style={{
                  background: isValid ? 'linear-gradient(135deg, #7C3AED, #6366F1)' : 'rgba(255,255,255,0.06)',
                  border: isValid ? '1px solid rgba(124,58,237,0.5)' : '1px solid rgba(255,255,255,0.08)',
                  fontSize: 15, fontWeight: 700,
                  color: isValid ? '#fff' : 'rgba(255,255,255,0.25)',
                  fontFamily: font,
                  boxShadow: isValid ? '0 4px 20px rgba(124,58,237,0.35)' : 'none',
                  letterSpacing: 0.3,
                }}
              >
                Save Changes
              </motion.button>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}
