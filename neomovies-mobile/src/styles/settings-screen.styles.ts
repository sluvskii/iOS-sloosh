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

export function createSettingsScreenStyles(theme: ThemePalette) {
  return StyleSheet.create({
    container: {
      flex: 1,
    },
    content: {
      paddingHorizontal: Spacing.four,
      paddingTop: Spacing.two,
      paddingBottom: Spacing.six,
      gap: Spacing.four,
    },
    section: {
      gap: Spacing.one,
    },
    sectionTitle: {
      fontSize: 13,
      fontWeight: '600',
      color: theme.textMuted,
      textTransform: 'uppercase',
      letterSpacing: 0.5,
      paddingHorizontal: Spacing.two,
      marginBottom: Spacing.one,
    },
    settingItem: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      backgroundColor: theme.backgroundElement,
      paddingVertical: Spacing.three,
      paddingHorizontal: Spacing.three,
      borderRadius: 16,
      minHeight: 64,
    },
    settingLeft: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.three,
      flex: 1,
    },
    iconWrapper: {
      width: 36,
      height: 36,
      borderRadius: 18,
      backgroundColor: theme.backgroundSelected,
      alignItems: 'center',
      justifyContent: 'center',
    },
    settingLabel: {
      fontSize: 16,
      fontWeight: '600',
      color: theme.text,
    },
    toggle: {
      width: 52,
      height: 32,
      borderRadius: 16,
      backgroundColor: theme.backgroundSelected,
      padding: 2,
      justifyContent: 'center',
    },
    toggleActive: {
      backgroundColor: theme.accent,
    },
    toggleThumb: {
      width: 28,
      height: 28,
      borderRadius: 14,
      backgroundColor: '#FFFFFF',
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.1,
      shadowRadius: 3,
      elevation: 2,
    },
    toggleThumbActive: {
      alignSelf: 'flex-end',
    },
  });
}
