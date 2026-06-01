import { StyleSheet } from 'react-native';

import { Spacing } from '@/constants/theme';

type ThemePalette = {
  backgroundSelected: string;
  backgroundElement: string;
  textMuted: string;
  text: string;
};

export function createSelectionItemStyles(theme: ThemePalette) {
  return StyleSheet.create({
    item: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      paddingVertical: Spacing.three,
      paddingHorizontal: Spacing.four,
      borderRadius: 14,
      minHeight: 64,
      backgroundColor: theme.backgroundElement,
    },
    itemSelected: {
      backgroundColor: theme.backgroundSelected,
    },
    itemDisabled: {
      opacity: 0.5,
    },
    itemPressed: {
      opacity: 0.8,
    },
    left: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.three,
      flex: 1,
    },
    leftAccessory: {
      minWidth: 32,
      alignItems: 'center',
      justifyContent: 'center',
    },
    textWrap: {
      flex: 1,
    },
    title: {
      fontSize: 16,
      fontWeight: '500',
      marginBottom: 2,
      color: theme.text,
    },
    titleDisabled: {
      color: theme.textMuted,
    },
    subtitle: {
      fontSize: 13,
      lineHeight: 17,
    },
  });
}
