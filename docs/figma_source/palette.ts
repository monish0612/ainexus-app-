import { useMemo } from 'react';
import { useSettings } from './settingsContext';

export interface Palette {
  bg: string;        // page background
  bg1: string;       // elevated surface
  bg2: string;       // card / container
  bg3: string;       // input / tab bg
  bg4: string;       // pressed / hover
  text: string;      // primary text
  text2: string;     // secondary text
  text3: string;     // tertiary text
  text4: string;     // muted text
  text5: string;     // very muted text
  border: string;    // standard border
  border2: string;   // subtle border
  headerBg: string;  // header / nav background
  navBg: string;     // bottom nav background
  isDark: boolean;
}

export function createPalette(theme: 'dark' | 'white'): Palette {
  if (theme === 'white') {
    return {
      bg:       '#FFFFFF',
      bg1:      '#F8FAFC',
      bg2:      'rgba(0,0,0,0.04)',
      bg3:      'rgba(0,0,0,0.06)',
      bg4:      'rgba(0,0,0,0.09)',
      text:     '#0F172A',
      text2:    '#475569',
      text3:    'rgba(0,0,0,0.55)',
      text4:    'rgba(0,0,0,0.38)',
      text5:    'rgba(0,0,0,0.25)',
      border:   'rgba(0,0,0,0.09)',
      border2:  'rgba(0,0,0,0.06)',
      headerBg: '#FFFFFF',
      navBg:    'rgba(255,255,255,0.97)',
      isDark:   false,
    };
  }
  return {
    bg:       '#000000',
    bg1:      '#060608',
    bg2:      'rgba(255,255,255,0.05)',
    bg3:      'rgba(255,255,255,0.08)',
    bg4:      'rgba(255,255,255,0.12)',
    text:     '#F1F5F9',
    text2:    '#94A3B8',
    text3:    'rgba(255,255,255,0.42)',
    text4:    'rgba(255,255,255,0.28)',
    text5:    'rgba(255,255,255,0.18)',
    border:   'rgba(255,255,255,0.08)',
    border2:  'rgba(255,255,255,0.05)',
    headerBg: '#000000',
    navBg:    'rgba(0,0,0,0.97)',
    isDark:   true,
  };
}

export function usePalette(): Palette {
  const { theme } = useSettings();
  return useMemo(() => createPalette(theme), [theme]);
}
