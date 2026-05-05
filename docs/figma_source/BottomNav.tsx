import { motion } from 'motion/react';
import { Wallet, Newspaper, GraduationCap, Cloud } from 'lucide-react';
import { useNavigate, useLocation } from 'react-router';
import { usePalette } from '../utils/palette';

const NAV_ITEMS = [
  { path: '/', Icon: Wallet },
  { path: '/news', Icon: Newspaper },
  { path: '/tutor', Icon: GraduationCap },
  { path: '/cloud', Icon: Cloud },
] as const;

export function BottomNav() {
  const navigate = useNavigate();
  const location = useLocation();
  const p = usePalette();

  const activeColor  = p.isDark ? '#ffffff' : '#0F172A';
  const inactiveColor = p.isDark ? 'rgba(255,255,255,0.38)' : 'rgba(0,0,0,0.35)';
  const dotColor     = p.isDark ? '#ffffff' : '#0F172A';

  return (
    <div
      className="shrink-0 flex items-center justify-around px-4"
      style={{
        background: p.navBg,
        borderTop: `1px solid ${p.border}`,
        height: 56,
        paddingBottom: 'env(safe-area-inset-bottom, 0px)',
        backdropFilter: !p.isDark ? 'blur(12px)' : undefined,
      }}
    >
      {NAV_ITEMS.map(({ path, Icon }) => {
        const isActive = location.pathname === path;
        return (
          <motion.button
            key={path}
            whileTap={{ scale: 0.82 }}
            onClick={() => navigate(path)}
            className="flex items-center justify-center relative"
            style={{ width: 48, height: 48, borderRadius: 24 }}
          >
            <Icon
              size={24}
              color={isActive ? activeColor : inactiveColor}
              strokeWidth={isActive ? 2.4 : 1.8}
              style={{ transition: 'color 0.15s, stroke-width 0.15s' }}
            />
            {isActive && (
              <motion.div
                layoutId="nav-dot"
                className="absolute rounded-full nav-dot"
                style={{
                  bottom: 4,
                  left: '50%',
                  transform: 'translateX(-50%)',
                  width: 4,
                  height: 4,
                  background: dotColor,
                }}
                transition={{ type: 'spring', damping: 28, stiffness: 340 }}
              />
            )}
          </motion.button>
        );
      })}
    </div>
  );
}
