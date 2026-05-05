import { useState, useEffect, useRef, useCallback } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
  Download, Star, X, MoreVertical, CheckCircle,
  Trash2, Upload, CloudLightning, Layers, CloudUpload
} from 'lucide-react';
import { useSettings } from '../utils/settingsContext';
import { usePalette } from '../utils/palette';

const F = "'Plus Jakarta Sans', sans-serif";
const CYAN = '#00E6E6';
const CYAN_L = '#C1FFFE';
const PURPLE = '#D575FF';
const BLUE = '#63BAFF';

// ── Types ─────────────────────────────────────────────────────────────────────
interface CloudFile {
  id: string;
  name: string;
  size: number; // bytes
  ext: string;
  date: string;
  starred: boolean;
  description?: string;
  tags?: string[];
  featured?: boolean;
}

type TransferPhase = 'preparing' | 'transferring' | 'finalizing' | 'done';
type TransferMode = 'upload' | 'download';

interface Transfer {
  file: CloudFile;
  mode: TransferMode;
  progress: number; // 0-100
  speed: number; // MB/s
  transferred: number; // bytes
  phase: TransferPhase;
  background: boolean;
}

// ── Static data ───────────────────────────────────────────────────────────────
const INITIAL_FILES: CloudFile[] = [
  {
    id: '1', name: 'Linguistic_Patterns_2024.pdf',
    size: 45.2 * 1024 * 1024, ext: 'pdf', date: 'Today',
    starred: true, featured: true,
    description: 'Deep neural analysis of semantic structures across multi-cloud repositories.',
    tags: ['ANALYSIS', '45.2 MB'],
  },
  {
    id: '2', name: 'Core_V_Zero.zip',
    size: 128.5 * 1024 * 1024, ext: 'zip', date: 'Yesterday',
    starred: false,
    description: 'Compiled core modules and runtime dependencies.',
  },
  {
    id: '3', name: 'Consciousness_Stream_09.mp4',
    size: 890.3 * 1024 * 1024, ext: 'mp4', date: 'Yesterday',
    starred: false,
  },
  {
    id: '4', name: 'Budget_Analysis_Q1.xlsx',
    size: 2.8 * 1024 * 1024, ext: 'xlsx', date: '2 days ago',
    starred: true,
  },
  {
    id: '5', name: 'Project_Presentation.pdf',
    size: 14.7 * 1024 * 1024, ext: 'pdf', date: '3 days ago',
    starred: false,
  },
  {
    id: '6', name: 'API_Documentation.docx',
    size: 5.1 * 1024 * 1024, ext: 'docx', date: '5 days ago',
    starred: true,
  },
];

const FILE_META: Record<string, { color: string; emoji: string }> = {
  pdf:    { color: '#EF4444', emoji: '📄' },
  zip:    { color: '#FBBF24', emoji: '🗜️' },
  mp4:    { color: '#818CF8', emoji: '🎬' },
  xlsx:   { color: '#34D399', emoji: '📊' },
  png:    { color: '#F472B6', emoji: '🖼️' },
  docx:   { color: '#60A5FA', emoji: '📝' },
  mp3:    { color: '#A78BFA', emoji: '🎵' },
  default:{ color: '#94A3B8', emoji: '📁' },
};

const getFileMeta = (ext: string) => FILE_META[ext] ?? FILE_META.default;


// ── Formatters ────────────────────────────────────────────────────────────────
const fmtBytes = (b: number) => {
  if (b >= 1073741824) return `${(b / 1073741824).toFixed(1)} GB`;
  if (b >= 1048576)    return `${(b / 1048576).toFixed(1)} MB`;
  if (b >= 1024)       return `${(b / 1024).toFixed(1)} KB`;
  return `${b} B`;
};

