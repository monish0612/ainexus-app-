import { createContext, useContext, useState, useCallback, useEffect } from 'react';

export interface Bank {
  id: string;
  name: string;
  color: string;
}

const BANK_PALETTE = [
  '#0D59F2', '#7C3AED', '#059669', '#DC2626',
  '#D97706', '#0891B2', '#9333EA', '#0F766E', '#BE185D',
];

export const getBankColor = (index: number) => BANK_PALETTE[index % BANK_PALETTE.length];

const DEFAULT_BANKS: Bank[] = [
  { id: 'b1', name: 'HDFC Bank',      color: '#0D59F2' },
  { id: 'b2', name: 'SBI',            color: '#059669' },
  { id: 'b3', name: 'ICICI Bank',     color: '#DC2626' },
  { id: 'b4', name: 'Axis Bank',      color: '#7C3AED' },
  { id: 'b5', name: 'Kotak Mahindra', color: '#D97706' },
];

interface SettingsContextType {
  settingsOpen: boolean;
  openSettings: () => void;
  closeSettings: () => void;
  banks: Bank[];
  addBank: (name: string) => void;
  deleteBank: (id: string) => void;
  theme: 'dark' | 'white';
  setTheme: (t: 'dark' | 'white') => void;
}

const SettingsContext = createContext<SettingsContextType | null>(null);

export function SettingsProvider({ children }: { children: React.ReactNode }) {
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [theme, setTheme] = useState<'dark' | 'white'>('dark');
  const [banks, setBanks] = useState<Bank[]>(() => {
    try {
      const s = localStorage.getItem('app_banks');
      return s ? JSON.parse(s) : DEFAULT_BANKS;
    } catch { return DEFAULT_BANKS; }
  });

  useEffect(() => {
    localStorage.setItem('app_banks', JSON.stringify(banks));
  }, [banks]);

  const openSettings = useCallback(() => setSettingsOpen(true), []);
  const closeSettings = useCallback(() => setSettingsOpen(false), []);

  const addBank = useCallback((name: string) => {
    if (!name.trim()) return;
    setBanks(prev => {
      const color = getBankColor(prev.length);
      return [...prev, { id: crypto.randomUUID(), name: name.trim(), color }];
    });
  }, []);

  const deleteBank = useCallback((id: string) => {
    setBanks(prev => prev.filter(b => b.id !== id));
  }, []);

  return (
    <SettingsContext.Provider value={{ settingsOpen, openSettings, closeSettings, banks, addBank, deleteBank, theme, setTheme }}>
      {children}
    </SettingsContext.Provider>
  );
}

export function useSettings() {
  const ctx = useContext(SettingsContext);
  if (!ctx) throw new Error('useSettings must be used within SettingsProvider');
  return ctx;
}
