import { useState, useRef } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import {
  X, Bell, ChevronRight, Trash2, Plus, Check,
  Brain, Shield, Info, Pencil, LogOut, CreditCard, Sun, Moon,
} from 'lucide-react';
import { useSettings } from '../utils/settingsContext';
import { usePalette } from '../utils/palette';

const F = "'Plus Jakarta Sans', sans-serif";
const BLUE = '#0D59F2';

/* ─── Profile Avatar ──────────────────────────────────────────────────────── */
function ProfileAvatar({ isDark }: { isDark: boolean }) {
  return (
    <div style={{ position: 'relative', width: 108, height: 108, flexShrink: 0 }}>
      <div style={{
        position: 'absolute', inset: -10, borderRadius: '50%',
        background: 'rgba(13,89,242,0.18)', filter: 'blur(14px)', pointerEvents: 'none',
      }} />
      <div style={{
        position: 'absolute', inset: 0, borderRadius: '50%',
        background: 'linear-gradient(135deg, #0D59F2 0%, #22D3EE 100%)',
        padding: 3, boxShadow: '0 0 24px rgba(13,89,242,0.4)',
      }}>
        <div style={{
          width: '100%', height: '100%', borderRadius: '50%',
          background: isDark ? '#111' : '#fff',
          border: `2px solid ${isDark ? '#000' : '#E2E8F0'}`,
          display: 'flex', alignItems: 'center', justifyContent: 'center', overflow: 'hidden',
        }}>
          <span style={{
            fontSize: 34, fontWeight: 900,
            color: isDark ? '#fff' : '#0F172A',
            fontFamily: F, letterSpacing: '-1px',
          }}>
            AR
          </span>
        </div>
      </div>
      <div style={{
        position: 'absolute', bottom: 3, right: 3, width: 30, height: 30,
        borderRadius: 15, background: BLUE,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        border: `2.5px solid ${isDark ? '#000' : '#fff'}`, zIndex: 2,
      }}>
        <Pencil size={12} color="#fff" strokeWidth={2.5} />
      </div>
    </div>
  );
}

