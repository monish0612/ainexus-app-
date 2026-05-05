import { useState, useEffect, useRef, useMemo } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
  Bell, Bookmark, Clock, Trash2, Share2, BookmarkCheck,
  Search, X, Zap, TrendingUp, Cpu, Globe,
} from 'lucide-react';
import { ARTICLES, CATEGORIES, CAT_COLOR, type Article } from '../components/news/NewsData';
import { ArticleDetailModal } from '../components/news/ArticleDetailModal';
import { ImageWithFallback } from '../components/figma/ImageWithFallback';
import { useSettings } from '../utils/settingsContext';
import { usePalette } from '../utils/palette';

const F = "'Plus Jakarta Sans', sans-serif";
type Tab = 'forYou' | 'saved';

const TAG_COLOR: Record<string, string> = {
  Breaking: '#EF4444',
  Trending: '#F59E0B',
  Exclusive: '#EC4899',
};

const NOTIFICATIONS = [
  { id: 'n1', icon: Zap,        color: '#EF4444', title: 'Breaking: Quantum AI decodes proteins in under 2 seconds',     time: '12 min ago', read: false, articleId: 'art-001' },
  { id: 'n2', icon: TrendingUp, color: '#34D399', title: 'Market Alert: S&P 500 surges 2.4% on rate-cut signals',         time: '28 min ago', read: false, articleId: 'art-002' },
  { id: 'n3', icon: Cpu,        color: '#A78BFA', title: "DeepMind's Gemini Ultra 2 shatters 43 benchmarks",              time: '3 hr ago',   read: true,  articleId: 'art-004' },
  { id: 'n4', icon: Globe,      color: '#F59E0B', title: 'SpaceX Starship completes first fully-reusable orbital flight', time: '7 hr ago',   read: true,  articleId: 'art-006' },
];

// ─── Featured card ────────────────────────────────────────────────────────────
function FeaturedCard({ article, onOpen }: { article: Article; onOpen: () => void }) {
  const catColor = CAT_COLOR[article.category] || '#818CF8';
  return (
    <motion.div
      whileTap={{ scale: 0.985 }}
      onClick={onOpen}
      className="relative w-full overflow-hidden cursor-pointer"
      style={{ height: 400, borderRadius: 24, boxShadow: '0 24px 64px rgba(0,0,0,0.65)' }}
      initial={{ opacity: 0, y: 20 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.38 }}
    >
      <ImageWithFallback src={article.image} alt={article.title} className="absolute inset-0 w-full h-full object-cover" />
      <div className="absolute inset-0" style={{ background: 'linear-gradient(to bottom, rgba(0,0,0,0.08) 0%, rgba(0,0,0,0) 32%, rgba(0,0,0,0.72) 64%, rgba(0,0,0,0.98) 100%)' }} />
      <div className="absolute inset-0 pointer-events-none" style={{ background: `radial-gradient(ellipse 80% 50% at 50% 100%, ${catColor}20 0%, transparent 70%)` }} />
      <div className="absolute bottom-0 left-0 right-0 p-6">
        <div className="flex items-center gap-2 mb-3 flex-wrap">
          {article.tag && (
            <span className="rounded-full px-3 py-1" style={{ fontSize: 10, fontWeight: 800, color: '#fff', background: TAG_COLOR[article.tag] || '#EF4444', fontFamily: F, letterSpacing: 0.8 }}>
              {article.tag.toUpperCase()}
            </span>
          )}
          <span className="rounded-full px-3 py-1" style={{ fontSize: 10, fontWeight: 700, color: catColor, background: `${catColor}20`, border: `1px solid ${catColor}45`, fontFamily: F }}>
            {article.category}
          </span>
        </div>
        <h2 style={{ fontSize: 20, fontWeight: 800, color: '#fff', fontFamily: F, letterSpacing: '-0.3px', lineHeight: 1.3, marginBottom: 12 }}>
          {article.title}
        </h2>
        <div className="flex items-center gap-3">
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.55)', fontFamily: F }}>{article.source}</span>
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.3)', fontFamily: F }}>·</span>
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.55)', fontFamily: F }}>{article.timeAgo}</span>
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.3)', fontFamily: F }}>·</span>
          <Clock size={11} color="rgba(255,255,255,0.4)" />
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.55)', fontFamily: F }}>{article.readTime} min</span>
        </div>
      </div>
    </motion.div>
  );
}

