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

export function createAboutScreenStyles(theme: ThemePalette) {
  return StyleSheet.create({
    container: {
      flex: 1,
    },
    content: {
      paddingHorizontal: Spacing.three,
      paddingTop: Spacing.three,
      paddingBottom: Spacing.six,
      gap: Spacing.three,
    },
    centeredIconWrap: {
      alignItems: 'center',
      justifyContent: 'center',
      paddingTop: Spacing.one,
      paddingBottom: Spacing.one,
    },
    centeredAppIcon: {
      width: 64,
      height: 64,
      borderRadius: 16,
    },
    appDescription: {
      fontSize: 14,
      color: theme.textMuted,
      lineHeight: 20,
      paddingHorizontal: 2,
      textAlign: 'center',
    },
    listStack: {
      gap: Spacing.two,
    },
    iconWrapper: {
      width: 36,
      height: 36,
      borderRadius: 18,
      backgroundColor: theme.backgroundSelected,
      alignItems: 'center',
      justifyContent: 'center',
    },
    preferenceTitle: {
      fontSize: 15,
      fontWeight: '600',
      color: theme.text,
      marginBottom: 2,
    },
    versionCard: {
      borderRadius: 16,
      borderWidth: 1,
      borderColor: theme.border,
      backgroundColor: theme.backgroundElement,
      paddingVertical: Spacing.three,
      paddingHorizontal: Spacing.four,
      gap: 8,
    },
    versionHeader: {
      paddingBottom: 2,
      alignItems: 'center',
    },
    metaRow: {
      flexDirection: 'row',
      justifyContent: 'space-between',
      alignItems: 'center',
      minHeight: 22,
    },
    metaSeparator: {
      height: 1,
      backgroundColor: theme.border,
    },
    metaLabel: {
      fontSize: 13,
      color: theme.textMuted,
    },
    metaValue: {
      fontSize: 13,
      color: theme.textSecondary,
      fontWeight: '600',
      textAlign: 'right',
    },
  });
}
