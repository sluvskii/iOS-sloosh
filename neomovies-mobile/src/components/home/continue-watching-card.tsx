import { LinearGradient } from 'expo-linear-gradient';
import { View } from 'react-native';

import { MediaImage } from '@/components/cards/media-image';
import { ThemedText } from '@/components/themed-text';
import { ContinueWatchingItem } from '@/hooks/use-continue-watching';
import { resolveBackdropPageUrl, resolveBackdropUrl, resolveEpisodeStillUrl } from '@/lib/neomovies-api';
import { continueWatchingCardStyles as styles } from './continue-watching-card.styles';

type Props = {
  item: ContinueWatchingItem;
  title: string;
  subtitle: string;
  nextUpLabel?: string;
};

export function ContinueWatchingCard({ item, title, subtitle, nextUpLabel }: Props) {
  const isNextUp = item.kind === 'next_up';

  const imageUri =
    item.kind === 'movie'
      ? resolveBackdropPageUrl(item.mediaId, 'small')
      : resolveEpisodeStillUrl(item.mediaId, item.season ?? undefined, item.episode ?? undefined, 'small');

  const fallbackUri =
    item.kind === 'movie'
      ? resolveBackdropUrl(item.mediaId, 'small')
      : resolveBackdropPageUrl(item.mediaId, 'small');

  return (
    <View style={styles.container}>
      <MediaImage
        primaryUri={imageUri}
        fallbackUris={[fallbackUri]}
        style={styles.image}
        imageKey={`${item.mediaId}-${item.season}-${item.episode}`}
      />
      <View style={styles.shadeTop} />
      <LinearGradient
        colors={['transparent', 'rgba(4, 7, 13, 0.7)', 'rgba(4, 7, 13, 0.88)']}
        style={styles.shadeBottom}
      />
      <View style={styles.overlay}>
        {isNextUp && nextUpLabel ? (
          <View style={styles.nextUpBadge}>
            <ThemedText style={styles.nextUpText}>{nextUpLabel}</ThemedText>
          </View>
        ) : null}
        <ThemedText numberOfLines={1} style={styles.title}>{title}</ThemedText>
        <ThemedText numberOfLines={1} style={styles.subtitle}>{subtitle}</ThemedText>
        {!isNextUp && item.progressPercent > 0 ? (
          <View style={styles.progressTrack}>
            <View style={[styles.progressFill, { width: `${Math.min(item.progressPercent, 100)}%` }]} />
          </View>
        ) : null}
      </View>
    </View>
  );
}
