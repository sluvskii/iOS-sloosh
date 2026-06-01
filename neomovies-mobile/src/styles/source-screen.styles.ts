import { StyleSheet } from 'react-native';

import { Spacing } from '@/constants/theme';

type ThemePalette = {
  backgroundSelected: string;
};

export function createSourceScreenStyles(theme: ThemePalette) {
  return StyleSheet.create({
    container: {
      flex: 1,
    },
    content: {
      paddingHorizontal: Spacing.four,
      paddingTop: Spacing.two,
      paddingBottom: Spacing.six,
    },
    itemSeparator: {
      height: Spacing.two,
    },
    iconWrapper: {
      width: 32,
      height: 32,
      borderRadius: 16,
      backgroundColor: theme.backgroundSelected,
      alignItems: 'center',
      justifyContent: 'center',
    },
    iconWrapperDisabled: {
      opacity: 0.6,
    },
  });
}