const fmtETA = (sec: number) => {
  if (sec <= 0 || !isFinite(sec)) return '00:00';
  const m = Math.floor(sec / 60);
  const s = Math.floor(sec % 60);
  return `${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
};

// ── Circular Progress Ring ────────────────────────────────────────────────────
function CircularRing({ progress, phase, mode }: { progress: number; phase: TransferPhase; mode: TransferMode }) {
  const r = 85;
  const circ = 2 * Math.PI * r;
  const offset = circ * (1 - Math.min(progress, 100) / 100);
  const ringColor = mode === 'download' ? BLUE : CYAN;
  const isDone = phase === 'done';

  const phaseLabel: Record<TransferPhase, string> = {
    preparing:   'Initializing...',
    transferring:'Fragmenting Data',
    finalizing:  'Verifying...',
    done:        'Complete',
  };

  return (
    <div style={{ position: 'relative', width: 240, height: 240, flexShrink: 0 }}>
      {/* Atmospheric glow behind ring */}
      <div style={{
        position: 'absolute', inset: 0, borderRadius: '50%',
        background: `radial-gradient(circle, ${ringColor}09 0%, transparent 68%)`,
        filter: 'blur(18px)',
      }} />

      <svg width={240} height={240} viewBox="0 0 200 200" style={{ transform: 'rotate(-90deg)', display: 'block' }}>
        <defs>
          <filter id="cld-glow" x="-30%" y="-30%" width="160%" height="160%">
            <feGaussianBlur in="SourceAlpha" stdDeviation="5" result="blur" />
            <feFlood floodColor={ringColor} floodOpacity="0.5" result="col" />
            <feComposite in="col" in2="blur" operator="in" result="shad" />
            <feMerge><feMergeNode in="shad" /><feMergeNode in="SourceGraphic" /></feMerge>
          </filter>
        </defs>
        {/* Track */}
        <circle cx={100} cy={100} r={r} fill="none" stroke="#1A1A1A" strokeWidth="8" />
        {/* Progress arc */}
        <motion.circle
          cx={100} cy={100} r={r}
          fill="none"
          stroke={isDone ? '#34D399' : ringColor}
          strokeWidth="8"
          strokeLinecap="round"
          strokeDasharray={circ}
          animate={{ strokeDashoffset: isDone ? 0 : offset, stroke: isDone ? '#34D399' : ringColor }}
          transition={{ duration: 0.3, ease: 'linear', stroke: { duration: 0.5 } }}
          filter="url(#cld-glow)"
        />
      </svg>

      {/* Center label */}
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
        <AnimatePresence mode="wait">
          {isDone ? (
            <motion.div key="done"
              initial={{ scale: 0.3, opacity: 0 }}
              animate={{ scale: 1, opacity: 1 }}
              transition={{ type: 'spring', damping: 18, stiffness: 280 }}>
              <CheckCircle size={56} color="#34D399" strokeWidth={1.8} />
            </motion.div>
          ) : (
            <motion.div key="pct" className="flex flex-col items-center" initial={{ opacity: 0 }} animate={{ opacity: 1 }}>
              <p style={{ fontSize: 46, fontWeight: 900, color: '#fff', fontFamily: F, letterSpacing: '-2.5px', lineHeight: 1 }}>
                {Math.floor(progress)}%
              </p>
              <p style={{ fontSize: 9, color: '#ABABAB', letterSpacing: 2, textTransform: 'uppercase', marginTop: 6, fontFamily: F }}>
                {phaseLabel[phase]}
              </p>
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      {/* Floating decorative particles */}
      <motion.div
        animate={{ y: [-5, 5, -5], opacity: [0.7, 1, 0.7] }}
        transition={{ duration: 3.2, repeat: Infinity, ease: 'easeInOut' }}
        style={{ position: 'absolute', top: 6, right: 22, width: 8, height: 8, borderRadius: 12, background: PURPLE, boxShadow: `0 0 14px ${PURPLE}` }} />
      <motion.div
        animate={{ y: [3, -3, 3], opacity: [1, 0.6, 1] }}
        transition={{ duration: 2.4, repeat: Infinity, ease: 'easeInOut', delay: 1 }}
        style={{ position: 'absolute', bottom: 42, left: 2, width: 6, height: 6, borderRadius: 12, background: CYAN, boxShadow: `0 0 8px ${CYAN}` }} />
    </div>
  );
}

// ── Transfer Modal ────────────────────────────────────────────────────────────
function TransferModal({ transfer, onCancel, onBackground }: {
  transfer: Transfer;
  onCancel: () => void;
  onBackground: () => void;
}) {
  const meta = getFileMeta(transfer.file.ext);
  const isDone = transfer.phase === 'done';
  const etaSec = transfer.speed > 0
    ? (transfer.file.size - transfer.transferred) / (transfer.speed * 1024 * 1024)
    : 0;

  return (
    <motion.div
      initial={{ y: '100%', opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      exit={{ y: '100%', opacity: 0 }}
      transition={{ type: 'spring', damping: 28, stiffness: 280, mass: 1 }}
      style={{
        position: 'absolute', inset: 0, background: '#000',
        overflowY: 'auto', scrollbarWidth: 'none', zIndex: 50,
      }}
    >
      {/* Atmospheric background blurs */}
      <div style={{ position: 'absolute', top: '20%', left: '50%', transform: 'translate(-50%,-50%)', width: 500, height: 500, borderRadius: 12, background: 'rgba(213,117,255,0.08)', filter: 'blur(60px)', pointerEvents: 'none' }} />
      <div style={{ position: 'absolute', bottom: 0, right: 0, width: 400, height: 400, borderRadius: 12, background: 'rgba(193,255,254,0.04)', filter: 'blur(50px)', pointerEvents: 'none' }} />

      {/* Mini header inside modal */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '16px 20px 12px', borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{ width: 28, height: 28, borderRadius: 8, background: 'rgba(0,230,230,0.12)', border: `1px solid ${CYAN}30`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <CloudLightning size={14} color={CYAN} strokeWidth={2} />
          </div>
          <span style={{ fontSize: 15, fontWeight: 800, background: `linear-gradient(90deg, #67e8f9, #06b6d4)`, WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent', fontFamily: F, letterSpacing: '-0.3px' }}>
            Ethereal Vault
          </span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 4, padding: '4px 10px', borderRadius: 20, background: 'rgba(99,186,255,0.1)', border: `1px solid ${BLUE}30` }}>
            <div style={{ width: 6, height: 6, borderRadius: 3, background: BLUE, boxShadow: `0 0 6px ${BLUE}` }} />
            <span style={{ fontSize: 9, fontWeight: 700, color: BLUE, fontFamily: F, letterSpacing: 0.8 }}>GDRIVE SYNC</span>
          </div>
          <motion.button whileTap={{ scale: 0.88 }} onClick={onCancel}
            style={{ width: 32, height: 32, borderRadius: 10, background: 'rgba(255,255,255,0.06)', border: '1px solid rgba(255,255,255,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <X size={15} color="rgba(255,255,255,0.5)" />
          </motion.button>
        </div>
      </div>

      <div style={{ padding: '28px 20px 100px', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>

        {/* ── Ring ── */}
        <CircularRing progress={transfer.progress} phase={transfer.phase} mode={transfer.mode} />

        {/* ── File metadata card ── */}
        <motion.div
          initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.15 }}
          style={{ width: '100%', marginTop: 24, borderRadius: 12, background: 'rgba(38,38,38,0.4)', border: '1px solid rgba(255,255,255,0.05)', backdropFilter: 'blur(10px)', marginBottom: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, padding: '14px 18px' }}>
            <div style={{ width: 40, height: 40, borderRadius: 8, background: `${meta.color}18`, border: `1px solid ${meta.color}30`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
              <span style={{ fontSize: 18 }}>{meta.emoji}</span>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <p style={{ fontSize: 12, fontWeight: 800, color: '#fff', fontFamily: F, letterSpacing: 0.5, textTransform: 'uppercase', overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>
                {transfer.file.name}
              </p>
              <p style={{ fontSize: 9, color: '#ABABAB', fontFamily: F, marginTop: 2, letterSpacing: 1, textTransform: 'uppercase' }}>
                Secure Encrypted Channel
              </p>
            </div>
          </div>
        </motion.div>

        {/* ── Metrics bento grid ── */}
        <motion.div
          initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.2 }}
          style={{ width: '100%', display: 'grid', gridTemplateColumns: '1fr 1fr', gridTemplateRows: 'auto auto', gap: 10 }}>
          {/* Speed */}
          <div style={{ background: '#131313', borderRadius: 18, padding: 18 }}>
            <p style={{ fontSize: 9, color: '#ABABAB', fontFamily: F, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 6 }}>Speed</p>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 3 }}>
              <motion.p
                key={Math.floor(transfer.speed * 10)}
                animate={{ opacity: [0.7, 1] }} transition={{ duration: 0.2 }}
                style={{ fontSize: 26, fontWeight: 800, color: CYAN_L, fontFamily: F, letterSpacing: '-0.5px', lineHeight: 1 }}>
                {transfer.speed.toFixed(1)}
              </motion.p>
              <p style={{ fontSize: 12, color: '#ABABAB', fontFamily: F }}>MB/s</p>
            </div>
          </div>
          {/* ETA */}
          <div style={{ background: '#131313', borderRadius: 18, padding: 18 }}>
            <p style={{ fontSize: 9, color: '#ABABAB', fontFamily: F, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 6 }}>ETA</p>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 3 }}>
              <motion.p
                key={fmtETA(etaSec)}
                animate={{ opacity: [0.7, 1] }} transition={{ duration: 0.2 }}
                style={{ fontSize: 26, fontWeight: 800, color: PURPLE, fontFamily: F, letterSpacing: '-0.5px', lineHeight: 1 }}>
                {isDone ? '00:00' : fmtETA(etaSec)}
              </motion.p>
              <p style={{ fontSize: 12, color: '#ABABAB', fontFamily: F }}>sec</p>
            </div>
          </div>
          {/* Volume Transfer — spans 2 cols */}
          <div style={{ gridColumn: '1 / span 2', background: '#191919', borderRadius: 18, padding: '18px 20px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div>
              <p style={{ fontSize: 9, color: '#ABABAB', fontFamily: F, letterSpacing: 1.2, textTransform: 'uppercase', marginBottom: 4 }}>Volume Transfer</p>
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 4 }}>
                <motion.p
                  style={{ fontSize: 22, fontWeight: 800, color: '#fff', fontFamily: F, lineHeight: 1 }}
                  key={Math.floor(transfer.transferred / 1048576)}>
                  {fmtBytes(transfer.transferred)}
                </motion.p>
                <p style={{ fontSize: 12, color: '#ABABAB', fontFamily: F }}>/ {fmtBytes(transfer.file.size)}</p>
              </div>
              {/* Thin progress bar */}
              <div style={{ marginTop: 8, height: 3, borderRadius: 99, background: 'rgba(255,255,255,0.08)', overflow: 'hidden', width: 160 }}>
                <motion.div
                  animate={{ width: `${transfer.progress}%` }}
                  transition={{ duration: 0.3, ease: 'linear' }}
                  style={{ height: '100%', borderRadius: 99, background: `linear-gradient(90deg, ${CYAN}, ${PURPLE})`, boxShadow: `0 0 8px ${CYAN}60` }} />
              </div>
            </div>
            <div style={{ width: 32, height: 32, borderRadius: 12, background: 'rgba(59,173,252,0.18)', border: '2px solid #191919', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {transfer.mode === 'upload' ? <Upload size={13} color={BLUE} strokeWidth={2.5} /> : <Download size={13} color={BLUE} strokeWidth={2.5} />}
            </div>
          </div>
        </motion.div>

        {/* ── Action buttons ── */}
        <motion.div
          initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.28 }}
          style={{ width: '100%', marginTop: 28, display: 'flex', gap: 14 }}>
          <motion.button whileTap={{ scale: 0.96 }} onClick={onCancel}
            style={{ flex: 1, height: 52, borderRadius: 14, background: 'rgba(38,38,38,0.3)', border: '1px solid rgba(72,72,72,0.2)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontSize: 12, fontWeight: 800, color: '#fff', fontFamily: F, letterSpacing: 1.2, textTransform: 'uppercase' }}>Cancel</span>
          </motion.button>
          <motion.button whileTap={{ scale: 0.96 }} onClick={isDone ? onCancel : onBackground}
            style={{ flex: 1, height: 52, borderRadius: 14, background: `linear-gradient(90deg, ${CYAN}, #0ff)`, boxShadow: '0 0 20px rgba(0,255,255,0.2)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontSize: 12, fontWeight: 800, color: '#004343', fontFamily: F, letterSpacing: 1.2, textTransform: 'uppercase' }}>
              {isDone ? 'Done' : 'Background'}
            </span>
          </motion.button>
        </motion.div>
      </div>
    </motion.div>
  );
}

// ── Big Upload Zone ───────────────────────────────────────────────────────────
function UploadZone({ onTrigger }: { onTrigger: () => void }) {
  const [pressed, setPressed] = useState(false);
  const [dragOver, setDragOver] = useState(false);

  return (
    <motion.button
      onClick={onTrigger}
      onTapStart={() => setPressed(true)}
      onTap={() => setPressed(false)}
      onTapCancel={() => setPressed(false)}
      onDragOver={(e: React.DragEvent) => { e.preventDefault(); setDragOver(true); }}
      onDragLeave={() => setDragOver(false)}
      animate={{
        scale: pressed ? 0.97 : 1,
        boxShadow: dragOver
          ? `0 0 0 2px ${CYAN}, 0 0 40px ${CYAN}40`
          : `0 0 0 0px transparent`,
      }}
      transition={{ type: 'spring', damping: 22, stiffness: 340 }}
      style={{
        width: '100%', cursor: 'pointer', border: 'none', outline: 'none',
        background: dragOver
          ? `rgba(0,230,230,0.06)`
          : `linear-gradient(145deg, rgba(0,230,230,0.04) 0%, rgba(213,117,255,0.025) 100%)`,
        borderRadius: 22, padding: '30px 20px 28px',
        display: 'flex', flexDirection: 'column', alignItems: 'center',
        position: 'relative', overflow: 'hidden',
        transition: 'background 0.2s',
      }}>
      {/* Animated dashed border */}
      <svg style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', pointerEvents: 'none' }}>
        <rect
          x="1" y="1" width="calc(100% - 2px)" height="calc(100% - 2px)"
          rx="21" ry="21" fill="none"
          stroke={dragOver ? CYAN : `rgba(0,230,230,0.30)`}
          strokeWidth="1.5" strokeDasharray="7 5"
          style={{ transition: 'stroke 0.25s' }}
        />
      </svg>

      {/* Breathing radial glow */}
      <motion.div
        animate={{ scale: [1, 1.25, 1], opacity: [0.35, 0.6, 0.35] }}
        transition={{ duration: 3.5, repeat: Infinity, ease: 'easeInOut' }}
        style={{ position: 'absolute', top: '50%', left: '50%', transform: 'translate(-50%,-50%)', width: 200, height: 130, borderRadius: '50%', background: `radial-gradient(ellipse, ${CYAN}15 0%, transparent 70%)`, pointerEvents: 'none' }} />

      {/* Bouncing cloud upload icon */}
      <motion.div
        animate={{ y: [0, -7, 0] }}
        transition={{ duration: 1.9, repeat: Infinity, ease: 'easeInOut' }}
        style={{ position: 'relative', zIndex: 1, marginBottom: 14 }}>
        <div style={{ width: 68, height: 68, borderRadius: 20, background: `linear-gradient(145deg, ${CYAN}20, ${CYAN}0a)`, border: `1.5px solid ${CYAN}35`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <CloudUpload size={30} color={CYAN} strokeWidth={1.6} />
        </div>
        {/* Glow under icon */}
        <div style={{ position: 'absolute', bottom: -6, left: '50%', transform: 'translateX(-50%)', width: 40, height: 12, borderRadius: '50%', background: `${CYAN}30`, filter: 'blur(6px)' }} />
      </motion.div>

      {/* Main label */}
      <p style={{ fontSize: 17, fontWeight: 800, color: '#fff', fontFamily: F, letterSpacing: '-0.3px', marginBottom: 6, position: 'relative', zIndex: 1 }}>
        {dragOver ? 'Drop to upload' : 'Tap to upload'}
      </p>

      {/* Subtitle */}
      <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.3)', fontFamily: F, marginBottom: 16, position: 'relative', zIndex: 1 }}>
        PDF · ZIP · MP4 · XLSX · PNG · DOCX
      </p>

      {/* File type pill row */}
      <div style={{ display: 'flex', gap: 6, position: 'relative', zIndex: 1 }}>
        {['📄', '🗜️', '🎬', '📊', '🖼️'].map((emoji, i) => (
          <motion.div
            key={i}
            animate={{ opacity: [0.5, 1, 0.5] }}
            transition={{ duration: 2.5, repeat: Infinity, delay: i * 0.3, ease: 'easeInOut' }}
            style={{ width: 30, height: 30, borderRadius: 8, background: 'rgba(255,255,255,0.05)', border: '1px solid rgba(255,255,255,0.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 14 }}>
            {emoji}
          </motion.div>
        ))}
      </div>

      {/* Bottom shimmer line */}
      <motion.div
        animate={{ opacity: [0.3, 0.8, 0.3], scaleX: [0.6, 1, 0.6] }}
        transition={{ duration: 2.4, repeat: Infinity, ease: 'easeInOut' }}
        style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 1, background: `linear-gradient(90deg, transparent, ${CYAN}70, transparent)` }} />
    </motion.button>
  );
}

// ── File Icon Box ─────────────────────────────────────────────────────────────
function FileIconBox({ ext, size = 40 }: { ext: string; size?: number }) {
  const meta = getFileMeta(ext);
  return (
    <div style={{
      width: size, height: size, flexShrink: 0,
      background: `${meta.color}15`, border: `1px solid ${meta.color}28`,
      borderRadius: Math.round(size * 0.28),
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <span style={{ fontSize: Math.round(size * 0.44) }}>{meta.emoji}</span>
    </div>
  );
}

// ── Main Page ─────────────────────────────────────────────────────────────────
export function CloudPage() {
  const [files, setFiles] = useState<CloudFile[]>(INITIAL_FILES);
  const [activeTab, setActiveTab] = useState<'files' | 'starred'>('files');
  const [transfer, setTransfer] = useState<Transfer | null>(null);
  const [fileMenu, setFileMenu] = useState<string | null>(null); // file id
  const fileInputRef = useRef<HTMLInputElement>(null);
  const intervalRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const { openSettings } = useSettings();
  const p = usePalette();

  const TOTAL_GB = 100;
  const USED_GB = 15.4 + files.filter(f => !INITIAL_FILES.find(i => i.id === f.id)).reduce((s, f) => s + f.size / 1073741824, 0);
  const usagePct = USED_GB / TOTAL_GB;

  const displayFiles = activeTab === 'starred' ? files.filter(f => f.starred) : files;

  // ── Transfer simulation ─────────────────────────────────────────────────────
  const startTransfer = useCallback((file: CloudFile, mode: TransferMode) => {
    if (intervalRef.current) clearInterval(intervalRef.current);

    setTransfer({ file, mode, progress: 0, speed: 10 + Math.random() * 6, transferred: 0, phase: 'preparing', background: false });

    // After 900ms → transferring
    setTimeout(() => {
      setTransfer(prev => prev ? { ...prev, phase: 'transferring' } : null);

      intervalRef.current = setInterval(() => {
        setTransfer(prev => {
          if (!prev || prev.phase === 'done') return prev;

          // Realistic speed fluctuation ±25%
          const newSpeed = Math.max(1.5, prev.speed * (0.78 + Math.random() * 0.44));
          const addedBytes = newSpeed * 1048576 * 0.1; // 100ms tick
          const newTransferred = Math.min(prev.file.size, prev.transferred + addedBytes);
          const newProgress = (newTransferred / prev.file.size) * 100;

          if (newTransferred >= prev.file.size) {
            clearInterval(intervalRef.current!);
            setTimeout(() => {
              setTransfer(p => p ? { ...p, phase: 'finalizing', progress: 99, speed: 0 } : null);
              setTimeout(() => {
                setTransfer(p => p ? { ...p, phase: 'done', progress: 100 } : null);
                setTimeout(() => setTransfer(null), 2800);
              }, 900);
            }, 200);
            return { ...prev, progress: 99.5, transferred: prev.file.size, speed: newSpeed };
          }

          const phase = newProgress >= 92 ? 'finalizing' : 'transferring';
          return { ...prev, speed: newSpeed, transferred: newTransferred, progress: newProgress, phase };
        });
      }, 100);
    }, 900);
  }, []);

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0];
    if (!f) return;
    const newFile: CloudFile = {
      id: crypto.randomUUID(),
      name: f.name,
      size: f.size > 0 ? f.size : 40 * 1024 * 1024,
      ext: f.name.split('.').pop()?.toLowerCase() ?? 'default',
      date: 'Just now',
      starred: false,
    };
    setFiles(prev => [newFile, ...prev]);
    startTransfer(newFile, 'upload');
    e.target.value = '';
  };

  const handleDownload = (file: CloudFile) => { startTransfer(file, 'download'); setFileMenu(null); };
  const handleToggleStar = (id: string) => { setFiles(p => p.map(f => f.id === id ? { ...f, starred: !f.starred } : f)); setFileMenu(null); };
  const handleDelete = (id: string) => { setFiles(p => p.filter(f => f.id !== id)); setFileMenu(null); };
  const handleCancel = () => { if (intervalRef.current) clearInterval(intervalRef.current); setTransfer(null); };
  const handleBackground = () => setTransfer(p => p ? { ...p, background: true } : null);

  useEffect(() => () => { if (intervalRef.current) clearInterval(intervalRef.current); }, []);

  const featuredFile = displayFiles[0];
  const secondFile = displayFiles[1];
  const recentFiles = displayFiles.slice(2);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100%', background: p.bg, position: 'relative' }}>
      <input type="file" ref={fileInputRef} onChange={handleFileSelect} style={{ display: 'none' }} />

      {/* ── Header ── */}
      <div style={{
        height: 52, flexShrink: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 16px',
        borderBottom: `1px solid ${p.border}`,
        background: p.headerBg,
        backdropFilter: 'blur(12px)',
      }}>
        <motion.button
          whileTap={{ scale: 0.84 }}
          onClick={openSettings}
          style={{ width: 32, height: 32, borderRadius: '50%', cursor: 'pointer', background: 'linear-gradient(135deg, #0D59F2, #22D3EE)', padding: 2, border: 'none', outline: 'none', flexShrink: 0 }}
        >
          <div style={{ width: '100%', height: '100%', borderRadius: '50%', background: p.isDark ? '#111' : '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontSize: 11, fontWeight: 800, color: p.isDark ? '#fff' : '#0F172A', fontFamily: F }}>AR</span>
          </div>
        </motion.button>
        <span style={{ fontSize: 17, fontWeight: 800, color: p.text, fontFamily: F, letterSpacing: '-0.3px' }}>Cloud Storage</span>
        {/* GDrive live status pill */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 5, padding: '5px 11px', borderRadius: 20, background: `rgba(99,186,255,0.08)`, border: `1px solid ${BLUE}22` }}>
          <motion.div
            animate={{ opacity: [0.5, 1, 0.5] }}
            transition={{ duration: 2.2, repeat: Infinity }}
            style={{ width: 6, height: 6, borderRadius: 3, background: BLUE, boxShadow: `0 0 6px ${BLUE}` }} />
          <span style={{ fontSize: 9, fontWeight: 700, color: BLUE, fontFamily: F, letterSpacing: 0.6 }}>GDrive</span>
        </div>
      </div>

      {/* ── Scrollable body ── */}
      <div style={{ flex: 1, overflowY: 'auto', scrollbarWidth: 'none' }}>
        <div style={{ padding: '16px 16px 100px' }}>

          {/* ── Storage Capacity Card ── */}
          <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }}
            style={{ background: '#131313', borderRadius: 22, padding: 28, marginBottom: 12, border: '1px solid rgba(72,72,72,0.12)', overflow: 'hidden', position: 'relative' }}>
            {/* Atmospheric blurs inside card */}
            <div style={{ position: 'absolute', top: -60, right: -60, width: 200, height: 200, borderRadius: 12, background: 'rgba(213,117,255,0.18)', filter: 'blur(48px)', pointerEvents: 'none' }} />
            <div style={{ position: 'absolute', bottom: -30, left: -30, width: 150, height: 150, borderRadius: 12, background: 'rgba(193,255,254,0.08)', filter: 'blur(36px)', pointerEvents: 'none' }} />

            <div style={{ position: 'relative' }}>
              <p style={{ fontSize: 10, fontWeight: 700, color: '#ABABAB', fontFamily: F, letterSpacing: 2.2, textTransform: 'uppercase', marginBottom: 10 }}>System Capacity</p>

              {/* Usage numbers */}
              <div style={{ display: 'flex', alignItems: 'baseline', gap: 0, marginBottom: 14 }}>
                <span style={{ fontSize: 44, fontWeight: 900, color: '#fff', fontFamily: F, letterSpacing: '-2px', lineHeight: 1 }}>{USED_GB.toFixed(1)}</span>
                <span style={{ fontSize: 20, fontWeight: 600, color: CYAN_L, fontFamily: F, marginLeft: 4, letterSpacing: '-0.3px' }}>GB</span>
                <span style={{ fontSize: 16, color: '#484848', fontFamily: F, margin: '0 8px' }}>/</span>
                <span style={{ fontSize: 20, fontWeight: 300, color: '#ABABAB', fontFamily: F }}>{TOTAL_GB} GB</span>
              </div>

              {/* GDrive indicator */}
              <div style={{ display: 'inline-flex', alignItems: 'center', gap: 8, background: 'rgba(38,38,38,0.5)', border: '1px solid rgba(72,72,72,0.25)', borderRadius: 10, padding: '6px 12px', marginBottom: 16 }}>
                <div style={{ width: 7, height: 7, borderRadius: 99, background: BLUE, boxShadow: `0 0 8px ${BLUE}` }} />
                <span style={{ fontSize: 10, fontWeight: 700, color: '#fff', fontFamily: F, letterSpacing: 0.8, textTransform: 'uppercase' }}>Google Drive Connected</span>
              </div>

              {/* Glowing progress bar */}
              <div style={{ height: 6, borderRadius: 12, background: '#262626', overflow: 'hidden' }}>
                <motion.div
                  initial={{ width: 0 }}
                  animate={{ width: `${usagePct * 100}%` }}
                  transition={{ duration: 1.4, ease: 'easeOut', delay: 0.3 }}
                  style={{ height: '100%', borderRadius: 12, background: `linear-gradient(90deg, ${CYAN}, ${PURPLE})`, boxShadow: `0 0 14px rgba(0,255,255,0.4)` }} />
              </div>

              <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.22)', fontFamily: F, marginTop: 8 }}>
                {(TOTAL_GB - USED_GB).toFixed(1)} GB free · {Math.round(usagePct * 100)}% used
              </p>
            </div>
          </motion.div>

          {/* ── Big Upload Zone ── */}
          <motion.div initial={{ opacity: 0, y: 10 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }} style={{ marginBottom: 14 }}>
            <UploadZone onTrigger={() => fileInputRef.current?.click()} />
          </motion.div>

          {/* ── Files / Starred Tabs ── */}
          <div style={{ display: 'flex', borderBottom: '1px solid rgba(72,72,72,0.12)', marginBottom: 16, position: 'relative' }}>
            {(['files', 'starred'] as const).map(tab => (
              <motion.button key={tab} whileTap={{ scale: 0.95 }} onClick={() => setActiveTab(tab)}
                style={{ padding: '12px 28px', position: 'relative', background: 'none', border: 'none', cursor: 'pointer' }}>
                <span style={{ fontSize: 14, fontWeight: activeTab === tab ? 600 : 400, color: activeTab === tab ? CYAN_L : '#ABABAB', fontFamily: F, letterSpacing: 0.3, textTransform: 'capitalize' }}>
                  {tab}
                </span>
                {activeTab === tab && (
                  <motion.div layoutId="cloud-tab" style={{ position: 'absolute', bottom: 0, left: 0, right: 0, height: 2, background: CYAN_L, borderRadius: 2, boxShadow: `0 -3px 8px ${CYAN_L}` }} transition={{ type: 'spring', damping: 28, stiffness: 340 }} />
                )}
              </motion.button>
            ))}
          </div>

          {displayFiles.length === 0 ? (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', paddingTop: 60, gap: 12 }}>
              <motion.div animate={{ scale: [1, 1.07, 1] }} transition={{ duration: 2.5, repeat: Infinity }}>
                <Star size={40} color={`${CYAN}60`} strokeWidth={1.5} />
              </motion.div>
              <p style={{ fontSize: 14, fontWeight: 700, color: 'rgba(255,255,255,0.3)', fontFamily: F }}>No starred files yet</p>
              <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.18)', fontFamily: F, textAlign: 'center' }}>Tap ··· on a file and select Star</p>
            </div>
          ) : (
            <>
              {/* ── Featured card ── */}
              {featuredFile && (
                <motion.div key={featuredFile.id} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.05 }}
                  style={{ background: '#131313', borderRadius: 22, padding: '20px 20px 18px', marginBottom: 10, border: '1px solid rgba(72,72,72,0.1)', position: 'relative', overflow: 'hidden' }}>
                  {/* Subtle inner glow */}
                  <div style={{ position: 'absolute', top: -30, right: -30, width: 140, height: 140, borderRadius: 99, background: `${getFileMeta(featuredFile.ext).color}08`, filter: 'blur(30px)', pointerEvents: 'none' }} />

                  <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 14, position: 'relative' }}>
                    {/* File type icon in colored box */}
                    <div style={{ width: 44, height: 44, borderRadius: 14, background: `${PURPLE}18`, border: `1px solid ${PURPLE}28`, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      <span style={{ fontSize: 20 }}>{getFileMeta(featuredFile.ext).emoji}</span>
                    </div>
                    <motion.button whileTap={{ scale: 0.84 }} onClick={() => setFileMenu(fileMenu === featuredFile.id ? null : featuredFile.id)}>
                      <MoreVertical size={16} color="rgba(255,255,255,0.3)" />
                    </motion.button>
                  </div>

                  <p style={{ fontSize: 22, fontWeight: 700, color: '#fff', fontFamily: F, letterSpacing: '-0.4px', lineHeight: 1.25, marginBottom: 8, position: 'relative' }}>
                    {featuredFile.name.replace(/\.[^/.]+$/, '').replace(/_/g, ' ')}
                  </p>
                  {featuredFile.description && (
                    <p style={{ fontSize: 13, color: '#ABABAB', fontFamily: F, lineHeight: 1.6, marginBottom: 14, position: 'relative' }}>
                      {featuredFile.description}
                    </p>
                  )}

                  {/* Tags */}
                  <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', position: 'relative' }}>
                    {featuredFile.tags?.map(tag => (
                      <span key={tag} style={{ padding: '3px 10px', borderRadius: 5, background: '#1F1F1F', fontSize: 10, fontWeight: 700, color: '#F0C1FF', fontFamily: F, letterSpacing: 0.8, textTransform: 'uppercase' }}>
                        {tag}
                      </span>
                    ))}
                    <span style={{ padding: '3px 10px', borderRadius: 5, background: '#1F1F1F', fontSize: 10, fontWeight: 700, color: '#ABABAB', fontFamily: F }}>{featuredFile.date}</span>
                  </div>
                </motion.div>
              )}

              {/* ── Second card (clean) ── */}
              {secondFile && (
                <motion.div key={secondFile.id} initial={{ opacity: 0, y: 12 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.1 }}
                  style={{ background: '#131313', borderRadius: 22, padding: '16px 18px', marginBottom: 14, border: '1px solid rgba(72,72,72,0.1)' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
                    <FileIconBox ext={secondFile.ext} size={42} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <p style={{ fontSize: 14, fontWeight: 700, color: '#fff', fontFamily: F, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>
                        {secondFile.name}
                      </p>
                      <p style={{ fontSize: 11, color: '#ABABAB', fontFamily: F, marginTop: 3 }}>
                        {fmtBytes(secondFile.size)} · {secondFile.date}
                      </p>
                    </div>
                    <motion.button whileTap={{ scale: 0.82 }} onClick={() => setFileMenu(fileMenu === secondFile.id ? null : secondFile.id)}>
                      <MoreVertical size={16} color="rgba(255,255,255,0.3)" />
                    </motion.button>
                  </div>
                </motion.div>
              )}

              {/* ── Recent files list ── */}
              {recentFiles.length > 0 && (
                <>
                  <p style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.3)', fontFamily: F, letterSpacing: 1.6, textTransform: 'uppercase', marginBottom: 8, paddingLeft: 2 }}>
                    RECENT FILES
                  </p>
                  <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                    {recentFiles.map((f, i) => (
                      <motion.div key={f.id}
                        initial={{ opacity: 0, y: 8 }} animate={{ opacity: 1, y: 0 }} transition={{ delay: 0.12 + i * 0.05 }}
                        style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 6px', borderBottom: i < recentFiles.length - 1 ? '1px solid rgba(255,255,255,0.05)' : 'none' }}>
                        <FileIconBox ext={f.ext} size={38} />
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <p style={{ fontSize: 13, fontWeight: 600, color: 'rgba(255,255,255,0.88)', fontFamily: F, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>
                            {f.name}
                          </p>
                          <p style={{ fontSize: 10, color: 'rgba(255,255,255,0.28)', fontFamily: F, marginTop: 2, textTransform: 'uppercase', letterSpacing: 0.6 }}>
                            Uploaded {f.date}
                          </p>
                        </div>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
                          <motion.button whileTap={{ scale: 0.82 }} onClick={() => handleToggleStar(f.id)}>
                            <Star size={16} color={f.starred ? '#FBBF24' : 'rgba(255,255,255,0.25)'} fill={f.starred ? '#FBBF24' : 'none'} />
                          </motion.button>
                          <motion.button whileTap={{ scale: 0.82 }} onClick={() => setFileMenu(fileMenu === f.id ? null : f.id)}>
                            <MoreVertical size={15} color="rgba(255,255,255,0.22)" />
                          </motion.button>
                        </div>
                      </motion.div>
                    ))}
                  </div>
                </>
              )}
            </>
          )}
        </div>
      </div>

      {/* ── Background transfer mini banner ── */}
      <AnimatePresence>
        {transfer?.background && (
          <motion.div
            initial={{ y: 60, opacity: 0 }} animate={{ y: 0, opacity: 1 }} exit={{ y: 60, opacity: 0 }}
            transition={{ type: 'spring', damping: 26, stiffness: 300 }}
            style={{ position: 'absolute', bottom: 4, left: 12, right: 12, zIndex: 40 }}>
            <motion.button whileTap={{ scale: 0.97 }} onClick={() => setTransfer(p => p ? { ...p, background: false } : null)}
              style={{ width: '100%', background: '#131313', border: `1px solid ${CYAN}35`, borderRadius: 16, padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 12, boxShadow: `0 0 20px ${CYAN}20` }}>
              <div style={{ width: 36, height: 36, borderRadius: 10, background: `${CYAN}15`, border: `1px solid ${CYAN}25`, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                {transfer.mode === 'upload' ? <Upload size={14} color={CYAN} /> : <Download size={14} color={CYAN} />}
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <p style={{ fontSize: 12, fontWeight: 700, color: '#fff', fontFamily: F, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>
                  {transfer.file.name}
                </p>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 3 }}>
                  <div style={{ flex: 1, height: 3, borderRadius: 99, background: 'rgba(255,255,255,0.08)', overflow: 'hidden' }}>
                    <motion.div animate={{ width: `${transfer.progress}%` }} transition={{ duration: 0.25 }}
                      style={{ height: '100%', borderRadius: 99, background: `linear-gradient(90deg, ${CYAN}, ${PURPLE})` }} />
                  </div>
                  <span style={{ fontSize: 10, color: CYAN_L, fontFamily: F, fontWeight: 700, flexShrink: 0 }}>{Math.floor(transfer.progress)}%</span>
                </div>
              </div>
              <Layers size={14} color="rgba(255,255,255,0.35)" />
            </motion.button>
          </motion.div>
        )}
      </AnimatePresence>

      {/* ── File options bottom sheet ── */}
      <AnimatePresence>
        {fileMenu && (
          <>
            <motion.div key="overlay" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }}
              onClick={() => setFileMenu(null)}
              style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.6)', zIndex: 60 }} />
            <motion.div key="sheet"
              initial={{ y: '100%' }} animate={{ y: 0 }} exit={{ y: '100%' }}
              transition={{ type: 'spring', damping: 28, stiffness: 300 }}
              style={{ position: 'absolute', bottom: 0, left: 0, right: 0, zIndex: 61, background: '#131313', borderRadius: '20px 20px 0 0', border: '1px solid rgba(255,255,255,0.08)', padding: '14px 16px 32px' }}>
              <div style={{ width: 36, height: 4, borderRadius: 99, background: 'rgba(255,255,255,0.15)', margin: '0 auto 20px' }} />
              {(() => {
                const f = files.find(x => x.id === fileMenu);
                if (!f) return null;
                return (
                  <>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '0 4px 16px', borderBottom: '1px solid rgba(255,255,255,0.07)', marginBottom: 8 }}>
                      <FileIconBox ext={f.ext} size={36} />
                      <div style={{ minWidth: 0 }}>
                        <p style={{ fontSize: 14, fontWeight: 700, color: '#fff', fontFamily: F, overflow: 'hidden', whiteSpace: 'nowrap', textOverflow: 'ellipsis' }}>{f.name}</p>
                        <p style={{ fontSize: 11, color: '#ABABAB', fontFamily: F }}>{fmtBytes(f.size)}</p>
                      </div>
                    </div>
                    {[
                      { icon: <Download size={17} color={CYAN} />, label: 'Download', bg: `${CYAN}12`, action: () => handleDownload(f) },
                      { icon: <Star size={17} color="#FBBF24" fill={f.starred ? '#FBBF24' : 'none'} />, label: f.starred ? 'Remove Star' : 'Add to Starred', bg: 'rgba(251,191,36,0.1)', action: () => handleToggleStar(f.id) },
                      { icon: <Trash2 size={17} color="#F87171" />, label: 'Delete', bg: 'rgba(239,68,68,0.1)', action: () => handleDelete(f.id) },
                    ].map((item, i) => (
                      <motion.button key={i} whileTap={{ scale: 0.97 }} onClick={item.action}
                        style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 14, padding: '14px 8px', background: 'none', border: 'none', cursor: 'pointer', borderRadius: 12 }}>
                        <div style={{ width: 38, height: 38, borderRadius: 12, background: item.bg, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                          {item.icon}
                        </div>
                        <span style={{ fontSize: 15, fontWeight: 600, color: i === 2 ? '#F87171' : '#fff', fontFamily: F }}>{item.label}</span>
                      </motion.button>
                    ))}
                  </>
                );
              })()}
            </motion.div>
          </>
        )}
      </AnimatePresence>

      {/* ── Transfer Modal (full overlay) ── */}
      <AnimatePresence>
        {transfer && !transfer.background && (
          <TransferModal transfer={transfer} onCancel={handleCancel} onBackground={handleBackground} />
        )}
      </AnimatePresence>
    </div>
  );
}