// ─── News Card ────────────────────────────────────────────────────────────────
function NewsCard({ article, index, onOpen }: { article: Article; index: number; onOpen: () => void }) {
  const catColor = CAT_COLOR[article.category] || '#818CF8';
  return (
    <motion.div
      whileTap={{ scale: 0.98 }}
      onClick={onOpen}
      className="flex gap-3 cursor-pointer"
      style={{ padding: '14px 0', borderBottom: '1px solid rgba(255,255,255,0.06)' }}
      initial={{ opacity: 0, y: 14 }}
      animate={{ opacity: 1, y: 0 }}
      transition={{ duration: 0.3, delay: index * 0.04 }}
    >
      <div className="flex-1 min-w-0 flex flex-col justify-between gap-2">
        <div>
          {article.tag && (
            <span className="inline-block rounded-full px-2 py-0.5 mb-1.5" style={{ fontSize: 9, fontWeight: 800, color: '#fff', background: TAG_COLOR[article.tag] || '#EF4444', fontFamily: F, letterSpacing: 0.8 }}>
              {article.tag.toUpperCase()}
            </span>
          )}
          <p style={{ fontSize: 14, fontWeight: 700, color: '#F1F5F9', fontFamily: F, lineHeight: 1.35, letterSpacing: '-0.1px' }}>
            {article.title}
          </p>
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <span className="rounded-full px-2 py-0.5" style={{ fontSize: 9, fontWeight: 700, color: catColor, background: `${catColor}18`, fontFamily: F }}>
            {article.category}
          </span>
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', fontFamily: F }}>{article.source}</span>
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.2)', fontFamily: F }}>·</span>
          <span style={{ fontSize: 11, color: 'rgba(255,255,255,0.35)', fontFamily: F }}>{article.timeAgo}</span>
        </div>
      </div>
      <div className="relative shrink-0" style={{ width: 88, height: 88 }}>
        <ImageWithFallback
          src={article.image} alt={article.title}
          className="w-full h-full object-cover"
          style={{ borderRadius: 12 }}
        />
        <div className="absolute inset-0 pointer-events-none" style={{ borderRadius: 12, background: `linear-gradient(135deg, ${catColor}20 0%, transparent 60%)` }} />
      </div>
    </motion.div>
  );
}

// ─── Saved Card ───────────────────────────────────────────────────────────────
function SavedCard({ article, query, onOpen, onRemove }: {
  article: Article;
  query: string;
  onOpen: () => void;
  onRemove: () => void;
}) {
  const catColor = CAT_COLOR[article.category] || '#818CF8';

  const highlight = (text: string) => {
    if (!query) return <>{text}</>;
    const idx = text.toLowerCase().indexOf(query.toLowerCase());
    if (idx === -1) return <>{text}</>;
    return (
      <>
        {text.slice(0, idx)}
        <span style={{ background: `${catColor}30`, color: catColor, borderRadius: 3, padding: '0 2px' }}>
          {text.slice(idx, idx + query.length)}
        </span>
        {text.slice(idx + query.length)}
      </>
    );
  };

  return (
    <motion.div
      layout
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, x: -20 }}
      whileTap={{ scale: 0.985 }}
      onClick={onOpen}
      className="flex gap-3 cursor-pointer"
      style={{ padding: '14px 0', borderBottom: '1px solid rgba(255,255,255,0.06)' }}
    >
      <div className="relative shrink-0" style={{ width: 72, height: 72 }}>
        <ImageWithFallback
          src={article.image} alt={article.title}
          className="w-full h-full object-cover"
          style={{ borderRadius: 10 }}
        />
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-start justify-between gap-2">
          <p style={{ fontSize: 13, fontWeight: 700, color: '#F1F5F9', fontFamily: F, lineHeight: 1.35, flex: 1 }}>
            {highlight(article.title)}
          </p>
          <motion.button
            whileTap={{ scale: 0.82 }}
            onClick={e => { e.stopPropagation(); onRemove(); }}
            style={{ width: 28, height: 28, borderRadius: 8, background: 'rgba(239,68,68,0.1)', border: '1px solid rgba(239,68,68,0.2)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}
          >
            <Trash2 size={12} color="#EF4444" />
          </motion.button>
        </div>
        <div className="flex items-center gap-2 mt-1.5 flex-wrap">
          <span className="rounded-full px-2 py-0.5" style={{ fontSize: 9, fontWeight: 700, color: catColor, background: `${catColor}18`, fontFamily: F }}>{article.category}</span>
          <span style={{ fontSize: 10, color: 'rgba(255,255,255,0.3)', fontFamily: F }}>{article.source} · {article.timeAgo}</span>
        </div>
      </div>
    </motion.div>
  );
}

