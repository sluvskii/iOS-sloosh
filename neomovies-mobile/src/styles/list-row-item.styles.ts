import { StyleSheet } from 'react-native';

import { Spacing } from '@/constants/theme';

type ThemePalette = {
  backgroundElement: string;
  text: string;
  textSecondary: string;
};

export function createListRowItemStyles(theme: ThemePalette) {
  return StyleSheet.create({
    row: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      backgroundColor: theme.backgroundElement,
      paddingVertical: Spacing.three,
      paddingHorizontal: Spacing.three,
      borderRadius: 16,
      minHeight: 64,
    },
    pressed: {
      opacity: 0.82,
    },
    left: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.three,
      flex: 1,
    },
    textWrap: {
      flex: 1,
    },
    title: {
      fontSize: 16,
      fontWeight: '600',
      color: theme.text,
    },
    subtitle: {
      fontSize: 13,
      color: theme.textSecondary,
      marginTop: 2,
    },
    right: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.two,
    },
    value: {
      fontSize: 15,
      color: theme.textSecondary,
    },
  });
}
