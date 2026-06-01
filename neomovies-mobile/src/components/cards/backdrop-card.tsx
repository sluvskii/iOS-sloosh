import { View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';

import { MediaImage } from '@/components/cards/media-image';
import { ThemedText } from '@/components/themed-text';
import { resolveBackdropPageUrl, resolveBackdropUrl, resolvePosterUrl } from '@/lib/neomovies-api';
import { PopularMovie } from '@/types/api';
import { backdropCardStyles } from '@/components/cards/backdrop-card.styles';

export function BackdropCard({ item, fluid = false }: { item: PopularMovie; fluid?: boolean }) {
  const backdropUri = resolveBackdropUrl(item.id, 'small');
  const backdropPageUri = resolveBackdropPageUrl(item.id, 'small');
  const posterUri = resolvePosterUrl(item.posterUrl);
  const rating = item.rating != null ? item.rating.toFixed(1) : '--';

  return (
    <View style={fluid ? backdropCardStyles.fluidContainer : backdropCardStyles.container}>
      <MediaImage
        primaryUri={backdropPageUri}
        fallbackUris={[backdropUri, posterUri]}
        style={backdropCardStyles.image}
        imageKey={item.id}
      />
      <View style={backdropCardStyles.shadeTop} />
      <LinearGradient
        colors={['transparent', 'rgba(4, 7, 13, 0.62)', 'rgba(4, 7, 13, 0.82)']}
        style={backdropCardStyles.shadeBottom}
      />
      <View style={backdropCardStyles.overlay}>
        <View style={backdropCardStyles.row}>
          <ThemedText numberOfLines={1} style={backdropCardStyles.title}>
            {item.title}
          </ThemedText>
          <View style={backdropCardStyles.ratingPill}>
            <ThemedText style={backdropCardStyles.ratingText}>★</ThemedText>
            <ThemedText style={backdropCardStyles.ratingText}>{rating}</ThemedText>
          </View>
        </View>
      </View>
    </View>
  );
}
