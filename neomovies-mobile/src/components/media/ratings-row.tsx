import { memo, useMemo } from 'react';
import { StyleSheet, View } from 'react-native';

import { ThemedText } from '@/components/themed-text';

type ThemePalette = {
  text: string;
  textSecondary: string;
  border: string;
  backgroundElement: string;
};

type RatingsRowProps = {
  theme: ThemePalette;
  kp?: number | null;
  tmdb?: number | null;
  imdb?: number | null;
  compact?: boolean;
};

function formatRating(value?: number | null) {
  if (typeof value !== 'number' || Number.isNaN(value) || value <= 0) return '--';
  return value.toFixed(1);
}

export const RatingsRow = memo(function RatingsRow({ theme, kp, tmdb, imdb, compact = false }: RatingsRowProps) {
  const styles = useMemo(() => createStyles(theme, compact), [theme, compact]);
  const hasKp = typeof kp === 'number' && !Number.isNaN(kp) && kp > 0;
  const hasTmdb = typeof tmdb === 'number' && !Number.isNaN(tmdb) && tmdb > 0;
  const hasImdb = typeof imdb === 'number' && !Number.isNaN(imdb) && imdb > 0;

  return (
    <View style={styles.row}>
      {hasKp ? (
        <View style={styles.badge}>
          <View style={[styles.logoTextWrap, styles.kpLogo]}>
            <ThemedText style={styles.logoText}>KP</ThemedText>
          </View>
          <ThemedText style={styles.value}>{formatRating(kp)}</ThemedText>
        </View>
      ) : null}

      {hasTmdb ? (
        <View style={styles.badge}>
          <View style={[styles.logoTextWrap, styles.tmdbLogo]}>
            <ThemedText style={styles.logoTextSmall}>TMDB</ThemedText>
          </View>
          <ThemedText style={styles.value}>{formatRating(tmdb)}</ThemedText>
        </View>
      ) : null}

      {hasImdb ? (
        <View style={styles.badge}>
          <View style={[styles.logoTextWrap, styles.imdbLogo]}>
            <ThemedText style={styles.logoTextSmall}>IMDb</ThemedText>
          </View>
          <ThemedText style={styles.value}>{formatRating(imdb)}</ThemedText>
        </View>
      ) : null}
    </View>
  );
});

function createStyles(theme: ThemePalette, compact: boolean) {
  return StyleSheet.create({
    row: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 8,
      flexWrap: 'wrap',
    },
    badge: {
      flexDirection: 'row',
      alignItems: 'center',
      gap: 6,
      borderWidth: 1,
      borderColor: theme.border,
      backgroundColor: theme.backgroundElement,
      borderRadius: 999,
      paddingVertical: compact ? 4 : 5,
      paddingHorizontal: compact ? 8 : 10,
    },
    value: {
      fontWeight: '700',
      fontSize: compact ? 11 : 12,
      lineHeight: compact ? 14 : 16,
      color: theme.text,
    },
    logoTextWrap: {
      borderRadius: 4,
      paddingHorizontal: 4,
      paddingVertical: 1,
    },
    kpLogo: {
      backgroundColor: '#FF6A00',
    },
    tmdbLogo: {
      backgroundColor: '#01D277',
    },
    imdbLogo: {
      backgroundColor: '#F5C518',
    },
    logoText: {
      color: '#FFFFFF',
      fontWeight: '800',
      fontSize: compact ? 9 : 10,
      lineHeight: compact ? 11 : 12,
    },
    logoTextSmall: {
      color: '#002A1E',
      fontWeight: '800',
      fontSize: compact ? 8 : 9,
      lineHeight: compact ? 10 : 11,
    },
  });
}
