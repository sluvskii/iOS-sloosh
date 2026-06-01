import { StyleSheet } from 'react-native';

import { Radius, Spacing } from '@/constants/theme';

export const categoryScreenStyles = StyleSheet.create({
  container: { flex: 1 },
  listContent: {
    paddingHorizontal: Spacing.three,
    paddingBottom: 110,
    paddingTop: Spacing.two,
    gap: Spacing.three,
  },
  row: {
    justifyContent: 'flex-start',
    gap: Spacing.three,
  },
  gridItem: {
    minWidth: 0,
  },
  skeleton: {
    width: '100%',
    borderRadius: Radius.md,
    aspectRatio: 2 / 3,
  },
  footerWrap: {
    paddingTop: 0,
  },
  footerRow: {
    flexDirection: 'row',
    gap: Spacing.three,
  },
});
