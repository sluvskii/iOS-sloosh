import { View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';

import { MediaImage } from '@/components/cards/media-image';
import { ThemedText } from '@/components/themed-text';
import { resolvePosterUrl } from '@/lib/neomovies-api';
import { PopularMovie, SearchResultItem } from '@/types/api';
import { posterCardStyles } from '@/components/cards/poster-card.styles';

type PosterCardItem = PopularMovie | SearchResultItem;

type PosterCardProps = {
  item: PosterCardItem;
  fluid?: boolean;
  mediaLabel?: string;
};

export function PosterCard({ item, fluid = false, mediaLabel }: PosterCardProps) {
  const posterUri = resolvePosterUrl(item.posterUrl);
  const rating = item.rating != null ? item.rating.toFixed(1) : '--';

  return (
    <View style={fluid ? posterCardStyles.fluidContainer : posterCardStyles.container}>
      <MediaImage
        primaryUri={posterUri}
        fallbackUris={[]}
        style={posterCardStyles.image}
        imageKey={item.id}
      />
      <View style={posterCardStyles.shadeTop} />
      <LinearGradient
        colors={['transparent', 'rgba(4, 7, 13, 0.62)', 'rgba(4, 7, 13, 0.82)']}
        style={posterCardStyles.shadeBottom}
      />

      <View style={posterCardStyles.gradientOverlay}>
        <View style={posterCardStyles.bottomRow}>
          <ThemedText numberOfLines={mediaLabel ? 1 : 2} style={posterCardStyles.title}>
            {item.title}
          </ThemedText>
          {mediaLabel ? (
            <ThemedText numberOfLines={1} style={posterCardStyles.metaText}>
              {mediaLabel}
            </ThemedText>
          ) : null}
          <View style={posterCardStyles.ratingPill}>
            <ThemedText style={posterCardStyles.ratingText}>★</ThemedText>
            <ThemedText style={posterCardStyles.ratingText}>{rating}</ThemedText>
          </View>
        </View>
      </View>
    </View>
  );
}
