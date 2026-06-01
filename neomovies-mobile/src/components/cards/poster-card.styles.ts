import { StyleSheet } from 'react-native';

import { Radius, Spacing } from '@/constants/theme';

export const posterCardStyles = StyleSheet.create({
  container: {
    width: 140,
    height: 210,
    borderRadius: Radius.lg,
    overflow: 'hidden',
    position: 'relative',
  },
  fluidContainer: {
    width: '100%',
    aspectRatio: 2 / 3,
    borderRadius: Radius.lg,
    overflow: 'hidden',
    position: 'relative',
  },
  image: {
    width: '100%',
    height: '100%',
    transform: [{ scale: 1.01 }],
  },
  shadeTop: {
    position: 'absolute',
    left: 0,
    right: 0,
    top: 0,
    bottom: 0,
    backgroundColor: 'rgba(0, 0, 0, 0.03)',
  },
  shadeBottom: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    height: 90,
  },
  placeholder: {
    width: '100%',
    height: '100%',
  },
  gradientOverlay: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    paddingTop: 30,
    backgroundColor: 'transparent',
    paddingHorizontal: 10,
    paddingBottom: 10,
    justifyContent: 'flex-end',
  },
  bottomRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    justifyContent: 'space-between',
    gap: Spacing.one,
  },
  title: {
    flex: 1,
    color: '#FFFFFF',
    fontSize: 12,
    lineHeight: 14,
    fontWeight: '700',
  },
  metaText: {
    color: 'rgba(255,255,255,0.9)',
    fontSize: 11,
    lineHeight: 13,
    fontWeight: '600',
    flex: 1,
  },
  ratingPill: {
    minWidth: 48,
    height: 22,
    borderRadius: 99,
    backgroundColor: 'rgba(255, 255, 255, 0.2)',
    borderWidth: 0,
    borderColor: 'transparent',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 2,
    paddingHorizontal: 7,
  },
  ratingText: {
    color: '#FFFFFF',
    fontSize: 11,
    lineHeight: 11,
    fontWeight: '700',
  },
});
