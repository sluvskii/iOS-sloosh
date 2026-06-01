import { StyleSheet } from 'react-native';

import { Spacing } from '@/constants/theme';

type ThemePalette = {
  backgroundElement: string;
  textSecondary: string;
  accent: string;
};

export function createFavoritesScreenStyles(theme: ThemePalette) {
  return StyleSheet.create({
    emptyWrap: {
      flex: 1,
      minHeight: 360,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: Spacing.four,
      gap: Spacing.three,
    },
    emptyIconWrap: {
      width: 56,
      height: 56,
      borderRadius: 999,
      backgroundColor: theme.backgroundElement,
      alignItems: 'center',
      justifyContent: 'center',
    },
    emptyText: {
      textAlign: 'center',
      color: theme.textSecondary,
      maxWidth: 260,
      lineHeight: 22,
      fontSize: 15,
      fontWeight: '500',
    },
    authLine: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      justifyContent: 'center',
      alignItems: 'center',
      maxWidth: 280,
    },
    authActionText: {
      color: theme.accent,
      fontSize: 15,
      lineHeight: 22,
      fontWeight: '700',
    },
    authSuffixText: {
      textAlign: 'center',
      color: theme.textSecondary,
      fontSize: 15,
      lineHeight: 22,
      fontWeight: '500',
    },
  });
}
