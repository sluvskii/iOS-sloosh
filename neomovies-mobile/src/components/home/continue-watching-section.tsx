import { router } from 'expo-router';
import { Pressable, View } from 'react-native';
import { FlashList } from '@shopify/flash-list';
import { useEffect, useState } from 'react';

import { ContinueWatchingCard } from '@/components/home/continue-watching-card';
import { ThemedText } from '@/components/themed-text';
import { ContinueWatchingItem } from '@/hooks/use-continue-watching';
import { getMediaDetails } from '@/lib/neomovies-api';
import { MediaDetails } from '@/types/api';
import { mediaCarouselSectionStyles } from './media-carousel-section.styles';
import { Spacing } from '@/constants/theme';

type Props = {
  items: ContinueWatchingItem[];
  title: string;
  nextUpLabel: string;
};

const detailsCache = new Map<string, MediaDetails>();

function useMediaTitle(mediaId: string): string | null {
  const [details, setDetails] = useState<MediaDetails | null>(() => detailsCache.get(mediaId) ?? null);
  useEffect(() => {
    if (detailsCache.has(mediaId)) return;
    let cancelled = false;
    getMediaDetails(mediaId).then((d) => {
      if (cancelled) return;
      detailsCache.set(mediaId, d);
      setDetails(d);
    }).catch(() => {});
    return () => { cancelled = true; };
  }, [mediaId]);
  return details?.title ?? null;
}

function ContinueWatchingCardWrapper({ item, nextUpLabel }: { item: ContinueWatchingItem; nextUpLabel: string }) {
  const title = useMediaTitle(item.mediaId);

  const subtitle =
    item.kind === 'movie'
      ? ''
      : item.season != null && item.episode != null
        ? `S${item.season}:E${item.episode}`
        : '';

  return (
    <Pressable
      onPress={() =>
        router.push({ pathname: '/media/[id]', params: { id: item.mediaId, title: title ?? '' } })
      }>
      <ContinueWatchingCard
        item={item}
        title={title ?? ''}
        subtitle={subtitle}
        nextUpLabel={item.kind === 'next_up' ? nextUpLabel : undefined}
      />
    </Pressable>
  );
}

const HorizontalSpacer = () => <View style={{ width: Spacing.four }} />;

export function ContinueWatchingSection({ items, title, nextUpLabel }: Props) {
  return (
    <View style={mediaCarouselSectionStyles.sectionWrap}>
      <View style={mediaCarouselSectionStyles.headerRow}>
        <ThemedText style={mediaCarouselSectionStyles.sectionTitle}>{title}</ThemedText>
      </View>
      <FlashList
        horizontal
        showsHorizontalScrollIndicator={false}
        data={items}
        estimatedItemSize={240}
        drawDistance={240 * 4}
        disableHorizontalListHeightMeasurement
        removeClippedSubviews={false}
        style={{ height: 135 }}
        ListHeaderComponent={HorizontalSpacer}
        ListFooterComponent={HorizontalSpacer}
        ItemSeparatorComponent={() => <View style={mediaCarouselSectionStyles.rowSeparator} />}
        keyExtractor={(item) => `${item.mediaId}-${item.kind}-${item.season}-${item.episode}`}
        renderItem={({ item }) => (
          <ContinueWatchingCardWrapper item={item} nextUpLabel={nextUpLabel} />
        )}
      />
    </View>
  );
}
