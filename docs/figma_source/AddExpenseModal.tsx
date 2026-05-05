import type { SuccessMeta } from './ExpenseSuccessModal';
import { useState, useEffect, useRef, useCallback } from 'react';
import type { ReactNode } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { X, Camera, Upload, Check, ChevronDown, Wand2, Sparkles, Brain, RotateCcw } from 'lucide-react';
import type { Expense, CategoryLearning } from '../../types/expense';
import { BANKS, CARD_TYPES, CATEGORIES, CATEGORY_COLORS, CATEGORY_ICONS } from '../../types/expense';
import { aiCategorize } from '../../utils/aiCategorize';
import type { AICategoryResult } from '../../utils/aiCategorize';

const font = "'Plus Jakarta Sans', sans-serif";

// ── Types ──────────────────────────────────────────────────────────────────
type Mode = 'scan' | 'manual';
type ScanState = 'idle' | 'scanning' | 'done' | 'error';
type Confidence = 'learned' | 'matched' | 'default';

interface AddExpenseModalProps {
  open: boolean;
  onClose: () => void;
  onAdd: (expense: Omit<Expense, 'id' | 'date'>, isManual: boolean, meta: SuccessMeta) => void;
  learnings: CategoryLearning;
  onTeachAI: (description: string, category: string) => void;
}

// ── Mock bill extraction pool (Indian merchants) ───────────────────────────
const MOCK_POOL: Array<{ shop: string; amount: string; hints: string[] }> = [
  { shop: 'Swiggy Order', amount: '347', hints: ['swiggy'] },
  { shop: 'Zomato Delivery', amount: '529', hints: ['zomato', 'zmt'] },
  { shop: 'BigBasket Grocery', amount: '1243', hints: ['bigbasket', 'basket'] },
  { shop: 'DMart Supermarket', amount: '2156', hints: ['dmart', 'mart'] },
  { shop: 'Uber Ride', amount: '145', hints: ['uber'] },
  { shop: 'Ola Cab', amount: '223', hints: ['ola'] },
  { shop: 'Netflix Subscription', amount: '649', hints: ['netflix', 'ott'] },
  { shop: 'Amazon Order', amount: '1599', hints: ['amazon', 'amz'] },
  { shop: 'BESCOM Electricity', amount: '1876', hints: ['bescom', 'electricity', 'bill'] },
  { shop: 'Apollo Pharmacy', amount: '287', hints: ['apollo', 'pharmacy', 'medicine'] },
  { shop: 'BPCL Petrol Pump', amount: '500', hints: ['petrol', 'fuel', 'bpcl', 'iocl'] },
  { shop: 'Café Coffee Day', amount: '185', hints: ['coffee', 'cafe', 'ccd'] },
  { shop: 'Myntra Fashion', amount: '999', hints: ['myntra', 'fashion', 'clothes'] },
  { shop: 'IRCTC Train Ticket', amount: '450', hints: ['irctc', 'train', 'railway'] },
  { shop: 'Cult.fit Membership', amount: '799', hints: ['cult', 'fitness', 'gym'] },
  { shop: 'Blinkit Grocery', amount: '632', hints: ['blinkit', 'grofers'] },
  { shop: 'Jio Recharge', amount: '299', hints: ['jio', 'recharge', 'mobile'] },
  { shop: 'BookMyShow', amount: '380', hints: ['bookmyshow', 'movie', 'cinema'] },
];

const SCAN_PHASES = [
  { text: 'Uploading image…', emoji: '📤', ms: 600 },
  { text: 'Reading bill structure…', emoji: '🔍', ms: 1200 },
  { text: 'Detecting amount & merchant…', emoji: '💰', ms: 1000 },
  { text: 'AI categorizing expense…', emoji: '🧠', ms: 800 },
];

function getMockExtraction(fileName: string) {
  const lower = fileName.toLowerCase();
  for (const item of MOCK_POOL) {
    if (item.hints.some(h => lower.includes(h))) return item;
  }
  return MOCK_POOL[Math.floor((Date.now() / 1000) % MOCK_POOL.length)];
}

const sleep = (ms: number) => new Promise<void>(r => setTimeout(r, ms));

const CONF_META: Record<Confidence, { label: string; color: string; bg: string }> = {
  learned: { label: 'AI Learned', color: '#818CF8', bg: 'rgba(129,140,248,0.18)' },
  matched: { label: 'AI Detected', color: '#34D399', bg: 'rgba(52,211,153,0.18)' },
  default: { label: 'Undetected', color: 'rgba(255,255,255,0.38)', bg: 'rgba(255,255,255,0.07)' },
};

