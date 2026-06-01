import { StyleSheet } from 'react-native';

import { Spacing } from '@/constants/theme';

type ThemePalette = {
  text: string;
  background: string;
  backgroundElement: string;
  backgroundSelected: string;
  textSecondary: string;
  textMuted: string;
  accent: string;
  border: string;
};

export function createCreditsScreenStyles(theme: ThemePalette) {
  return StyleSheet.create({
    container: {
      flex: 1,
    },
    content: {
      paddingHorizontal: Spacing.four,
      paddingTop: Spacing.two,
      paddingBottom: Spacing.six,
      gap: Spacing.five,
    },
    section: {
      gap: Spacing.three,
    },
    sectionHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.two,
      paddingHorizontal: Spacing.two,
    },
    sectionTitle: {
      fontSize: 17,
      fontWeight: '600',
      color: theme.text,
    },
    creditsCard: {
      backgroundColor: theme.backgroundElement,
      borderRadius: 16,
      padding: Spacing.four,
      gap: Spacing.three,
    },
    creditItem: {
      paddingBottom: Spacing.three,
      borderBottomWidth: 1,
      borderBottomColor: theme.border,
    },
    creditItemLast: {
      paddingBottom: 0,
      borderBottomWidth: 0,
    },
    creditName: {
      fontSize: 15,
      fontWeight: '600',
      color: theme.text,
      marginBottom: 4,
    },
    creditDescription: {
      fontSize: 14,
      color: theme.textSecondary,
      lineHeight: 20,
    },
  });
}
