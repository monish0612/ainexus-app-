import { useRef, useEffect, useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ArrowLeft, Bookmark, Share2, Clock, ExternalLink, CheckCircle2 } from 'lucide-react';
import type { Article } from './NewsData';
import { CAT_COLOR } from './NewsData';
import { ImageWithFallback } from '../figma/ImageWithFallback';

const F = "'Plus Jakarta Sans', sans-serif";

interface Props {
  article: Article | null;
  isSaved: boolean;
  source?: 'forYou' | 'saved';
  onClose: () => void;
  onToggleSave: (id: string) => void;
  onDone: (id: string) => void;
}

const TAG_COLOR: Record<string, string> = {
  Breaking: '#EF4444',
  Trending: '#F59E0B',
  Exclusive: '#EC4899',
};

export function ArticleDetailModal({ article, isSaved, source = 'forYou', onClose, onToggleSave, onDone }: Props) {
  const scrollRef   = useRef<HTMLDivElement>(null);
  const [scrolled,  setScrolled]  = useState(false);
  const [saveAnim,  setSaveAnim]  = useState(false);
  const [doneAnim,  setDoneAnim]  = useState(false);
  const [doneFlash, setDoneFlash] = useState(false);

  useEffect(() => {
    if (article) { setScrolled(false); setDoneAnim(false); scrollRef.current?.scrollTo(0, 0); }
  }, [article]);

  const handleScroll = () => setScrolled((scrollRef.current?.scrollTop ?? 0) > 140);

  const handleSave = () => {
    if (!article) return;
    onToggleSave(article.id);
    setSaveAnim(true);
    setTimeout(() => setSaveAnim(false), 700);
  };

  const handleDone = () => {
    if (!article) return;
    setDoneFlash(true);
    setDoneAnim(true);
    setTimeout(() => {
      onDone(article.id);
      setDoneFlash(false);
      setDoneAnim(false);
    }, 520);
  };

  const catColor = article ? (CAT_COLOR[article.category] || '#818CF8') : '#818CF8';

  return (
    <AnimatePresence>
      {article && (
        <motion.div
          className="fixed inset-0 z-[70] flex flex-col"
          style={{ background: '#000', maxWidth: 430, margin: '0 auto' }}
          initial={{ y: '100%' }}
          animate={{ y: 0 }}
          exit={{ y: '100%' }}
          transition={{ type: 'spring', damping: 30, stiffness: 280 }}
        >
          {/* ── Fixed header ── */}
          <motion.div
            className="absolute top-0 left-0 right-0 z-10 flex items-center justify-between px-4 pt-3 pb-3"
            animate={{
              background: scrolled ? 'rgba(0,0,0,0.92)' : 'transparent',
              borderBottomColor: scrolled ? 'rgba(255,255,255,0.08)' : 'transparent',
            }}
            style={{ backdropFilter: scrolled ? 'blur(20px)' : 'none', borderBottom: '1px solid transparent', height: 58 }}
            transition={{ duration: 0.2 }}
          >
            <motion.button
              whileTap={{ scale: 0.88 }}
              onClick={onClose}
              className="flex items-center justify-center rounded-full"
              style={{
                width: 38, height: 38,
                background: scrolled ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.55)',
                border: '1px solid rgba(255,255,255,0.14)',
                backdropFilter: 'blur(10px)',
              }}
            >
              <ArrowLeft size={18} color="#fff" />
            </motion.button>

            <AnimatePresence>
              {scrolled && (
                <motion.p
                  initial={{ opacity: 0, y: 6 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -6 }}
                  style={{
                    fontSize: 12, fontWeight: 700, color: '#fff', fontFamily: F,
                    maxWidth: 190, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                  }}
                >
                  {article.title}
                </motion.p>
              )}
            </AnimatePresence>

            <div className="flex items-center gap-2">
              <motion.button
                whileTap={{ scale: 0.88 }}
                className="flex items-center justify-center rounded-full"
                style={{
                  width: 38, height: 38,
                  background: scrolled ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.55)',
                  border: '1px solid rgba(255,255,255,0.14)',
                  backdropFilter: 'blur(10px)',
                }}
              >
                <Share2 size={15} color="rgba(255,255,255,0.7)" />
              </motion.button>
            </div>
          </motion.div>

          {/* ── Scrollable body ── */}
          <div
            ref={scrollRef}
            onScroll={handleScroll}
            className="flex-1 overflow-y-auto"
            style={{ scrollbarWidth: 'none' }}
          >
            {/* Hero image */}
            <div className="relative w-full" style={{ height: 300 }}>
              <ImageWithFallback
                src={article.image}
                alt={article.title}
                className="w-full h-full object-cover"
              />
              <div className="absolute inset-0" style={{
                background: 'linear-gradient(to bottom, rgba(0,0,0,0.28) 0%, rgba(0,0,0,0) 38%, rgba(0,0,0,0.82) 78%, rgba(0,0,0,1) 100%)',
              }} />
              <div className="absolute inset-0 pointer-events-none" style={{
                background: `radial-gradient(ellipse 80% 40% at 50% 100%, ${catColor}15 0%, transparent 70%)`,
              }} />
              <div className="absolute bottom-0 left-0 right-0 px-5 pb-5">
                <div className="flex items-center gap-2 flex-wrap">
                  <span className="rounded-full px-3 py-1"
                    style={{ fontSize: 10, fontWeight: 700, color: '#fff', background: catColor, fontFamily: F, letterSpacing: 0.7 }}>
                    {article.category.toUpperCase()}
                  </span>
                  {article.tag && (
                    <span className="rounded-full px-3 py-1"
                      style={{ fontSize: 10, fontWeight: 700, color: '#fff', background: TAG_COLOR[article.tag], fontFamily: F, letterSpacing: 0.7 }}>
                      {article.tag.toUpperCase()}
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* Article content */}
            <div className="px-5 pt-5 pb-36">
              {/* Meta row */}
              <div className="flex items-center gap-3 mb-4 flex-wrap">
                <div className="flex items-center gap-1.5">
                  <Clock size={12} color="rgba(255,255,255,0.38)" />
                  <span style={{ fontSize: 12, color: 'rgba(255,255,255,0.38)', fontFamily: F }}>
                    {article.readTime} min read
                  </span>
                </div>
                <span style={{ color: 'rgba(255,255,255,0.18)', fontSize: 10 }}>•</span>
                <span style={{ fontSize: 12, color: 'rgba(255,255,255,0.38)', fontFamily: F }}>{article.date}</span>
                <span style={{ color: 'rgba(255,255,255,0.18)', fontSize: 10 }}>•</span>
                <span style={{ fontSize: 12, color: catColor, fontWeight: 700, fontFamily: F }}>{article.source}</span>
              </div>

              {/* Title */}
              <h1 style={{
                fontSize: 27, fontWeight: 900, color: '#fff', fontFamily: F,
                lineHeight: 1.27, letterSpacing: '-0.5px', marginBottom: 18,
              }}>
                {article.title}
              </h1>

              {/* Lead / excerpt */}
              <p style={{
                fontSize: 16, color: 'rgba(255,255,255,0.6)', fontFamily: F, lineHeight: 1.72,
                fontStyle: 'italic', marginBottom: 24, paddingBottom: 24,
                borderBottom: '1px solid rgba(255,255,255,0.07)',
              }}>
                {article.excerpt}
              </p>

              {/* Content blocks */}
              {article.content.map((block, i) => {
                if (block.type === 'paragraph') return (
                  <p key={i} style={{ fontSize: 15, color: 'rgba(255,255,255,0.74)', fontFamily: F, lineHeight: 1.88, marginBottom: 22 }}>
                    {block.text}
                  </p>
                );
                if (block.type === 'heading') return (
                  <h2 key={i} style={{
                    fontSize: 20, fontWeight: 800, color: '#fff', fontFamily: F,
                    letterSpacing: '-0.3px', marginTop: 30, marginBottom: 12, lineHeight: 1.3,
                  }}>
                    {block.text}
                  </h2>
                );
                if (block.type === 'quote') return (
                  <div key={i} style={{ borderLeft: `3px solid ${catColor}`, paddingLeft: 18, marginTop: 26, marginBottom: 26 }}>
                    <p style={{ fontSize: 17, fontStyle: 'italic', color: 'rgba(255,255,255,0.87)', lineHeight: 1.68, fontFamily: F, marginBottom: 10 }}>
                      "{block.text}"
                    </p>
                    <p style={{ fontSize: 12, fontWeight: 700, fontFamily: F, color: catColor }}>
                      — {block.author}, {block.role}
                    </p>
                  </div>
                );
                if (block.type === 'stat' && block.items) return (
                  <div key={i} className="flex gap-3 my-6 flex-wrap">
                    {block.items.map((item, j) => (
                      <div key={j} className="flex-1 rounded-2xl p-4 text-center"
                        style={{ background: `${catColor}10`, border: `1px solid ${catColor}22`, minWidth: 88 }}>
                        <p style={{ fontSize: 23, fontWeight: 900, color: catColor, fontFamily: F, letterSpacing: '-0.4px' }}>
                          {item.value}
                        </p>
                        <p style={{ fontSize: 9, color: 'rgba(255,255,255,0.42)', fontFamily: F, marginTop: 4, letterSpacing: 0.5 }}>
                          {item.label.toUpperCase()}
                        </p>
                      </div>
                    ))}
                  </div>
                );
                return null;
              })}

              {/* Source */}
              <div className="flex items-center gap-2 mt-8 pt-6" style={{ borderTop: '1px solid rgba(255,255,255,0.06)' }}>
                <ExternalLink size={12} color="rgba(255,255,255,0.28)" />
                <span style={{ fontSize: 12, color: 'rgba(255,255,255,0.28)', fontFamily: F }}>Source: {article.source}</span>
              </div>
            </div>
          </div>

          {/* ── Bottom action bar ── */}
          <div className="absolute bottom-0 left-0 right-0 px-4 pb-7 pt-5"
            style={{ background: 'linear-gradient(to top, rgba(0,0,0,1) 55%, transparent)', pointerEvents: 'none' }}>
            <div className="flex gap-3" style={{ pointerEvents: 'auto' }}>

              {source === 'saved' ? (
                /* ── Saved tab: single full-width Close button ── */
                <motion.button
                  onClick={onClose}
                  className="flex items-center justify-center gap-2.5 rounded-2xl w-full"
                  style={{ height: 64, border: '1px solid rgba(255,255,255,0.12)', background: 'rgba(255,255,255,0.06)', cursor: 'pointer' }}
                  whileTap={{ scale: 0.97 }}
                  animate={{ boxShadow: '0 0 0px transparent' }}
                  whileHover={{ background: 'rgba(255,255,255,0.09)' } as any}
                >
                  <ArrowLeft size={20} color="rgba(255,255,255,0.7)" />
                  <span style={{ fontSize: 16, fontWeight: 700, fontFamily: F, color: 'rgba(255,255,255,0.7)' }}>
                    Close
                  </span>
                </motion.button>
              ) : (
                <>
                  {/* ── DONE button ── */}
                  <motion.button
                    onClick={handleDone}
                    disabled={doneAnim}
                    className="flex items-center justify-center gap-2 rounded-2xl"
                    style={{ flex: 1, height: 58, border: '1px solid rgba(52,211,153,0.35)', cursor: 'pointer', position: 'relative', overflow: 'hidden' }}
                    animate={{
                      background: doneFlash ? 'rgba(52,211,153,0.28)' : 'rgba(52,211,153,0.09)',
                      scale: doneAnim ? [1, 0.94, 1.06, 1] : 1,
                      boxShadow: doneFlash ? '0 0 28px rgba(52,211,153,0.4), 0 0 60px rgba(52,211,153,0.15)' : 'none',
                    }}
                    transition={{ duration: 0.4 }}
                    whileTap={{ scale: 0.94 }}
                  >
                    <AnimatePresence>
                      {doneFlash && (
                        <motion.div
                          className="absolute inset-0 rounded-2xl"
                          initial={{ opacity: 0.6, scale: 0.5 }}
                          animate={{ opacity: 0, scale: 2.5 }}
                          exit={{ opacity: 0 }}
                          style={{ background: 'radial-gradient(circle, rgba(52,211,153,0.6) 0%, transparent 70%)' }}
                          transition={{ duration: 0.5 }}
                        />
                      )}
                    </AnimatePresence>
                    <motion.div animate={doneAnim ? { rotate: [0, -8, 8, 0], scale: [1, 1.2, 1] } : {}} transition={{ duration: 0.4 }}>
                      <CheckCircle2
                        size={18}
                        color={doneFlash ? '#34D399' : 'rgba(52,211,153,0.75)'}
                        fill={doneFlash ? 'rgba(52,211,153,0.15)' : 'none'}
                      />
                    </motion.div>
                    <span style={{ fontSize: 14, fontWeight: 700, fontFamily: F, color: doneFlash ? '#34D399' : 'rgba(52,211,153,0.75)' }}>
                      {doneFlash ? 'Done!' : 'Done'}
                    </span>
                  </motion.button>

                  {/* ── SAVE button ── */}
                  <motion.button
                    onClick={handleSave}
                    className="flex items-center justify-center gap-2 rounded-2xl"
                    animate={{
                      background: isSaved ? 'rgba(124,58,237,0.22)' : 'rgba(124,58,237,0.12)',
                      borderColor: isSaved ? 'rgba(124,58,237,0.45)' : 'rgba(124,58,237,0.28)',
                      boxShadow: isSaved ? '0 0 24px rgba(124,58,237,0.25)' : 'none',
                    }}
                    style={{ border: '1px solid rgba(124,58,237,0.28)', flex: 2, height: 58, cursor: 'pointer' }}
                    whileTap={{ scale: 0.96 }}
                  >
                    <motion.div animate={saveAnim ? { scale: [1, 1.4, 0.9, 1.1, 1], rotate: [0, -15, 10, 0] } : {}} transition={{ duration: 0.5 }}>
                      <Bookmark
                        size={18}
                        color={isSaved ? '#A78BFA' : 'rgba(167,139,250,0.7)'}
                        fill={isSaved ? '#A78BFA' : 'none'}
                      />
                    </motion.div>
                    <span style={{ fontSize: 14, fontWeight: 700, fontFamily: F, color: isSaved ? '#A78BFA' : 'rgba(167,139,250,0.7)' }}>
                      {isSaved ? 'Saved to Library' : 'Save Article'}
                    </span>
                  </motion.button>
                </>
              )}
            </div>
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
}