// ── Component ──────────────────────────────────────────────────────────────
export function AddExpenseModal({ open, onClose, onAdd, learnings, onTeachAI }: AddExpenseModalProps) {
  const [mode, setMode] = useState<Mode>('scan');
  const [scanState, setScanState] = useState<ScanState>('idle');
  const [scanPhaseIdx, setScanPhaseIdx] = useState(0);
  const [imageUrl, setImageUrl] = useState<string | null>(null);

  const [amount, setAmount] = useState('');
  const [description, setDescription] = useState('');
  const [bank, setBank] = useState('HDFC');
  const [cardType, setCardType] = useState('Debit Card');
  const [category, setCategory] = useState('Others');
  const [aiCategory, setAiCategory] = useState<string | null>(null);
  const [confidence, setConfidence] = useState<Confidence>('default');
  const [isManual, setIsManual] = useState(false);
  const [hasLearned, setHasLearned] = useState(false);
  const [isLearning, setIsLearning] = useState(false);
  const [showCategoryPicker, setShowCategoryPicker] = useState(false);
  const [aiThinking, setAiThinking] = useState(false);
  const [aiReasoning, setAiReasoning] = useState('');

  const cameraRef = useRef<HTMLInputElement>(null);
  const uploadRef = useRef<HTMLInputElement>(null);
  const amountRef = useRef<HTMLInputElement>(null);
  const scanActive = useRef(false);
  const aiTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // ── Reset on open/close ──
  useEffect(() => {
    if (open) {
      setMode('scan');
      setScanState('idle');
      setScanPhaseIdx(0);
      setImageUrl(null);
      setAmount('');
      setDescription('');
      setBank('HDFC');
      setCardType('Debit Card');
      setCategory('Others');
      setAiCategory(null);
      setConfidence('default');
      setIsManual(false);
      setHasLearned(false);
      setIsLearning(false);
      setShowCategoryPicker(false);
      setAiThinking(false);
      setAiReasoning('');
    } else {
      scanActive.current = false;
    }
  }, [open]);

  // ── Auto-categorize on description change (manual mode) ──
  useEffect(() => {
    if (mode !== 'manual') return;
    if (isManual) return;
    if (description.trim().length < 3) { setAiThinking(false); return; }

    setAiThinking(true);
    if (aiTimer.current) clearTimeout(aiTimer.current);
    aiTimer.current = setTimeout(async () => {
      const result = await aiCategorize(description, learnings);
      setCategory(result.category);
      setAiCategory(result.category);
      setConfidence(result.confidence);
      setAiReasoning(result.reasoning);
      setAiThinking(false);
    }, 480);

    return () => { if (aiTimer.current) clearTimeout(aiTimer.current); };
  }, [description, learnings, isManual, mode]);

  // ── Image file picked → start simulated scan ──
  const handleImageFile = useCallback(async (file: File) => {
    const url = URL.createObjectURL(file);
    setImageUrl(url);
    setScanState('scanning');
    setScanPhaseIdx(0);
    scanActive.current = true;

    let totalMs = 0;
    for (let i = 0; i < SCAN_PHASES.length; i++) {
      if (!scanActive.current) return;
      setScanPhaseIdx(i);
      await sleep(SCAN_PHASES[i].ms);
      totalMs += SCAN_PHASES[i].ms;
    }

    if (!scanActive.current) return;

    const extracted = getMockExtraction(file.name);
    const result = await aiCategorize(extracted.shop, learnings);
    setAmount(extracted.amount);
    setDescription(extracted.shop);
    setCategory(result.category);
    setAiCategory(result.category);
    setConfidence(result.confidence);
    setAiReasoning(result.reasoning);
    setScanState('done');
  }, [learnings]);

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (file) handleImageFile(file);
    e.target.value = '';
  };

  // ── Category manual override ──
  const handleCategorySelect = (cat: string) => {
    setCategory(cat);
    setIsManual(true);
    setHasLearned(false);
    setShowCategoryPicker(false);
  };

  // ── Wand: teach AI immediately ──
  const handleTeachAI = async () => {
    if (!description.trim() || isLearning || hasLearned) return;
    setIsLearning(true);
    await sleep(1200);
    onTeachAI(description, category);
    setIsLearning(false);
    setHasLearned(true);
    setConfidence('learned');
  };

  // ── Submit ──
  const handleSubmit = () => {
    const num = parseFloat(amount.replace(/,/g, ''));
    if (!num || num <= 0 || !description.trim()) return;
    const finalIsManual = isManual && !hasLearned;
    onAdd(
      { amount: num, description: description.trim(), category, bank, cardType, isManualCategory: isManual },
      finalIsManual,
      {
        confidence: isManual ? 'manual' : confidence,
        reasoning: aiReasoning,
        capturedImageUrl: imageUrl,
      }
    );
    onClose();
  };

  const canSubmit = parseFloat(amount) > 0 && description.trim().length > 0;
  const showWand = isManual && !hasLearned && aiCategory !== null && description.trim().length >= 3;
  const currentPhase = SCAN_PHASES[scanPhaseIdx];

  return (
    <AnimatePresence>
      {open && (
        <>
          {/* Backdrop */}
          <motion.div
            className="fixed inset-0 z-40"
            style={{ background: 'rgba(0,0,0,0.7)', backdropFilter: 'blur(6px)' }}
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          />

          {/* ── Bottom Sheet ── */}
          <motion.div
            className="fixed bottom-0 left-0 right-0 z-50 flex justify-center"
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', damping: 30, stiffness: 300 }}
          >
            <div
              className="w-full max-w-[430px] rounded-t-3xl flex flex-col"
              style={{
                background: '#080808',
                border: '1px solid rgba(255,255,255,0.1)',
                borderBottom: 'none',
                maxHeight: '92dvh',
              }}
            >
              {/* Handle */}
              <div className="flex justify-center pt-3 pb-1 shrink-0">
                <div style={{ width: 40, height: 4, borderRadius: 4, background: 'rgba(255,255,255,0.13)' }} />
              </div>

              {/* Header */}
              <div className="flex items-center justify-between px-5 py-3 shrink-0">
                <h3 style={{ fontSize: 18, fontWeight: 800, color: '#fff', fontFamily: font }}>
                  Add Expense
                </h3>
                <motion.button
                  whileTap={{ scale: 0.88 }}
                  onClick={onClose}
                  className="flex items-center justify-center rounded-full"
                  style={{ width: 34, height: 34, background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.1)' }}
                >
                  <X size={16} color="rgba(255,255,255,0.6)" />
                </motion.button>
              </div>

              {/* ── Mode Tab Switcher ── */}
              <div className="px-5 mb-1 shrink-0">
                <div
                  className="flex p-1 rounded-2xl"
                  style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.08)' }}
                >
                  {([
                    { id: 'scan', icon: '📷', label: 'Scan Bill', sub: 'AI Powered' },
                    { id: 'manual', icon: '✏️', label: 'Manual', sub: 'Type It In' },
                  ] as const).map(tab => (
                    <motion.button
                      key={tab.id}
                      onClick={() => setMode(tab.id)}
                      className="flex-1 flex items-center justify-center gap-2 rounded-xl py-2.5 px-3"
                      animate={{
                        background: mode === tab.id
                          ? 'linear-gradient(135deg, #7C3AED, #6366F1)'
                          : 'transparent',
                        boxShadow: mode === tab.id
                          ? '0 2px 12px rgba(124,58,237,0.5)'
                          : 'none',
                      }}
                      transition={{ duration: 0.22 }}
                    >
                      <span style={{ fontSize: 16 }}>{tab.icon}</span>
                      <div className="text-left">
                        <p style={{ fontSize: 12, fontWeight: 700, color: mode === tab.id ? '#fff' : 'rgba(255,255,255,0.45)', fontFamily: font, lineHeight: 1 }}>
                          {tab.label}
                        </p>
                        <p style={{ fontSize: 9, color: mode === tab.id ? 'rgba(255,255,255,0.6)' : 'rgba(255,255,255,0.25)', fontFamily: font, letterSpacing: 0.3 }}>
                          {tab.sub}
                        </p>
                      </div>
                    </motion.button>
                  ))}
                </div>
              </div>

              {/* ── Scrollable Content ── */}
              <div className="flex-1 overflow-y-auto px-5 pt-3 pb-6">

                {/* ════════ SCAN MODE ════════ */}
                <AnimatePresence mode="wait">
                  {mode === 'scan' && (
                    <motion.div
                      key="scan"
                      initial={{ opacity: 0, x: 24 }}
                      animate={{ opacity: 1, x: 0 }}
                      exit={{ opacity: 0, x: -24 }}
                      transition={{ duration: 0.2 }}
                    >
                      {/* Hidden file inputs */}
                      <input ref={cameraRef} type="file" accept="image/*" capture="environment" className="hidden" onChange={handleFileChange} />
                      <input ref={uploadRef} type="file" accept="image/*" className="hidden" onChange={handleFileChange} />

                      {/* ── IDLE: Drop zone ── */}
                      {scanState === 'idle' && (
                        <motion.div
                          initial={{ opacity: 0, scale: 0.96 }}
                          animate={{ opacity: 1, scale: 1 }}
                          className="flex flex-col items-center rounded-3xl py-8 px-6 mb-5"
                          style={{
                            border: '2px dashed rgba(124,58,237,0.4)',
                            background: 'radial-gradient(circle at 50% 40%, rgba(124,58,237,0.08), transparent 70%)',
                          }}
                        >
                          <motion.div
                            animate={{ y: [0, -6, 0] }}
                            transition={{ duration: 2.4, repeat: Infinity, ease: 'easeInOut' }}
                            style={{ fontSize: 56, marginBottom: 14 }}
                          >
                            🧾
                          </motion.div>

                          <p style={{ fontSize: 15, fontWeight: 700, color: '#fff', fontFamily: font, marginBottom: 6 }}>
                            Scan Your Bill
                          </p>
                          <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.35)', fontFamily: font, textAlign: 'center', lineHeight: 1.6, marginBottom: 20 }}>
                            AI will extract the total amount, merchant name and automatically categorize the expense
                          </p>

                          {/* Feature pills */}
                          <div className="flex flex-wrap gap-2 justify-center mb-6">
                            {['🔢 Auto Amount', '🏪 Shop Name', '🏷️ AI Category'].map(f => (
                              <span key={f} className="rounded-full px-3 py-1"
                                style={{ fontSize: 10, fontWeight: 600, color: '#A78BFA', background: 'rgba(124,58,237,0.18)', border: '1px solid rgba(124,58,237,0.3)', fontFamily: font }}>
                                {f}
                              </span>
                            ))}
                          </div>

                          {/* Action buttons */}
                          <div className="flex gap-3 w-full">
                            <motion.button
                              whileTap={{ scale: 0.94 }}
                              onClick={() => cameraRef.current?.click()}
                              className="flex-1 flex items-center justify-center gap-2 rounded-2xl py-3.5"
                              style={{ background: 'linear-gradient(135deg, #7C3AED, #6366F1)', boxShadow: '0 4px 18px rgba(124,58,237,0.5)' }}
                            >
                              <Camera size={18} color="#fff" />
                              <span style={{ fontSize: 14, fontWeight: 700, color: '#fff', fontFamily: font }}>Camera</span>
                            </motion.button>
                            <motion.button
                              whileTap={{ scale: 0.94 }}
                              onClick={() => uploadRef.current?.click()}
                              className="flex-1 flex items-center justify-center gap-2 rounded-2xl py-3.5"
                              style={{ background: 'rgba(255,255,255,0.07)', border: '1px solid rgba(255,255,255,0.14)' }}
                            >
                              <Upload size={18} color="rgba(255,255,255,0.7)" />
                              <span style={{ fontSize: 14, fontWeight: 700, color: 'rgba(255,255,255,0.7)', fontFamily: font }}>Upload</span>
                            </motion.button>
                          </div>
                        </motion.div>
                      )}

                      {/* ── SCANNING: Image + animated scan line ── */}
                      {(scanState === 'scanning' || scanState === 'done') && imageUrl && (
                        <motion.div
                          initial={{ opacity: 0, y: 10 }}
                          animate={{ opacity: 1, y: 0 }}
                          className="relative rounded-2xl overflow-hidden mb-4"
                          style={{ height: 200 }}
                        >
                          <img src={imageUrl} alt="Bill" className="w-full h-full object-cover" />

                          {scanState === 'scanning' && (
                            <>
                              {/* Dark overlay */}
                              <div className="absolute inset-0" style={{ background: 'rgba(0,0,0,0.55)' }} />

                              {/* Scanning laser line */}
                              <motion.div
                                className="absolute left-0 right-0"
                                style={{
                                  height: 3,
                                  background: 'linear-gradient(90deg, transparent, rgba(124,58,237,0.3), #A78BFA, #7C3AED, #A78BFA, rgba(124,58,237,0.3), transparent)',
                                  boxShadow: '0 0 16px rgba(124,58,237,0.9), 0 0 4px rgba(255,255,255,0.6)',
                                }}
                                initial={{ top: '0%' }}
                                animate={{ top: ['0%', '100%', '0%'] }}
                                transition={{ duration: 2, repeat: Infinity, ease: 'linear' }}
                              />

                              {/* Corner brackets */}
                              {[
                                { top: 8, left: 8, borderTop: '2px solid #7C3AED', borderLeft: '2px solid #7C3AED' },
                                { top: 8, right: 8, borderTop: '2px solid #7C3AED', borderRight: '2px solid #7C3AED' },
                                { bottom: 8, left: 8, borderBottom: '2px solid #7C3AED', borderLeft: '2px solid #7C3AED' },
                                { bottom: 8, right: 8, borderBottom: '2px solid #7C3AED', borderRight: '2px solid #7C3AED' },
                              ].map((style, i) => (
                                <div key={i} className="absolute" style={{ ...style, width: 18, height: 18 }} />
                              ))}

                              {/* Phase text */}
                              <div className="absolute bottom-0 left-0 right-0 px-4 py-3"
                                style={{ background: 'linear-gradient(to top, rgba(0,0,0,0.9), transparent)' }}>
                                <div className="flex items-center gap-2">
                                  <motion.span
                                    key={scanPhaseIdx}
                                    initial={{ scale: 0.7, opacity: 0 }}
                                    animate={{ scale: 1, opacity: 1 }}
                                    style={{ fontSize: 16 }}
                                  >
                                    {currentPhase?.emoji}
                                  </motion.span>
                                  <motion.span
                                    key={`txt-${scanPhaseIdx}`}
                                    initial={{ opacity: 0, x: -8 }}
                                    animate={{ opacity: 1, x: 0 }}
                                    style={{ fontSize: 12, fontWeight: 600, color: '#C4B5FD', fontFamily: font }}
                                  >
                                    {currentPhase?.text}
                                  </motion.span>
                                </div>
                                {/* Progress dots */}
                                <div className="flex gap-1.5 mt-2">
                                  {SCAN_PHASES.map((_, i) => (
                                    <motion.div
                                      key={i}
                                      animate={{ width: i === scanPhaseIdx ? 16 : 5, background: i <= scanPhaseIdx ? '#7C3AED' : 'rgba(255,255,255,0.2)' }}
                                      style={{ height: 4, borderRadius: 4 }}
                                    />
                                  ))}
                                </div>
                              </div>
                            </>
                          )}

                          {scanState === 'done' && (
                            <motion.div
                              initial={{ opacity: 0 }}
                              animate={{ opacity: 1 }}
                              className="absolute inset-0 flex items-center justify-center"
                              style={{ background: 'rgba(0,0,0,0.45)' }}
                            >
                              <motion.div
                                initial={{ scale: 0, opacity: 0 }}
                                animate={{ scale: 1, opacity: 1 }}
                                transition={{ type: 'spring', damping: 14, stiffness: 220 }}
                                className="flex flex-col items-center gap-2"
                              >
                                <div className="flex items-center justify-center rounded-full" style={{ width: 60, height: 60, background: 'rgba(34,197,94,0.9)', boxShadow: '0 0 28px rgba(34,197,94,0.7)' }}>
                                  <Check size={30} color="#fff" strokeWidth={3} />
                                </div>
                                <span style={{ fontSize: 13, fontWeight: 700, color: '#86EFAC', fontFamily: font }}>
                                  Bill Extracted ✓
                                </span>
                              </motion.div>
                            </motion.div>
                          )}

                          {/* Re-scan button */}
                          {scanState === 'done' && (
                            <motion.button
                              initial={{ opacity: 0 }}
                              animate={{ opacity: 1 }}
                              whileTap={{ scale: 0.9 }}
                              onClick={() => { setScanState('idle'); setImageUrl(null); setAmount(''); setDescription(''); }}
                              className="absolute top-3 right-3 flex items-center gap-1.5 rounded-full px-2.5 py-1.5"
                              style={{ background: 'rgba(0,0,0,0.7)', border: '1px solid rgba(255,255,255,0.2)' }}
                            >
                              <RotateCcw size={11} color="rgba(255,255,255,0.7)" />
                              <span style={{ fontSize: 10, fontWeight: 600, color: 'rgba(255,255,255,0.7)', fontFamily: font }}>Rescan</span>
                            </motion.button>
                          )}
                        </motion.div>
                      )}

                      {/* ── DONE: Extracted fields (editable) ── */}
                      {scanState === 'done' && (
                        <motion.div
                          initial={{ opacity: 0, y: 12 }}
                          animate={{ opacity: 1, y: 0 }}
                          transition={{ delay: 0.15 }}
                        >
                          {/* Extracted banner */}
                          <div className="flex items-center gap-2 rounded-xl px-3 py-2 mb-4"
                            style={{ background: 'rgba(34,197,94,0.08)', border: '1px solid rgba(34,197,94,0.22)' }}>
                            <Sparkles size={13} color="#34D399" />
                            <p style={{ fontSize: 11, fontWeight: 600, color: '#86EFAC', fontFamily: font }}>
                              AI extracted the bill — review & edit before logging
                            </p>
                          </div>

                          {/* Extracted amount */}
                          <FormLabel>AMOUNT</FormLabel>
                          <AmountField value={amount} onChange={setAmount} />

                          {/* Extracted description */}
                          <FormLabel>MERCHANT / DESCRIPTION</FormLabel>
                          <div className="rounded-2xl px-4 py-3 mb-4"
                            style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}>
                            <input
                              type="text"
                              value={description}
                              onChange={e => { setDescription(e.target.value); setIsManual(false); }}
                              className="w-full bg-transparent outline-none"
                              style={{ fontSize: 14, fontWeight: 500, color: 'rgba(255,255,255,0.9)', fontFamily: font }}
                            />
                          </div>

                          {/* Category */}
                          <CategoryRow
                            category={category}
                            aiCategory={aiCategory}
                            confidence={confidence}
                            isManual={isManual}
                            showWand={showWand}
                            isLearning={isLearning}
                            hasLearned={hasLearned}
                            showPicker={showCategoryPicker}
                            onTogglePicker={() => setShowCategoryPicker(v => !v)}
                            onSelectCategory={handleCategorySelect}
                            onTeachAI={handleTeachAI}
                          />
                        </motion.div>
                      )}
                    </motion.div>
                  )}

                  {/* ════════ MANUAL MODE ════════ */}
                  {mode === 'manual' && (
                    <motion.div
                      key="manual"
                      initial={{ opacity: 0, x: -24 }}
                      animate={{ opacity: 1, x: 0 }}
                      exit={{ opacity: 0, x: 24 }}
                      transition={{ duration: 0.2 }}
                    >
                      {/* Amount – large prominent input */}
                      <div
                        className="rounded-3xl px-5 py-5 mb-4 flex items-center gap-3"
                        style={{
                          background: 'linear-gradient(135deg, rgba(124,58,237,0.12), rgba(99,102,241,0.06))',
                          border: '1px solid rgba(124,58,237,0.28)',
                        }}
                      >
                        <span style={{ fontSize: 30, fontWeight: 800, color: 'rgba(167,139,250,0.7)', fontFamily: font }}>₹</span>
                        <input
                          ref={amountRef}
                          type="number"
                          inputMode="decimal"
                          placeholder="0"
                          value={amount}
                          onChange={e => setAmount(e.target.value)}
                          className="flex-1 bg-transparent outline-none placeholder-white/20"
                          style={{ fontSize: 36, fontWeight: 900, color: '#fff', fontFamily: font, letterSpacing: '-0.5px' }}
                        />
                        {amount && parseFloat(amount) > 0 && (
                          <motion.div
                            initial={{ scale: 0 }}
                            animate={{ scale: 1 }}
                            className="flex items-center justify-center rounded-full"
                            style={{ width: 28, height: 28, background: 'rgba(34,197,94,0.2)', border: '1px solid rgba(34,197,94,0.4)', flexShrink: 0 }}
                          >
                            <Check size={14} color="#34D399" />
                          </motion.div>
                        )}
                      </div>

                      {/* Description + AI thinking */}
                      <FormLabel>DESCRIPTION</FormLabel>
                      <div className="rounded-2xl px-4 py-3 mb-4 relative"
                        style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}>
                        <input
                          type="text"
                          placeholder="e.g. Swiggy dinner, Uber ride…"
                          value={description}
                          onChange={e => { setDescription(e.target.value); setIsManual(false); setHasLearned(false); }}
                          className="w-full bg-transparent outline-none"
                          style={{ fontSize: 14, color: 'rgba(255,255,255,0.88)', fontFamily: font }}
                        />
                        {aiThinking && (
                          <div className="absolute right-3 top-1/2 -translate-y-1/2 flex items-center gap-1.5">
                            {[0, 1, 2].map(i => (
                              <motion.div
                                key={i}
                                animate={{ scale: [1, 1.5, 1], opacity: [0.4, 1, 0.4] }}
                                transition={{ duration: 0.7, repeat: Infinity, delay: i * 0.15 }}
                                style={{ width: 4, height: 4, borderRadius: '50%', background: '#818CF8' }}
                              />
                            ))}
                          </div>
                        )}
                      </div>

                      {/* Category */}
                      <CategoryRow
                        category={category}
                        aiCategory={aiCategory}
                        confidence={confidence}
                        isManual={isManual}
                        showWand={showWand}
                        isLearning={isLearning}
                        hasLearned={hasLearned}
                        showPicker={showCategoryPicker}
                        onTogglePicker={() => setShowCategoryPicker(v => !v)}
                        onSelectCategory={handleCategorySelect}
                        onTeachAI={handleTeachAI}
                      />
                    </motion.div>
                  )}
                </AnimatePresence>

                {/* ���═══════ BANK & PAYMENT (always shown when there's data) ════════ */}
                {(mode === 'manual' || scanState === 'done') && (
                  <motion.div
                    initial={{ opacity: 0, y: 10 }}
                    animate={{ opacity: 1, y: 0 }}
                    transition={{ delay: 0.05 }}
                  >
                    {/* Bank */}
                    <FormLabel>BANK</FormLabel>
                    <div className="flex gap-2 mb-5">
                      {BANKS.map(b => (
                        <motion.button
                          key={b}
                          whileTap={{ scale: 0.93 }}
                          onClick={() => setBank(b)}
                          className="flex-1 py-2.5 rounded-2xl"
                          style={{
                            fontSize: 12, fontWeight: 700, letterSpacing: 0.3, fontFamily: font,
                            background: bank === b ? 'rgba(124,58,237,0.22)' : 'rgba(255,255,255,0.04)',
                            border: `1px solid ${bank === b ? 'rgba(124,58,237,0.65)' : 'rgba(255,255,255,0.07)'}`,
                            color: bank === b ? '#A78BFA' : 'rgba(255,255,255,0.45)',
                            transition: 'all 0.18s',
                          }}
                        >
                          {b}
                        </motion.button>
                      ))}
                    </div>

                    {/* Payment type */}
                    <FormLabel>PAYMENT TYPE</FormLabel>
                    <div className="flex gap-2 mb-6">
                      {CARD_TYPES.map(ct => (
                        <motion.button
                          key={ct}
                          whileTap={{ scale: 0.93 }}
                          onClick={() => setCardType(ct)}
                          className="flex-1 py-2.5 rounded-2xl"
                          style={{
                            fontSize: 12, fontWeight: 600, fontFamily: font,
                            background: cardType === ct ? 'rgba(52,211,153,0.18)' : 'rgba(255,255,255,0.04)',
                            border: `1px solid ${cardType === ct ? 'rgba(52,211,153,0.55)' : 'rgba(255,255,255,0.07)'}`,
                            color: cardType === ct ? '#34D399' : 'rgba(255,255,255,0.45)',
                            transition: 'all 0.18s',
                          }}
                        >
                          {ct === 'Cash' ? '💵' : ct === 'Credit Card' ? '💳' : '🏦'} {ct}
                        </motion.button>
                      ))}
                    </div>

                    {/* Submit */}
                    <motion.button
                      whileTap={{ scale: 0.97 }}
                      onClick={handleSubmit}
                      disabled={!canSubmit}
                      className="w-full py-4 rounded-2xl flex items-center justify-center gap-2"
                      style={{
                        background: canSubmit ? 'linear-gradient(135deg, #7C3AED, #6366F1)' : 'rgba(255,255,255,0.05)',
                        border: canSubmit ? '1px solid rgba(124,58,237,0.5)' : '1px solid rgba(255,255,255,0.07)',
                        fontSize: 15, fontWeight: 800, fontFamily: font,
                        color: canSubmit ? '#fff' : 'rgba(255,255,255,0.2)',
                        boxShadow: canSubmit ? '0 4px 24px rgba(124,58,237,0.45)' : 'none',
                        letterSpacing: 0.3,
                        transition: 'all 0.25s',
                      }}
                    >
                      {canSubmit && <Check size={18} color="#fff" strokeWidth={2.5} />}
                      Log Expense
                    </motion.button>
                  </motion.div>
                )}
              </div>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}

