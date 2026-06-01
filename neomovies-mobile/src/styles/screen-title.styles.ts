import { StyleSheet } from 'react-native';

import { Fonts, Spacing } from '@/constants/theme';

export const screenTitleStyles = StyleSheet.create({
  container: {
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 48,
    paddingHorizontal: Spacing.four,
    paddingTop: Spacing.one,
    paddingBottom: Spacing.three,
  },
  backButton: {
    position: 'absolute',
    left: 0,
    top: 0,
    bottom: Spacing.one,
    width: 44,
    alignItems: 'flex-start',
    justifyContent: 'center',
  },
  rightButton: {
    position: 'absolute',
    right: 0,
    top: 0,
    bottom: Spacing.one,
    width: 44,
    alignItems: 'flex-end',
    justifyContent: 'center',
  },
  backButtonHit: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  rightButtonHit: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  title: {
    fontFamily: Fonts.rounded,
    fontSize: 17,
    lineHeight: 22,
    fontWeight: '600',
  },
});
