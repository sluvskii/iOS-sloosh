import { StyleSheet } from 'react-native';

import { Radius, Spacing } from '@/constants/theme';

type ThemePalette = {
  border: string;
  backgroundElement: string;
  text: string;
  textSecondary: string;
};

export function createSearchScreenStyles(theme: ThemePalette) {
  return StyleSheet.create({
    container: { flex: 1 },
    content: {
      paddingTop: Spacing.four,
      gap: Spacing.four,
    },
    listContent: {
      paddingBottom: 120,
      paddingHorizontal: Spacing.four,
      gap: Spacing.three,
    },
    searchRow: {
      flexDirection: 'row',
      alignItems: 'center',
      borderWidth: 0,
      borderColor: 'transparent',
      borderRadius: Radius.lg,
      backgroundColor: theme.backgroundElement,
      paddingHorizontal: Spacing.three,
      gap: Spacing.two,
      minHeight: 56,
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 2 },
      shadowOpacity: 0.05,
      shadowRadius: 8,
      elevation: 2,
    },
    input: {
      flex: 1,
      color: theme.text,
      fontSize: 17,
      paddingVertical: 12,
      fontWeight: '500',
    },
    searchAction: {
      width: 36,
      height: 36,
      borderRadius: 18,
      alignItems: 'center',
      justifyContent: 'center',
      marginRight: -4,
    },
    recentBlock: {
      gap: Spacing.two,
    },
    recentTitle: {
      fontSize: 14,
      fontWeight: '600',
      letterSpacing: -0.2,
    },
    recentRow: {
      flexDirection: 'row',
      alignItems: 'center',
      paddingRight: Spacing.one,
    },
    recentItemSeparator: {
      width: Spacing.two,
    },
    recentChip: {
      borderWidth: 0,
      borderColor: 'transparent',
      backgroundColor: theme.backgroundElement,
      borderRadius: 999,
      flexDirection: 'row',
      alignItems: 'center',
      maxWidth: 220,
      minHeight: 34,
      paddingLeft: Spacing.two,
      paddingRight: Spacing.two,
      paddingVertical: 6,
      gap: Spacing.one,
      shadowColor: '#000',
      shadowOffset: { width: 0, height: 1 },
      shadowOpacity: 0.04,
      shadowRadius: 4,
      elevation: 1,
    },
    recentChipIconWrap: {
      width: 18,
      height: 18,
      borderRadius: 9,
      alignItems: 'center',
      justifyContent: 'center',
    },
    recentChipMain: {
      maxWidth: 152,
      justifyContent: 'center',
      alignItems: 'flex-start',
      flexShrink: 1,
    },
    recentChipText: {
      fontSize: 13,
      lineHeight: 16,
    },
    recentChipRemove: {
      width: 20,
      height: 20,
      alignItems: 'center',
      justifyContent: 'center',
      borderRadius: 999,
    },
    resultsGrid: {
      marginTop: Spacing.two,
      gap: Spacing.three,
    },
    rowGap: {
      justifyContent: 'flex-start',
    },
    gridItem: {
      flex: 1,
      minWidth: 0,
    },
    gridSkeleton: {
      width: '100%',
      borderRadius: Radius.lg,
      aspectRatio: 2 / 3,
    },
    footerSkeletonWrap: {
      paddingTop: Spacing.two,
      paddingBottom: Spacing.four,
    },
    footerSkeletonRow: {
      flexDirection: 'row',
      gap: Spacing.three,
    },
    footerSkeletonItem: {
      width: '100%',
      borderRadius: Radius.lg,
      aspectRatio: 2 / 3,
    },
    emptyState: {
      fontSize: 15,
      lineHeight: 22,
      color: theme.textSecondary,
      textAlign: 'center',
      marginTop: Spacing.five,
    },
    errorText: {
      fontSize: 14,
      lineHeight: 20,
      color: theme.textSecondary,
    },
    offlineCard: {
      marginTop: Spacing.four,
      borderWidth: 1,
      borderColor: theme.border,
      borderRadius: Radius.lg,
      backgroundColor: theme.backgroundElement,
      paddingHorizontal: Spacing.four,
      paddingVertical: Spacing.four,
      alignItems: 'center',
      gap: Spacing.three,
    },
    offlineFlow: {
      alignItems: 'center',
      gap: Spacing.two,
      marginBottom: Spacing.one,
    },
    offlineDivider: {
      height: 24,
      borderLeftWidth: 1,
      borderLeftColor: theme.textMuted,
      borderStyle: 'dotted',
    },
    offlineTitle: {
      fontSize: 16,
      lineHeight: 22,
      fontWeight: '700',
      textAlign: 'center',
    },
    offlineSubtitle: {
      fontSize: 14,
      lineHeight: 20,
      color: theme.textSecondary,
      textAlign: 'center',
    },
    retryButton: {
      marginTop: Spacing.one,
      minHeight: 46,
      borderRadius: Radius.md,
      paddingHorizontal: Spacing.four,
      alignItems: 'center',
      justifyContent: 'center',
      alignSelf: 'stretch',
    },
    retryButtonText: {
      color: '#FFFFFF',
      fontWeight: '700',
      fontSize: 15,
    },
  });
}
