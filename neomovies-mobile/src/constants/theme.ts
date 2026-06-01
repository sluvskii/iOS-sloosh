import '@/global.css';

import { Platform } from 'react-native';

const isIOS = Platform.OS === 'ios';

export const Colors = {
  light: {
    text: '#16181D',
    background: '#F3F4F6',
    chrome: '#F7F8FA',
    backgroundElement: '#FFFFFF',
    backgroundSelected: '#ECEFF3',
    textSecondary: '#555E6B',
    textMuted: '#808A98',
    accent: '#FF385C',
    accentMuted: '#FFE5EB',
    danger: '#DC2626',
    border: '#DEE3EA',
  },
  dark: {
    text: '#F2F3F5',
    background: isIOS ? '#0E1013' : '#121212',
    chrome: '#141414',
    backgroundElement: isIOS ? '#171A1F' : '#1A1A1A',
    backgroundSelected: isIOS ? '#23272E' : '#2A2F36',
    textSecondary: '#A8ADB7',
    textMuted: '#7D838F',
    accent: '#FF385C',
    accentMuted: '#2B1D21',
    danger: '#EF4444',
    border: '#2A2D33',
  },
} as const;

export type ThemeColor = keyof typeof Colors.light & keyof typeof Colors.dark;

export const Fonts = Platform.select({
  ios: {
    sans: 'system-ui',
    serif: 'ui-serif',
    rounded: 'ui-rounded',
    mono: 'ui-monospace',
  },
  default: {
    sans: 'normal',
    serif: 'serif',
    rounded: 'normal',
    mono: 'monospace',
  },
  web: {
    sans: 'var(--font-display)',
    serif: 'var(--font-serif)',
    rounded: 'var(--font-rounded)',
    mono: 'var(--font-mono)',
  },
});

export const Spacing = {
  half: 2,
  one: 4,
  two: 8,
  three: 16,
  four: 24,
  five: 32,
  six: 48,
} as const;

export const Radius = {
  sm: 8,
  md: 12,
  lg: 20,
  xl: 28,
} as const;

export const BottomTabInset = Platform.select({ ios: 50, android: 80 }) ?? 0;
export const MaxContentWidth = 920;
