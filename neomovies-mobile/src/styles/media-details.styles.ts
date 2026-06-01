import { StyleSheet } from 'react-native';

import { Radius, Spacing } from '@/constants/theme';

type ThemePalette = {
  accent: string;
  accentMuted: string;
  backgroundElement: string;
  border: string;
  text: string;
  textSecondary: string;
};

export function createMediaDetailsStyles(theme: ThemePalette) {
  return StyleSheet.create({
    container: { flex: 1 },
    content: {
      paddingHorizontal: Spacing.three,
      paddingBottom: 110,
      gap: Spacing.three,
    },
    flashListContent: {
      paddingHorizontal: Spacing.three,
      paddingBottom: 110,
    },
    flashListHeader: {
      gap: Spacing.three,
      paddingTop: Spacing.three,
      paddingBottom: Spacing.three,
    },
    heroCard: {
      borderRadius: Radius.lg,
      overflow: 'hidden',
      backgroundColor: theme.backgroundElement,
      borderWidth: 1,
      borderColor: theme.border,
      minHeight: 230,
    },
    heroImage: {
      width: '100%',
      height: 230,
    },
    logoWrap: {
      position: 'absolute',
      left: Spacing.three,
      right: Spacing.three,
      bottom: Spacing.three,
      alignItems: 'flex-start',
      justifyContent: 'flex-end',
    },
    logo: {
      width: 190,
      height: 62,
    },
    logoHidden: {
      opacity: 0,
    },
    title: {
      fontSize: 28,
      lineHeight: 34,
      fontWeight: '700',
    },
    metaRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: Spacing.two,
    },
    metaItem: {
      fontSize: 14,
      lineHeight: 20,
      color: theme.textSecondary,
    },
    genresRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: Spacing.one,
    },
    genreChip: {
      borderWidth: 1,
      borderColor: theme.border,
      backgroundColor: theme.backgroundElement,
      borderRadius: 999,
      paddingHorizontal: Spacing.two,
      paddingVertical: Spacing.one,
    },
    genreText: {
      fontSize: 12,
      lineHeight: 16,
      color: theme.textSecondary,
      fontWeight: '600',
    },
    description: {
      fontSize: 15,
      lineHeight: 22,
      color: theme.textSecondary,
    },
    sectionTitle: {
      fontSize: 20,
      lineHeight: 26,
      fontWeight: '700',
    },
    actionsRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.two,
    },
    watchButton: {
      flex: 1,
      minHeight: 48,
      borderRadius: Radius.md,
      backgroundColor: theme.accent,
      alignItems: 'center',
      justifyContent: 'center',
      paddingHorizontal: Spacing.three,
    },
    watchButtonContent: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'center',
      gap: Spacing.one,
    },
    watchButtonText: {
      color: '#FFFFFF',
      fontSize: 16,
      lineHeight: 20,
      fontWeight: '700',
    },
    iconButton: {
      width: 48,
      height: 48,
      borderRadius: Radius.md,
      borderWidth: 1,
      borderColor: theme.border,
      backgroundColor: theme.accentMuted,
      alignItems: 'center',
      justifyContent: 'center',
    },
    seasonSelectorWrapper: {
      position: 'relative',
      marginTop: Spacing.two,
    },
    seasonsHeader: {
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      borderWidth: 1,
      borderColor: theme.border,
      borderRadius: Radius.md,
      backgroundColor: theme.backgroundElement,
      paddingHorizontal: Spacing.three,
      paddingVertical: Spacing.two,
    },
    seasonsHeaderLeft: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: Spacing.one,
    },
    seasonsHeaderLabel: {
      fontSize: 15,
      lineHeight: 20,
      fontWeight: '600',
    },
    seasonMeta: {
      color: theme.textSecondary,
      fontSize: 13,
      lineHeight: 18,
    },
    seasonsRow: {
      flexDirection: 'row',
      flexWrap: 'wrap',
      gap: Spacing.one,
    },
    seasonDropdownList: {
      position: 'absolute',
      top: 60,
      left: 0,
      right: 0,
      zIndex: 1000,
      borderWidth: 1,
      borderColor: theme.border,
      borderRadius: Radius.md,
      backgroundColor: theme.backgroundElement,
      overflow: 'hidden',
      shadowColor: '#000',
      shadowOffset: {
        width: 0,
        height: 4,
      },
      shadowOpacity: 0.3,
      shadowRadius: 8,
      elevation: 8,
    },
    seasonOptionRow: {
      minHeight: 44,
      paddingHorizontal: Spacing.three,
      flexDirection: 'row',
      alignItems: 'center',
      justifyContent: 'space-between',
      borderBottomWidth: 1,
      borderBottomColor: theme.border,
    },
    seasonOptionRowActive: {
      backgroundColor: theme.accentMuted,
    },
    seasonOptionText: {
      fontSize: 14,
      lineHeight: 18,
      fontWeight: '600',
    },
    seasonOptionCheck: {
      color: theme.textSecondary,
      fontSize: 14,
      lineHeight: 18,
      fontWeight: '700',
    },
    seasonPill: {
      borderWidth: 1,
      borderColor: theme.border,
      backgroundColor: theme.backgroundElement,
      borderRadius: 999,
      paddingVertical: Spacing.one,
      paddingHorizontal: Spacing.two,
    },
    seasonPillActive: {
      borderColor: theme.accent,
      backgroundColor: theme.accentMuted,
    },
    seasonPillText: {
      fontSize: 13,
      lineHeight: 18,
      fontWeight: '600',
    },
    episodesList: {
      gap: Spacing.three,
    },
    episodeCard: {
      marginBottom: 0,
    },
    episodeSeparator: {
      height: Spacing.two,
    },
    episodeContent: {
      flexDirection: 'row',
      gap: Spacing.three,
      alignItems: 'flex-start',
    },
    episodeImage: {
      width: 148,
      height: 83,
      borderRadius: Radius.sm,
      backgroundColor: theme.accentMuted,
    },
    episodeImageWrapper: {
      position: 'relative',
      width: 148,
      height: 83,
      borderRadius: Radius.sm,
      overflow: 'hidden',
    },
    episodePlayButton: {
      position: 'absolute',
      top: 6,
      right: 6,
      width: 28,
      height: 28,
      borderRadius: 999,
      backgroundColor: 'rgba(0, 0, 0, 0.6)',
      alignItems: 'center',
      justifyContent: 'center',
    },
    episodeWatchedBadge: {
      position: 'absolute',
      top: 6,
      left: 6,
      backgroundColor: '#21D07A',
      borderRadius: 999,
      width: 20,
      height: 20,
      alignItems: 'center',
      justifyContent: 'center',
    },
    episodeWatchedText: {
      color: '#FFFFFF',
      fontSize: 12,
      lineHeight: 14,
      fontWeight: '700',
    },
    episodeProgressBadge: {
      position: 'absolute',
      top: 6,
      left: 6,
      backgroundColor: 'rgba(0, 0, 0, 0.7)',
      borderRadius: 4,
      paddingHorizontal: 6,
      paddingVertical: 2,
    },
    episodeProgressText: {
      color: '#FFFFFF',
      fontSize: 10,
      lineHeight: 12,
      fontWeight: '700',
    },
    episodeInfo: {
      flex: 1,
      gap: 4,
      paddingTop: 0,
      justifyContent: 'center',
    },
    episodeTitleSkeleton: {
      width: '78%',
      height: 14,
      borderRadius: 6,
      marginBottom: 6,
    },
    episodeMetaSkeleton: {
      width: '48%',
      height: 12,
      borderRadius: 6,
      marginBottom: 8,
    },
    episodeDescriptionSkeleton: {
      width: '92%',
      height: 28,
      borderRadius: 6,
    },
    episodeTitle: {
      fontSize: 15,
      lineHeight: 20,
      fontWeight: '600',
    },
    episodeMeta: {
      color: theme.textSecondary,
      fontSize: 12,
      lineHeight: 16,
    },
    episodeMetaRow: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
    },
    episodeDescription: {
      color: theme.textSecondary,
      fontSize: 13,
      lineHeight: 18,
    },
    episodeActionButton: {
      width: 26,
      height: 26,
      borderRadius: 999,
      borderWidth: 1,
      borderColor: theme.border,
      alignItems: 'center',
      justifyContent: 'center',
    },
    episodeActions: {
      alignItems: 'center',
      gap: 6,
    },
    episodeActionsRail: {
      alignItems: 'flex-start',
      justifyContent: 'flex-start',
      gap: 8,
      paddingTop: 0,
    },
    episodeMoreButton: {
      width: 22,
      height: 22,
      alignItems: 'center',
      justifyContent: 'center',
    },
    episodeProgressTrack: {
      position: 'absolute',
      bottom: 0,
      left: 0,
      right: 0,
      height: 4,
      backgroundColor: 'rgba(255, 255, 255, 0.3)',
    },
    episodeProgressFill: {
      height: 4,
      backgroundColor: '#FFFFFF',
    },
    watchedTag: {
      alignSelf: 'flex-start',
      borderRadius: 999,
      backgroundColor: theme.accentMuted,
      paddingHorizontal: Spacing.one,
      paddingVertical: 2,
    },
    watchedTagText: {
      fontSize: 11,
      lineHeight: 14,
      color: theme.text,
      fontWeight: '700',
    },
    skeleton: {
      borderRadius: Radius.md,
      height: 22,
    },
    skeletonHero: {
      borderRadius: Radius.lg,
      height: 230,
    },
  });
}