// ─── Notification Panel ───────────────────────────────────────────────────────
function NotifPanel({ onClose, onOpenArticle }: {
  onClose: () => void;
  onOpenArticle: (id: string) => void;
}) {
  return (
    <motion.div
      key="notif"
      initial={{ opacity: 0, y: -12 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, y: -12 }}
      transition={{ type: 'spring', damping: 26, stiffness: 280 }}
      className="absolute inset-x-0 top-0 z-30 flex flex-col"
      style={{ background: '#080808', borderBottom: '1px solid rgba(255,255,255,0.08)', maxHeight: '80%', overflowY: 'auto', scrollbarWidth: 'none' }}
    >
      <div className="flex items-center justify-between px-4 py-3 shrink-0" style={{ borderBottom: '1px solid rgba(255,255,255,0.06)' }}>
        <span style={{ fontSize: 16, fontWeight: 800, color: '#fff', fontFamily: F }}>Notifications</span>
        <motion.button whileTap={{ scale: 0.85 }} onClick={onClose}
          className="flex items-center justify-center"
          style={{ width: 30, height: 30, borderRadius: 10, background: 'rgba(255,255,255,0.07)' }}>
          <X size={14} color="rgba(255,255,255,0.6)" />
        </motion.button>
      </div>
      {NOTIFICATIONS.map(n => {
        const Icon = n.icon;
        return (
          <motion.button key={n.id} whileTap={{ scale: 0.985 }}
            onClick={() => { onOpenArticle(n.articleId); onClose(); }}
            className="flex items-start gap-3 px-4 py-3 w-full text-left"
            style={{ borderBottom: '1px solid rgba(255,255,255,0.04)', background: n.read ? 'transparent' : 'rgba(255,255,255,0.02)', outline: 'none' }}>
            <div className="shrink-0 flex items-center justify-center" style={{ width: 34, height: 34, borderRadius: 10, background: `${n.color}18`, border: `1px solid ${n.color}28`, marginTop: 1 }}>
              <Icon size={15} color={n.color} />
            </div>
            <div className="flex-1 min-w-0">
              <p style={{ fontSize: 13, fontWeight: n.read ? 500 : 700, color: n.read ? 'rgba(255,255,255,0.55)' : '#F1F5F9', fontFamily: F, lineHeight: 1.4 }}>
                {n.title}
              </p>
              <p style={{ fontSize: 11, color: 'rgba(255,255,255,0.28)', fontFamily: F, marginTop: 3 }}>{n.time}</p>
            </div>
            {!n.read && (
              <div style={{ width: 7, height: 7, borderRadius: 99, background: n.color, boxShadow: `0 0 6px ${n.color}`, marginTop: 6, flexShrink: 0 }} />
            )}
          </motion.button>
        );
      })}
    </motion.div>
  );
}

