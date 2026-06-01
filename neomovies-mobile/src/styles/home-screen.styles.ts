import { StyleSheet } from 'react-native';

import { Spacing } from '@/constants/theme';

export const homeScreenStyles = StyleSheet.create({
  container: { flex: 1 },
  content: {
    paddingHorizontal: Spacing.four,
    paddingTop: Spacing.two,
    paddingBottom: Spacing.six,
    gap: Spacing.four,
  },
  searchRow: {
    borderRadius: 14,
    borderWidth: 0,
    minHeight: 48,
    paddingHorizontal: Spacing.three,
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
  },
  errorCard: {
    borderWidth: 1,
    borderRadius: 16,
    padding: Spacing.three,
  },
});