/* ─── Preference Row ──────────────────────────────────────────────────────── */
function PreferenceRow({
  icon, label, sub, onPress, right,
  cardBg, border, textColor, subColor,
}: {
  icon: React.ReactNode; label: string; sub?: string;
  onPress?: () => void; right?: React.ReactNode;
  cardBg: string; border: string; textColor: string; subColor: string;
}) {
  return (
    <motion.button
      whileTap={{ scale: 0.98 }}
      onClick={onPress}
      style={{
        width: '100%', display: 'flex', alignItems: 'center',
        justifyContent: 'space-between', padding: '14px 16px',
        background: cardBg, border: `1px solid ${border}`,
        borderRadius: 20, marginBottom: 10, cursor: 'pointer', outline: 'none',
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
        <div style={{
          width: 40, height: 40, borderRadius: 13,
          background: BLUE + '20', border: `1px solid ${BLUE}30`,
          display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
        }}>
          {icon}
        </div>
        <div style={{ textAlign: 'left' }}>
          <p style={{ fontSize: 15, fontWeight: 600, color: textColor, fontFamily: F }}>{label}</p>
          {sub && (
            <p style={{ fontSize: 12, color: subColor, fontFamily: F, marginTop: 1 }}>{sub}</p>
          )}
        </div>
      </div>
      {right ?? <ChevronRight size={17} color={subColor} />}
    </motion.button>
  );
}

/* ─── Section Label ───────────────────────────────────────────────────────── */
function SectionLabel({ label, color }: { label: string; color: string }) {
  return (
    <p style={{
      fontSize: 10, fontWeight: 800, color, letterSpacing: 1.8,
      fontFamily: F, marginBottom: 12, marginTop: 6, paddingLeft: 4,
    }}>
      {label.toUpperCase()}
    </p>
  );
}

/* ─── Settings Modal ──────────────────────────────────────────────────────── */
export function SettingsModal() {
  const { settingsOpen, closeSettings, banks, addBank, deleteBank, theme, setTheme } = useSettings();
  const p = usePalette();

  const [addingBank, setAddingBank]   = useState(false);
  const [newBankName, setNewBankName] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  const handleAddBank = () => {
    const trimmed = newBankName.trim();
    if (trimmed.length < 2) return;
    addBank(trimmed);
    setNewBankName('');
    setAddingBank(false);
  };

  const sheetBg          = p.isDark ? '#060608' : '#FFFFFF';
  const scrollBg         = p.isDark ? '#060608' : '#F8FAFC';
  const cardBg           = p.isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.04)';
  const handleColor      = p.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)';
  const sectionLabelColor = p.isDark ? 'rgba(255,255,255,0.3)' : '#94A3B8';
  const subtitleColor    = p.isDark ? 'rgba(255,255,255,0.38)' : '#64748B';

  const THEMES: { key: 'dark' | 'white'; label: string }[] = [
    { key: 'dark',  label: 'AMOLED Black' },
    { key: 'white', label: 'White'        },
  ];

  return (
    <AnimatePresence>
      {settingsOpen && (
        <>
          {/* Backdrop */}
          <motion.div
            key="backdrop"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            transition={{ duration: 0.22 }}
            onClick={closeSettings}
            style={{
              position: 'absolute', inset: 0, zIndex: 200,
              background: p.isDark ? 'rgba(0,0,0,0.75)' : 'rgba(0,0,0,0.4)',
              backdropFilter: 'blur(3px)',
            }}
          />

          {/* Sheet */}
          <motion.div
            key="sheet"
            initial={{ y: '100%' }}
            animate={{ y: 0 }}
            exit={{ y: '100%' }}
            transition={{ type: 'spring', damping: 32, stiffness: 310, mass: 1 }}
            style={{
              position: 'absolute', bottom: 0, left: 0, right: 0, height: '96%',
              background: sheetBg,
              borderRadius: '26px 26px 0 0',
              zIndex: 201, display: 'flex', flexDirection: 'column',
              overflow: 'hidden',
              boxShadow: p.isDark
                ? '0 -8px 60px rgba(0,0,0,0.9)'
                : '0 -4px 40px rgba(0,0,0,0.12)',
              borderTop:   `1px solid ${p.border}`,
              borderLeft:  `1px solid ${p.border}`,
              borderRight: `1px solid ${p.border}`,
              borderBottom: 'none',
            }}
          >
            {/* Drag handle */}
            <div style={{
              display: 'flex', justifyContent: 'center',
              paddingTop: 12, paddingBottom: 4, flexShrink: 0,
            }}>
              <div style={{
                width: 40, height: 4, borderRadius: 99, background: handleColor,
              }} />
            </div>

            {/* Header */}
            <div style={{
              display: 'flex', alignItems: 'center', justifyContent: 'space-between',
              padding: '10px 18px 14px', flexShrink: 0,
            }}>
              <motion.button
                whileTap={{ scale: 0.88 }}
                onClick={closeSettings}
                style={{
                  width: 40, height: 40, borderRadius: 14,
                  background: cardBg, border: `1px solid ${p.border}`,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  cursor: 'pointer', outline: 'none',
                }}
              >
                <X size={17} color={p.text2} />
              </motion.button>

              <span style={{
                fontSize: 18, fontWeight: 800, color: p.text,
                fontFamily: F, letterSpacing: '-0.5px',
              }}>
                Settings
              </span>

              <motion.button
                whileTap={{ scale: 0.88 }}
                style={{
                  width: 40, height: 40, borderRadius: 14,
                  background: cardBg, border: `1px solid ${p.border}`,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  cursor: 'pointer', outline: 'none',
                }}
              >
                <Bell size={17} color={p.text2} />
              </motion.button>
            </div>

            {/* Scrollable body */}
            <div style={{
              flex: 1, overflowY: 'auto', padding: '0 18px 40px', background: scrollBg,
            }}>

              {/* Profile */}
              <motion.div
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.06 }}
                style={{
                  display: 'flex', flexDirection: 'column', alignItems: 'center',
                  paddingTop: 24, paddingBottom: 24,
                }}
              >
                <ProfileAvatar isDark={p.isDark} />
                <p style={{
                  fontSize: 24, fontWeight: 800, color: p.text, fontFamily: F,
                  letterSpacing: '-0.6px', marginTop: 16, marginBottom: 6,
                }}>
                  Alex Rivera
                </p>
                <p style={{
                  fontSize: 13, color: subtitleColor, fontFamily: F, marginBottom: 18,
                }}>
                  alex.rivera@gmail.com
                </p>
                <motion.button
                  whileTap={{ scale: 0.95 }}
                  style={{
                    display: 'flex', alignItems: 'center', gap: 8,
                    padding: '10px 22px', borderRadius: 16,
                    background: BLUE + '18', border: `1.5px solid ${BLUE}40`,
                    cursor: 'pointer', outline: 'none',
                  }}
                >
                  <Pencil size={13} color={BLUE} />
                  <span style={{ fontSize: 13, fontWeight: 700, color: BLUE, fontFamily: F }}>
                    Edit Profile
                  </span>
                </motion.button>
              </motion.div>

              {/* divider */}
              <div style={{ height: 1, background: p.border, marginBottom: 22 }} />

              {/* Appearance */}
              <SectionLabel label="Appearance" color={sectionLabelColor} />
              <div style={{
                display: 'flex',
                background: cardBg,
                border: `1px solid ${p.border}`,
                borderRadius: 20, padding: 6, marginBottom: 26,
              }}>
                {THEMES.map(t => {
                  const active = theme === t.key;
                  return (
                    <motion.button
                      key={t.key}
                      whileTap={{ scale: 0.96 }}
                      onClick={() => setTheme(t.key)}
                      style={{
                        flex: 1, display: 'flex', alignItems: 'center',
                        justifyContent: 'center', gap: 7,
                        padding: '10px 0', borderRadius: 16,
                        cursor: 'pointer', outline: 'none', border: 'none',
                        background: active ? BLUE : 'transparent',
                        transition: 'background 0.22s',
                      }}
                    >
                      {t.key === 'dark'
                        ? <Moon size={14} color={active ? '#fff' : subtitleColor} />
                        : <Sun  size={14} color={active ? '#fff' : subtitleColor} />}
                      <span style={{
                        fontSize: 13, fontWeight: 600, fontFamily: F,
                        color: active ? '#fff' : subtitleColor,
                        transition: 'color 0.22s',
                      }}>
                        {t.label}
                      </span>
                      {active && <Check size={12} color="#fff" strokeWidth={3} />}
                    </motion.button>
                  );
                })}
              </div>

              {/* Connected Banks */}
              <SectionLabel label="Connected Banks" color={sectionLabelColor} />
              <div style={{
                background: cardBg, border: `1px solid ${p.border}`,
                borderRadius: 20, overflow: 'hidden', marginBottom: 10,
              }}>
                <AnimatePresence initial={false}>
                  {banks.map((bank, i) => (
                    <motion.div
                      key={bank.id}
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: 'auto' }}
                      exit={{ opacity: 0, height: 0 }}
                      transition={{ duration: 0.2 }}
                    >
                      <div style={{
                        display: 'flex', alignItems: 'center',
                        justifyContent: 'space-between', padding: '13px 16px',
                        borderBottom: i < banks.length - 1
                          ? `1px solid ${p.border}` : 'none',
                      }}>
                        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                          <div style={{
                            width: 36, height: 36, borderRadius: 12,
                            background: bank.color + '22',
                            border: `1px solid ${bank.color}44`,
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                          }}>
                            <CreditCard size={16} color={bank.color} />
                          </div>
                          <div>
                            <p style={{
                              fontSize: 14, fontWeight: 600, color: p.text, fontFamily: F,
                            }}>
                              {bank.name}
                            </p>
                            <p style={{
                              fontSize: 11, color: subtitleColor, fontFamily: F, marginTop: 1,
                            }}>
                              Connected
                            </p>
                          </div>
                        </div>
                        <motion.button
                          whileTap={{ scale: 0.88 }}
                          onClick={() => deleteBank(bank.id)}
                          style={{
                            width: 32, height: 32, borderRadius: 10,
                            background: 'rgba(239,68,68,0.1)',
                            border: '1px solid rgba(239,68,68,0.2)',
                            display: 'flex', alignItems: 'center', justifyContent: 'center',
                            cursor: 'pointer', outline: 'none',
                          }}
                        >
                          <Trash2 size={14} color="#EF4444" />
                        </motion.button>
                      </div>
                    </motion.div>
                  ))}
                </AnimatePresence>

                {/* Inline add form */}
                <AnimatePresence>
                  {addingBank && (
                    <motion.div
                      initial={{ opacity: 0, height: 0 }}
                      animate={{ opacity: 1, height: 'auto' }}
                      exit={{ opacity: 0, height: 0 }}
                      transition={{ duration: 0.18 }}
                      style={{
                        borderTop: banks.length > 0 ? `1px solid ${p.border}` : 'none',
                        padding: '12px 16px',
                        display: 'flex', gap: 10, alignItems: 'center',
                      }}
                    >
                      <input
                        ref={inputRef}
                        autoFocus
                        value={newBankName}
                        onChange={e => setNewBankName(e.target.value)}
                        onKeyDown={e => {
                          if (e.key === 'Enter')  handleAddBank();
                          if (e.key === 'Escape') { setAddingBank(false); setNewBankName(''); }
                        }}
                        placeholder="Bank name…"
                        style={{
                          flex: 1, background: 'transparent', border: 'none', outline: 'none',
                          fontSize: 14, fontWeight: 500, color: p.text, fontFamily: F,
                          caretColor: BLUE,
                        }}
                      />
                      <motion.button
                        whileTap={{ scale: 0.92 }}
                        onClick={handleAddBank}
                        disabled={newBankName.trim().length < 2}
                        style={{
                          padding: '6px 14px', borderRadius: 10, outline: 'none', border: 'none',
                          cursor: newBankName.trim().length >= 2 ? 'pointer' : 'default',
                          background: newBankName.trim().length >= 2 ? BLUE : p.bg3,
                          transition: 'background 0.18s',
                        }}
                      >
                        <span style={{
                          fontSize: 12, fontWeight: 700, fontFamily: F,
                          color: newBankName.trim().length >= 2 ? '#fff' : p.text3,
                        }}>
                          Add
                        </span>
                      </motion.button>
                      <motion.button
                        whileTap={{ scale: 0.9 }}
                        onClick={() => { setAddingBank(false); setNewBankName(''); }}
                        style={{
                          background: 'none', border: 'none',
                          cursor: 'pointer', outline: 'none', padding: 4,
                        }}
                      >
                        <X size={16} color={subtitleColor} />
                      </motion.button>
                    </motion.div>
                  )}
                </AnimatePresence>
              </div>

              {/* Add bank button */}
              {!addingBank && (
                <motion.button
                  whileTap={{ scale: 0.96 }}
                  onClick={() => {
                    setAddingBank(true);
                    setTimeout(() => inputRef.current?.focus(), 60);
                  }}
                  style={{
                    width: '100%', display: 'flex', alignItems: 'center',
                    justifyContent: 'center', gap: 8, padding: '13px 0',
                    borderRadius: 18, cursor: 'pointer', outline: 'none',
                    background: BLUE + '12', border: `1.5px dashed ${BLUE}55`,
                    marginBottom: 26,
                  }}
                >
                  <Plus size={15} color={BLUE} />
                  <span style={{ fontSize: 13, fontWeight: 700, color: BLUE, fontFamily: F }}>
                    Add Bank Account
                  </span>
                </motion.button>
              )}

              {/* Preferences */}
              <SectionLabel label="Preferences" color={sectionLabelColor} />
              <PreferenceRow
                icon={<Brain size={18} color={BLUE} />}
                label="AI Auto-Categorize"
                sub="Smart expense tagging"
                cardBg={cardBg} border={p.border}
                textColor={p.text} subColor={subtitleColor}
                right={
                  <div style={{
                    width: 44, height: 24, borderRadius: 12, background: BLUE,
                    display: 'flex', alignItems: 'center',
                    justifyContent: 'flex-end', padding: '0 3px',
                    boxShadow: `0 0 10px ${BLUE}55`,
                  }}>
                    <div style={{
                      width: 18, height: 18, borderRadius: 9, background: '#fff',
                    }} />
                  </div>
                }
              />
              <PreferenceRow
                icon={<Shield size={18} color={BLUE} />}
                label="Privacy & Security"
                sub="Manage permissions"
                cardBg={cardBg} border={p.border}
                textColor={p.text} subColor={subtitleColor}
              />
              <PreferenceRow
                icon={<Info size={18} color={BLUE} />}
                label="About"
                sub="v2.4.1 · Expense Tracker"
                cardBg={cardBg} border={p.border}
                textColor={p.text} subColor={subtitleColor}
              />

              {/* divider */}
              <div style={{ height: 1, background: p.border, margin: '8px 0 20px' }} />

              {/* Sign Out */}
              <motion.button
                whileTap={{ scale: 0.97 }}
                style={{
                  width: '100%', display: 'flex', alignItems: 'center',
                  justifyContent: 'center', gap: 10, padding: '15px 0',
                  borderRadius: 20, cursor: 'pointer', outline: 'none',
                  background: 'rgba(239,68,68,0.08)',
                  border: '1px solid rgba(239,68,68,0.22)',
                }}
              >
                <LogOut size={16} color="#EF4444" />
                <span style={{
                  fontSize: 15, fontWeight: 700, color: '#EF4444', fontFamily: F,
                }}>
                  Sign Out
                </span>
              </motion.button>
            </div>
          </motion.div>
        </>
      )}
    </AnimatePresence>
  );
}