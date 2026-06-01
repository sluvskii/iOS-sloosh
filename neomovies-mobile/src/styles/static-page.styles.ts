import { StyleSheet } from 'react-native';

import { Radius, Spacing } from '@/constants/theme';

type ThemePalette = {
  border: string;
  backgroundElement: string;
  textSecondary: string;
};

export function createStaticPageStyles(theme: ThemePalette) {
  return StyleSheet.create({
    container: { flex: 1 },
    content: {
      paddingHorizontal: Spacing.three,
      paddingTop: Spacing.three,
      paddingBottom: 110,
      gap: Spacing.two,
    },
    card: {
      borderWidth: 1,
      borderColor: theme.border,
      borderRadius: Radius.lg,
      backgroundColor: theme.backgroundElement,
      padding: Spacing.three,
      gap: Spacing.two,
    },
    text: {
      color: theme.textSecondary,
      fontSize: 14,
      lineHeight: 20,
    },
  });
}
