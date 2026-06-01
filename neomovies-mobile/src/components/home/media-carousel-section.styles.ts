import { StyleSheet } from 'react-native';

import { Spacing } from '@/constants/theme';

export const mediaCarouselSectionStyles = StyleSheet.create({
  sectionWrap: {
    gap: Spacing.three,
    marginHorizontal: -Spacing.four,
  },
  headerRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingBottom: Spacing.one,
    paddingHorizontal: Spacing.four,
  },
  headerAction: {
    width: 32,
    height: 32,
    borderRadius: 16,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sectionTitle: { 
    fontSize: 20, 
    lineHeight: 26, 
    fontWeight: '700',
    letterSpacing: -0.3,
  },
  row: { paddingHorizontal: Spacing.four },
  rowSeparator: { width: Spacing.three },
  overlayRow: {
    flexDirection: 'row',
    gap: Spacing.three,
  },
  skeletonPoster: {
    width: 140,
    height: 210,
    borderRadius: 16,
  },
  skeletonBackdrop: {
    width: 280,
    height: 157,
    borderRadius: 16,
  },
});
