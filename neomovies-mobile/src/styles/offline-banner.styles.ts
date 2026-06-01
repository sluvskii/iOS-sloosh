import { StyleSheet } from 'react-native';

import { Radius, Spacing } from '@/constants/theme';

export const offlineBannerStyles = StyleSheet.create({
  container: {
    marginHorizontal: Spacing.four,
    marginBottom: Spacing.two,
    marginTop: -Spacing.one,
    borderWidth: 1,
    borderRadius: Radius.md,
    paddingHorizontal: Spacing.three,
    paddingVertical: Spacing.two,
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.two,
  },
  copy: {
    flex: 1,
    gap: 2,
  },
  title: {
    fontWeight: '700',
  },
  text: {
    fontWeight: '600',
  },
});
