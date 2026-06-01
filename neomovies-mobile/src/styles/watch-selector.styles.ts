import { StyleSheet } from 'react-native';

import { Radius, Spacing } from '@/constants/theme';

type ThemePalette = {
  backgroundElement: string;
  border: string;
  textSecondary: string;
  accent: string;
};

export function createWatchSelectorStyles(theme: ThemePalette) {
  return StyleSheet.create({
    container: { flex: 1 },
    content: {
      paddingHorizontal: Spacing.three,
      paddingBottom: 120,
      gap: Spacing.three,
    },
    card: {
      borderWidth: 1,
      borderColor: theme.border,
      backgroundColor: theme.backgroundElement,
      borderRadius: Radius.lg,
      padding: Spacing.three,
      gap: Spacing.two,
    },
    row: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: Spacing.two,
    },
    title: {
      fontSize: 18,
      lineHeight: 22,
      fontWeight: '700',
    },
    subtitle: {
      fontSize: 13,
      lineHeight: 18,
      color: theme.textSecondary,
    },
    sectionTitle: {
      fontSize: 15,
      lineHeight: 20,
      fontWeight: '700',
      color: theme.textSecondary,
      textTransform: 'uppercase',
      letterSpacing: 0.3,
    },
    pillRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: Spacing.one,
    },
    pill: {
      borderRadius: 999,
      borderWidth: 1,
      borderColor: theme.border,
      paddingHorizontal: Spacing.two,
      paddingVertical: Spacing.one,
    },
    seasonButton: {
      borderWidth: 1,
      borderColor: theme.border,
      backgroundColor: theme.backgroundElement,
      borderRadius: Radius.md,
      paddingHorizontal: Spacing.two,
      paddingVertical: Spacing.two,
      minWidth: 74,
      alignItems: 'center',
      justifyContent: 'center',
    },
    seasonButtonActive: {
      borderColor: theme.accent,
      backgroundColor: `${theme.accent}1A`,
    },
    episodeButton: {
      borderWidth: 1,
      borderColor: theme.border,
      backgroundColor: theme.backgroundElement,
      borderRadius: Radius.md,
      paddingHorizontal: Spacing.two,
      paddingVertical: Spacing.two,
      minWidth: 92,
      alignItems: 'center',
      justifyContent: 'center',
    },
    episodeButtonActive: {
      borderColor: theme.accent,
      backgroundColor: `${theme.accent}1A`,
    },
    urlBlock: {
      borderWidth: 1,
      borderColor: theme.border,
      borderRadius: Radius.md,
      padding: Spacing.two,
      gap: Spacing.one,
      backgroundColor: theme.backgroundElement,
    },
  });
}
