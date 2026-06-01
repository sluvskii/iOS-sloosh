import { StyleSheet } from 'react-native';

import { Spacing } from '@/constants/theme';

export function createLanguageScreenStyles() {
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
    flagBadge: {
      width: 32,
      height: 32,
      alignItems: 'center',
      justifyContent: 'center',
    },
    flagImage: {
      width: 30,
      height: 30,
      borderRadius: 15,
    },
  });
}
