import { router, useLocalSearchParams } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import {
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  useWindowDimensions,
  View,
} from 'react-native';

import { PosterCard } from '@/components/cards/poster-card';
import { AppStatusEmptyState } from '@/components/app-status-empty-state';
import { ThemedView } from '@/components/themed-view';
import { useCategoryScreenData } from '@/hooks/use-category-screen-data';
import { useTheme } from '@/hooks/use-theme';
import { getOfflineModeSnapshot, subscribeOfflineMode } from '@/lib/offline-mode';
import { setRouteHasCache } from '@/lib/screen-cache-state';
import { categoryScreenStyles } from '@/styles/category-screen.styles';
import { PopularMovie } from '@/types/api';

const CARD_MIN_WIDTH = 150;
const CARD_GAP = 16;
const INITIAL_SKELETONS = 10;

type GridItem =
  | { kind: 'item'; value: PopularMovie }
  | { kind: 'skeleton'; id: string };

export default function CategoryScreen() {
  const { width } = useWindowDimensions();
  const theme = useTheme();
  const params = useLocalSearchParams<{ kind?: string }>();
  const kindParam = params.kind;
  const kind =
    kindParam === 'popular' || kindParam === 'top-films' || kindParam === 'top-series'
      ? kindParam
      : 'popular';

  const columns = Math.max(
    1,
    Math.floor((Math.max(width - 32, CARD_MIN_WIDTH) + CARD_GAP) / (CARD_MIN_WIDTH + CARD_GAP)),
  );

  const cardWidth = useMemo(() => {
    const contentWidth = Math.max(width - 32, CARD_MIN_WIDTH);
    const totalGaps = CARD_GAP * Math.max(columns - 1, 0);
    return Math.floor((contentWidth - totalGaps) / columns);
  }, [columns, width]);

  const dynamicStyles = useMemo(
    () =>
      StyleSheet.create({
        gridItem: {
          width: cardWidth,
          maxWidth: cardWidth,
          flexGrow: 0,
          flexShrink: 0,
          flexBasis: cardWidth,
          alignSelf: 'flex-start',
        },
      }),
    [cardWidth],
  );

  const { loading, items, hasNextPage, loadNextPage, refresh } =
    useCategoryScreenData(kind);
  const [offlineEnabled, setOfflineEnabled] = useState(getOfflineModeSnapshot().enabled);

  const [refreshing, setRefreshing] = useState(false);

  useEffect(() => subscribeOfflineMode((next) => setOfflineEnabled(next.enabled)), []);
  useEffect(() => {
    setRouteHasCache('category', items.length > 0);
  }, [items.length]);

  // Скелетоны только при первом пустом экране
  const gridData = useMemo<GridItem[]>(() => {
    if (loading && items.length === 0) {
      return Array.from({ length: INITIAL_SKELETONS }, (_, index) => ({
        kind: 'skeleton',
        id: `skeleton-${index}`,
      }));
    }
    return items.map((value) => ({ kind: 'item', value }));
  }, [items, loading]);

  const onRefresh = async () => {
    setRefreshing(true);
    try {
      await refresh();
    } finally {
      setRefreshing(false);
    }
  };

  if (!loading && offlineEnabled && items.length === 0) {
    return (
      <ThemedView style={categoryScreenStyles.container}>
        <View style={[categoryScreenStyles.listContent, { justifyContent: 'center', flex: 1 }]}>
          <AppStatusEmptyState />
        </View>
      </ThemedView>
    );
  }

  return (
    <ThemedView style={categoryScreenStyles.container}>
      <FlatList
        key={`category-grid-${kind}-${columns}`}
        data={gridData}
        keyExtractor={(item) => (item.kind === 'item' ? item.value.id : item.id)}
        numColumns={columns}
        contentContainerStyle={categoryScreenStyles.listContent}
        columnWrapperStyle={columns > 1 ? categoryScreenStyles.row : undefined}
        showsVerticalScrollIndicator={false}
        estimatedItemSize={260}
        refreshControl={
          <RefreshControl
            refreshing={refreshing}
            onRefresh={onRefresh}
            tintColor={theme.accent}
          />
        }
        onEndReachedThreshold={0.45}
        onEndReached={() => {
          if (items.length > 0 && hasNextPage) {
            void loadNextPage();
          }
        }}
        renderItem={({ item }) => {
          if (item.kind === 'skeleton') {
            return (
              <View style={[categoryScreenStyles.gridItem, dynamicStyles.gridItem]}>
                <ThemedView
                  type="backgroundSelected"
                  style={categoryScreenStyles.skeleton}
                />
              </View>
            );
          }
          return (
            <View style={[categoryScreenStyles.gridItem, dynamicStyles.gridItem]}>
              <Pressable
                onPress={() =>
                  router.push({
                    pathname: '/media/[id]',
                    params: { id: item.value.id, title: item.value.title },
                  })
                }>
                <PosterCard item={item.value} fluid />
              </Pressable>
            </View>
          );
        }}
      />
    </ThemedView>
  );
}