// ─── Main Page ────────────────────────────────────────────────────────────────
export function NewsPage() {
  const [tab, setTab]           = useState<Tab>('forYou');
  const [category, setCategory] = useState('All');
  const [selected, setSelected] = useState<Article | null>(null);
  const [selectedSource, setSelectedSource] = useState<'forYou' | 'saved'>('forYou');
  const [showNotif, setShowNotif] = useState(false);
  const [notifSeen, setNotifSeen] = useState(false);
  const [savedSearch, setSavedSearch] = useState('');
  const searchRef = useRef<HTMLInputElement>(null);
  const { openSettings } = useSettings();
  const p = usePalette();

  // Swipe gesture state
  const swipeX = useRef(0);
  const swipeY = useRef(0);

  const [savedIds, setSavedIds] = useState<string[]>(() => {
    try { return JSON.parse(localStorage.getItem('news_saved_ids') || '[]'); } catch { return []; }
  });

  const [dismissedIds, setDismissedIds] = useState<string[]>(() => {
    try { return JSON.parse(localStorage.getItem('news_dismissed_ids') || '[]'); } catch { return []; }
  });

  useEffect(() => { localStorage.setItem('news_saved_ids', JSON.stringify(savedIds)); }, [savedIds]);
  useEffect(() => { localStorage.setItem('news_dismissed_ids', JSON.stringify(dismissedIds)); }, [dismissedIds]);

  const toggleSave = (id: string) => {
    setSavedIds(prev => prev.includes(id) ? prev.filter(x => x !== id) : [...prev, id]);
  };

  const feedArticles = useMemo(() => {
    let list = ARTICLES.filter(a => !dismissedIds.includes(a.id));
    if (category !== 'All') list = list.filter(a => a.category === category);
    return list;
  }, [category, dismissedIds]);

  const featuredArticle = feedArticles.find(a => a.isFeatured) ?? feedArticles[0];
  const restArticles    = feedArticles.filter(a => a.id !== featuredArticle?.id);

  const savedArticles = useMemo(() => {
    return ARTICLES.filter(a => savedIds.includes(a.id));
  }, [savedIds]);

  const filteredSaved = useMemo(() => {
    const q = savedSearch.trim().toLowerCase();
    if (!q) return savedArticles;
    return savedArticles.filter(a =>
      a.title.toLowerCase().includes(q) ||
      a.category.toLowerCase().includes(q) ||
      a.source.toLowerCase().includes(q)
    );
  }, [savedArticles, savedSearch]);

  const unreadCount = NOTIFICATIONS.filter(n => !n.read).length;

  const openArticle = (article: Article, source: 'forYou' | 'saved') => {
    setSelected(article);
    setSelectedSource(source);
  };

  const handleSwipeStart = (e: React.TouchEvent) => {
    swipeX.current = e.touches[0].clientX;
    swipeY.current = e.touches[0].clientY;
  };

  const handleSwipeEnd = (e: React.TouchEvent) => {
    const dx = e.changedTouches[0].clientX - swipeX.current;
    const dy = Math.abs(e.changedTouches[0].clientY - swipeY.current);
    if (Math.abs(dx) < 50 || dy > 40) return;
    if (dx < 0 && tab === 'forYou') setTab('saved');
    if (dx > 0 && tab === 'saved') setTab('forYou');
  };

  return (
    <div
      className="flex flex-col h-full relative"
      style={{ background: p.bg, overflowX: 'hidden' }}
      onTouchStart={handleSwipeStart}
      onTouchEnd={handleSwipeEnd}
    >

      {/* ── Header ── */}
      <div className="shrink-0 flex items-center justify-between px-4"
        style={{ height: 52, borderBottom: `1px solid ${p.border}`, background: p.headerBg, zIndex: 10 }}>

        {/* Left: profile avatar — opens Settings */}
        <motion.button
          whileTap={{ scale: 0.84 }}
          onClick={openSettings}
          style={{
            width: 32, height: 32, borderRadius: '50%', cursor: 'pointer',
            background: 'linear-gradient(135deg, #0D59F2, #22D3EE)',
            padding: 2, border: 'none', outline: 'none', flexShrink: 0,
          }}
        >
          <div style={{ width: '100%', height: '100%', borderRadius: '50%', background: p.isDark ? '#111' : '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontSize: 11, fontWeight: 800, color: p.isDark ? '#fff' : '#0F172A', fontFamily: F }}>AR</span>
          </div>
        </motion.button>

        <span style={{ fontSize: 17, fontWeight: 800, color: p.text, fontFamily: F, letterSpacing: '-0.3px' }}>
          Discover
        </span>

        <motion.button
          whileTap={{ scale: 0.85 }}
          onClick={() => { setShowNotif(true); setNotifSeen(true); }}
          className="flex items-center justify-center rounded-full relative"
          style={{ width: 32, height: 32, background: 'rgba(255,255,255,0.07)', border: '1.5px solid rgba(255,255,255,0.1)' }}
        >
          <Bell size={15} color="rgba(255,255,255,0.7)" />
          <AnimatePresence>
            {!notifSeen && unreadCount > 0 && (
              <motion.div
                key="badge"
                initial={{ scale: 0 }} animate={{ scale: 1 }} exit={{ scale: 0 }}
                className="absolute -top-0.5 -right-0.5 flex items-center justify-center"
                style={{ width: 14, height: 14, borderRadius: 7, background: '#EF4444', border: '1.5px solid #000' }}
              >
                <span style={{ fontSize: 8, fontWeight: 800, color: '#fff', fontFamily: F }}>{unreadCount}</span>
              </motion.div>
            )}
          </AnimatePresence>
        </motion.button>
      </div>

      {/* ── Tab bar ── */}
      <div className="shrink-0 flex" style={{ borderBottom: `1px solid ${p.border}`, background: p.headerBg }}>
        {(['forYou', 'saved'] as const).map(t => (
          <motion.button key={t} whileTap={{ scale: 0.96 }} onClick={() => setTab(t)}
            className="flex-1 flex flex-col items-center py-2.5 relative"
            style={{ background: 'transparent', border: 'none', outline: 'none', cursor: 'pointer' }}>
            <div className="flex items-center gap-1.5">
              {t === 'saved' && (
                <Bookmark size={12} color={tab === t ? '#A78BFA' : p.text3} fill={tab === t ? '#A78BFA' : 'none'} />
              )}
              <span style={{
                fontSize: 13, fontWeight: tab === t ? 700 : 500,
                color: tab === t ? p.text : p.text3,
                fontFamily: F, letterSpacing: 0.1, transition: 'color 0.2s',
              }}>
                {t === 'forYou' ? 'For You' : `Saved${savedIds.length > 0 ? ` (${savedIds.length})` : ''}`}
              </span>
            </div>
            {tab === t && (
              <motion.div
                layoutId="news-tab"
                className="absolute bottom-0 left-4 right-4"
                style={{ height: 2, borderRadius: 2, background: 'linear-gradient(90deg, #818CF8, #A78BFA)' }}
                transition={{ type: 'spring', damping: 28, stiffness: 340 }}
              />
            )}
          </motion.button>
        ))}
      </div>

      {/* ── Scrollable Body ── */}
      <div className="flex-1 overflow-y-auto relative" style={{ scrollbarWidth: 'none', background: p.bg }}>

        {/* For You tab */}
        {tab === 'forYou' && (
          <div className="flex flex-col">
            {/* Category chips */}
            <div className="flex gap-2 px-4 py-3 overflow-x-auto shrink-0" style={{ scrollbarWidth: 'none', background: p.bg }}>
              {CATEGORIES.map(cat => (
                <motion.button key={cat} whileTap={{ scale: 0.92 }} onClick={() => setCategory(cat)}
                  className="shrink-0 rounded-full px-4 py-1.5"
                  style={{
                    background: category === cat ? (p.isDark ? '#fff' : '#0F172A') : p.bg2,
                    border: `1px solid ${category === cat ? (p.isDark ? '#fff' : '#0F172A') : p.border}`,
                    outline: 'none', cursor: 'pointer',
                  }}>
                  <span style={{ fontSize: 12, fontWeight: 600, color: category === cat ? (p.isDark ? '#000' : '#fff') : p.text2, fontFamily: F, whiteSpace: 'nowrap' }}>
                    {cat}
                  </span>
                </motion.button>
              ))}
            </div>

            <div className="px-4 pb-6 flex flex-col gap-4">
              {/* Featured */}
              {featuredArticle && (
                <FeaturedCard
                  article={featuredArticle}
                  onOpen={() => openArticle(featuredArticle, 'forYou')}
                />
              )}

              {feedArticles.length === 0 && (
                <div className="flex flex-col items-center pt-16 gap-3">
                  <span style={{ fontSize: 40 }}>📰</span>
                  <p style={{ fontSize: 15, fontWeight: 700, color: 'rgba(255,255,255,0.3)', fontFamily: F }}>No articles in this category</p>
                </div>
              )}

              {/* Article list */}
              {restArticles.map((article, i) => (
                <NewsCard
                  key={article.id}
                  article={article}
                  index={i}
                  onOpen={() => openArticle(article, 'forYou')}
                />
              ))}
            </div>
          </div>
        )}

        {/* Saved tab */}
        {tab === 'saved' && (
          <div className="flex flex-col">
            {/* Search bar */}
            <div className="px-4 pt-3 pb-2 shrink-0">
              <motion.div
                className="flex items-center gap-3 rounded-xl px-4"
                animate={{ borderColor: savedSearch ? 'rgba(167,139,250,0.6)' : 'rgba(255,255,255,0.1)', boxShadow: savedSearch ? '0 0 0 3px rgba(124,58,237,0.12)' : 'none' }}
                style={{ height: 44, background: 'rgba(255,255,255,0.05)', border: '1px solid' }}
                transition={{ duration: 0.18 }}
              >
                <Search size={15} color={savedSearch ? '#A78BFA' : 'rgba(255,255,255,0.3)'} />
                <input
                  ref={searchRef}
                  value={savedSearch}
                  onChange={e => setSavedSearch(e.target.value)}
                  placeholder="Search saved articles…"
                  style={{ flex: 1, background: 'none', border: 'none', outline: 'none', fontSize: 14, color: '#fff', fontFamily: F }}
                />
                {savedSearch && (
                  <motion.button whileTap={{ scale: 0.88 }} onClick={() => setSavedSearch('')}>
                    <X size={13} color="rgba(255,255,255,0.4)" />
                  </motion.button>
                )}
              </motion.div>
            </div>

            <div className="px-4 pb-6">
              {savedIds.length === 0 ? (
                <div className="flex flex-col items-center pt-16 gap-3">
                  <motion.div animate={{ scale: [1, 1.07, 1] }} transition={{ duration: 2.5, repeat: Infinity }}>
                    <BookmarkCheck size={42} color="rgba(167,139,250,0.4)" />
                  </motion.div>
                  <p style={{ fontSize: 15, fontWeight: 700, color: 'rgba(255,255,255,0.3)', fontFamily: F }}>No saved articles yet</p>
                  <p style={{ fontSize: 12, color: 'rgba(255,255,255,0.18)', fontFamily: F, textAlign: 'center' }}>Tap an article and press Save to read it later</p>
                </div>
              ) : filteredSaved.length === 0 ? (
                <div className="flex flex-col items-center pt-12 gap-2">
                  <Search size={28} color="rgba(255,255,255,0.2)" />
                  <p style={{ fontSize: 14, color: 'rgba(255,255,255,0.3)', fontFamily: F }}>No results for "{savedSearch}"</p>
                </div>
              ) : (
                <AnimatePresence>
                  {filteredSaved.map(article => (
                    <SavedCard
                      key={article.id}
                      article={article}
                      query={savedSearch}
                      onOpen={() => openArticle(article, 'saved')}
                      onRemove={() => toggleSave(article.id)}
                    />
                  ))}
                </AnimatePresence>
              )}
            </div>
          </div>
        )}
      </div>

      {/* ── Notification panel ── */}
      <AnimatePresence>
        {showNotif && (
          <NotifPanel
            onClose={() => setShowNotif(false)}
            onOpenArticle={id => {
              setSelectedSource('forYou');
              const art = ARTICLES.find(a => a.id === id);
              if (art) setSelected(art);
            }}
          />
        )}
      </AnimatePresence>

      {/* ── Article detail modal ── */}
      <AnimatePresence>
        {selected && (
          <ArticleDetailModal
            article={selected}
            isSaved={savedIds.includes(selected.id)}
            source={selectedSource}
            onClose={() => setSelected(null)}
            onToggleSave={() => toggleSave(selected.id)}
            onDone={() => setSelected(null)}
          />
        )}
      </AnimatePresence>
    </div>
  );
}