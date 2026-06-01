import { StyleSheet } from 'react-native';

import { Radius, Spacing } from '@/constants/theme';

export const backdropCardStyles = StyleSheet.create({
  container: {
    width: 280,
    height: 157,
    borderRadius: Radius.lg,
    overflow: 'hidden',
    position: 'relative',
  },
  fluidContainer: {
    width: '100%',
    aspectRatio: 280 / 157,
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
    height: 70,
  },
  placeholder: {
    width: '100%',
    height: '100%',
  },
  overlay: {
    position: 'absolute',
    left: 0,
    right: 0,
    bottom: 0,
    height: 50,
    backgroundColor: 'transparent',
    paddingHorizontal: 12,
    paddingBottom: 10,
    justifyContent: 'flex-end',
  },
  row: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: Spacing.one,
  },
  title: {
    flex: 1,
    color: '#FFFFFF',
    fontSize: 13,
    lineHeight: 16,
    fontWeight: '700',
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