// ── Helper sub-components ──────────────────────────────────────────────────

function FormLabel({ children }: { children: ReactNode }) {
  return (
    <p style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.35)', letterSpacing: 1.5, marginBottom: 8, fontFamily: "'Plus Jakarta Sans', sans-serif" }}>
      {children}
    </p>
  );
}

function AmountField({ value, onChange }: { value: string; onChange: (v: string) => void }) {
  return (
    <div className="rounded-2xl px-4 py-3 flex items-center gap-3 mb-4"
      style={{ background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.1)' }}>
      <span style={{ fontSize: 22, fontWeight: 700, color: 'rgba(255,255,255,0.4)', fontFamily: "'Plus Jakarta Sans', sans-serif" }}>₹</span>
      <input
        type="number"
        inputMode="decimal"
        value={value}
        onChange={e => onChange(e.target.value)}
        className="flex-1 bg-transparent outline-none"
        style={{ fontSize: 26, fontWeight: 800, color: '#fff', fontFamily: "'Plus Jakarta Sans', sans-serif", letterSpacing: '-0.5px' }}
      />
    </div>
  );
}

interface CategoryRowProps {
  category: string;
  aiCategory: string | null;
  confidence: Confidence;
  isManual: boolean;
  showWand: boolean;
  isLearning: boolean;
  hasLearned: boolean;
  showPicker: boolean;
  onTogglePicker: () => void;
  onSelectCategory: (cat: string) => void;
  onTeachAI: () => void;
}

function CategoryRow({
  category, aiCategory, confidence, isManual,
  showWand, isLearning, hasLearned,
  showPicker, onTogglePicker, onSelectCategory, onTeachAI,
}: CategoryRowProps) {
  const confMeta = CONF_META[isManual ? 'default' : confidence];
  const color = CATEGORY_COLORS[category] || '#818CF8';
  const icon = CATEGORY_ICONS[category] || '📦';

  return (
    <div className="mb-5">
      <FormLabel>CATEGORY</FormLabel>

      <div className="flex items-center gap-2">
        {/* Category selector */}
        <motion.button
          whileTap={{ scale: 0.97 }}
          onClick={onTogglePicker}
          className="flex-1 flex items-center gap-3 rounded-2xl px-4 py-3"
          style={{ background: 'rgba(255,255,255,0.05)', border: `1px solid ${showPicker ? `${color}50` : 'rgba(255,255,255,0.1)'}` }}
        >
          <motion.span
            key={icon}
            initial={{ scale: 0.6, opacity: 0 }}
            animate={{ scale: 1, opacity: 1 }}
            style={{ fontSize: 22 }}
          >
            {icon}
          </motion.span>
          <div className="flex-1 text-left">
            <p style={{ fontSize: 13, fontWeight: 700, color, fontFamily: "'Plus Jakarta Sans', sans-serif" }}>{category}</p>
          </div>

          {/* AI badge */}
          {!isManual && confidence !== 'default' ? (
            <motion.span
              key={confidence}
              initial={{ scale: 0.8, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              className="flex items-center gap-1 rounded-lg px-2 py-0.5"
              style={{ background: confMeta.bg, fontSize: 9, fontWeight: 700, color: confMeta.color, fontFamily: "'Plus Jakarta Sans', sans-serif", letterSpacing: 0.3, whiteSpace: 'nowrap' }}
            >
              <Sparkles size={8} />
              {confMeta.label}
            </motion.span>
          ) : hasLearned ? (
            <span className="flex items-center gap-1 rounded-lg px-2 py-0.5"
              style={{ background: 'rgba(129,140,248,0.18)', fontSize: 9, fontWeight: 700, color: '#818CF8', fontFamily: "'Plus Jakarta Sans', sans-serif" }}>
              <Brain size={8} /> AI Learned ✓
            </span>
          ) : isManual ? (
            <span className="flex items-center gap-1 rounded-lg px-2 py-0.5"
              style={{ background: 'rgba(251,191,36,0.15)', fontSize: 9, fontWeight: 700, color: '#FBBF24', fontFamily: "'Plus Jakarta Sans', sans-serif" }}>
              ✎ Manual
            </span>
          ) : null}

          <ChevronDown size={13} color="rgba(255,255,255,0.3)"
            style={{ transform: showPicker ? 'rotate(180deg)' : 'none', transition: '0.2s', flexShrink: 0 }} />
        </motion.button>

        {/* 🪄 Teach AI wand button */}
        <AnimatePresence>
          {showWand && (
            <motion.button
              initial={{ scale: 0, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              exit={{ scale: 0, opacity: 0 }}
              whileTap={{ scale: 0.88 }}
              onClick={onTeachAI}
              className="flex flex-col items-center justify-center rounded-2xl py-3 px-3 shrink-0"
              style={{
                background: isLearning ? 'rgba(245,158,11,0.2)' : 'rgba(124,58,237,0.2)',
                border: `1.5px solid ${isLearning ? 'rgba(245,158,11,0.5)' : 'rgba(124,58,237,0.5)'}`,
                minWidth: 58, gap: 3,
              }}
              title="Teach AI this correction"
            >
              {isLearning ? (
                <motion.div animate={{ rotate: 360 }} transition={{ duration: 0.8, repeat: Infinity, ease: 'linear' }}>
                  <Brain size={16} color="#F59E0B" />
                </motion.div>
              ) : (
                <Wand2 size={16} color="#A78BFA" />
              )}
              <span style={{
                fontSize: 8, fontWeight: 800, letterSpacing: 0.3, fontFamily: "'Plus Jakarta Sans', sans-serif",
                color: isLearning ? '#FCD34D' : '#A78BFA',
              }}>
                {isLearning ? 'LEARNING' : 'TEACH AI'}
              </span>
            </motion.button>
          )}
        </AnimatePresence>
      </div>

      {/* Wand hint text */}
      <AnimatePresence>
        {showWand && !isLearning && (
          <motion.p
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            style={{ fontSize: 10, color: 'rgba(255,255,255,0.3)', fontFamily: "'Plus Jakarta Sans', sans-serif", marginTop: 6 }}
          >
            🪄 Tap <span style={{ color: '#A78BFA', fontWeight: 600 }}>Teach AI</span> to remember this correction for future similar expenses
          </motion.p>
        )}
        {hasLearned && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            className="flex items-center gap-2 rounded-xl px-3 py-2 mt-2"
            style={{ background: 'rgba(129,140,248,0.1)', border: '1px solid rgba(129,140,248,0.25)' }}
          >
            <Brain size={12} color="#818CF8" />
            <p style={{ fontSize: 11, fontWeight: 600, color: '#A78BFA', fontFamily: "'Plus Jakarta Sans', sans-serif" }}>
              AI learned: future "{category}" expenses like this will be auto-detected
            </p>
          </motion.div>
        )}
      </AnimatePresence>

      {/* Category picker grid */}
      <AnimatePresence>
        {showPicker && (
          <motion.div
            initial={{ opacity: 0, height: 0 }}
            animate={{ opacity: 1, height: 'auto' }}
            exit={{ opacity: 0, height: 0 }}
            className="overflow-hidden"
          >
            <div className="grid grid-cols-4 gap-2 mt-3">
              {CATEGORIES.map((cat, i) => (
                <motion.button
                  key={cat}
                  initial={{ opacity: 0, scale: 0.85 }}
                  animate={{ opacity: 1, scale: 1 }}
                  transition={{ delay: i * 0.025 }}
                  whileTap={{ scale: 0.9 }}
                  onClick={() => onSelectCategory(cat)}
                  className="flex flex-col items-center gap-1.5 rounded-2xl py-3 px-1"
                  style={{
                    background: category === cat ? `${CATEGORY_COLORS[cat]}22` : 'rgba(255,255,255,0.04)',
                    border: `1.5px solid ${category === cat ? `${CATEGORY_COLORS[cat]}70` : 'rgba(255,255,255,0.07)'}`,
                  }}
                >
                  <span style={{ fontSize: 22 }}>{CATEGORY_ICONS[cat]}</span>
                  <span style={{ fontSize: 8.5, fontWeight: 700, color: category === cat ? CATEGORY_COLORS[cat] : 'rgba(255,255,255,0.38)', fontFamily: "'Plus Jakarta Sans', sans-serif", textAlign: 'center', lineHeight: 1.2 }}>
                    {cat}
                  </span>
                </motion.button>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}