import { router } from 'expo-router';
import { ChevronRight } from 'lucide-react-native';
import { Pressable, ScrollView, View } from 'react-native';

import { BackdropCard } from '@/components/cards/backdrop-card';
import { PosterCard } from '@/components/cards/poster-card';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { mediaCarouselSectionStyles } from '@/components/home/media-carousel-section.styles';
import { useTheme } from '@/hooks/use-theme';
import { Spacing } from '@/constants/theme';
import { PopularMovie } from '@/types/api';

type MediaCarouselSectionProps = {
  title: string;
  items: PopularMovie[];
  categoryKind: 'popular' | 'top-films' | 'top-series';
  variant?: 'poster' | 'backdrop';
  loading?: boolean;
};

export function MediaCarouselSection({
  title,
  items,
  categoryKind,
  variant = 'poster',
  loading = false,
}: MediaCarouselSectionProps) {
  const theme = useTheme();
  const CardComponent = variant === 'backdrop' ? BackdropCard : PosterCard;

  const skeletonStyle =
    variant === 'backdrop'
      ? mediaCarouselSectionStyles.skeletonBackdrop
      : mediaCarouselSectionStyles.skeletonPoster;
  const skeletonCount = variant === 'backdrop' ? 3 : 5;
  const listHeight = variant === 'backdrop' ? 157 : 210;

  const renderItems = loading
    ? Array.from({ length: skeletonCount }, (_, i) => (
        <ThemedView key={`skeleton-${i}`} type="backgroundSelected" style={skeletonStyle} />
      ))
    : items.map((item) => (
        <Pressable
          key={item.id}
          onPress={() => router.push({ pathname: '/media/[id]', params: { id: item.id, title: item.title } })}>
          <CardComponent item={item} />
        </Pressable>
      ));

  return (
    <View style={mediaCarouselSectionStyles.sectionWrap}>
      <View style={mediaCarouselSectionStyles.headerRow}>
        <ThemedText style={mediaCarouselSectionStyles.sectionTitle}>{title}</ThemedText>
        <Pressable
          style={mediaCarouselSectionStyles.headerAction}
          onPress={() => router.push({ pathname: '/category/[kind]', params: { kind: categoryKind, title } })}>
          <ChevronRight size={22} color={theme.textSecondary} strokeWidth={2.6} />
        </Pressable>
      </View>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={{ height: listHeight }}
        contentContainerStyle={{ paddingHorizontal: Spacing.four, gap: Spacing.three }}>
        {renderItems}
      </ScrollView>
    </View>
  );
}

