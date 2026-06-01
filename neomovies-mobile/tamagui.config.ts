import { createTamagui, createTokens } from '@tamagui/core';

const tokens = createTokens({
  size: {
    0: 0,
    1: 12,
    2: 14,
    3: 16,
    4: 18,
    5: 22,
    6: 28,
    true: 16,
  },
  space: {
    0: 0,
    1: 4,
    2: 8,
    3: 12,
    4: 16,
    5: 24,
    6: 32,
    7: 40,
    true: 16,
  },
  radius: {
    0: 0,
    1: 8,
    2: 12,
    3: 16,
    4: 20,
    true: 12,
  },
  zIndex: {
    0: 0,
    1: 100,
    2: 200,
    3: 300,
    true: 1,
  },
  color: {
    bg: '#05070B',
    bgSoft: '#0D121B',
    card: '#101622',
    text: '#F4F7FF',
    textMuted: '#9AA5BE',
    border: '#202A3B',
    accent: '#5AB2FF',
    danger: '#FF5A70',
    true: '#F4F7FF',
  },
});

const themes = {
  dark: {
    background: tokens.color.bg,
    backgroundHover: tokens.color.bgSoft,
    backgroundPress: tokens.color.card,
    backgroundFocus: tokens.color.bgSoft,
    color: tokens.color.text,
    colorHover: tokens.color.text,
    colorPress: tokens.color.text,
    colorFocus: tokens.color.text,
    borderColor: tokens.color.border,
    borderColorHover: tokens.color.border,
    borderColorPress: tokens.color.border,
    borderColorFocus: tokens.color.accent,
    shadowColor: '#000000',
    outlineColor: tokens.color.accent,
    placeholderColor: tokens.color.textMuted,
  },
};

const config = createTamagui({
  tokens,
  themes,
  defaultTheme: 'dark',
});

export type AppTamaguiConfig = typeof config;

declare module '@tamagui/core' {
  interface TamaguiCustomConfig extends AppTamaguiConfig {}
}

export default config;
