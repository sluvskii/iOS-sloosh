import { router } from 'expo-router';
import { Heart } from 'lucide-react-native';
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
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useFavoritesScreen } from '@/hooks/use-favorites-screen';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { getOfflineModeSnapshot, subscribeOfflineMode } from '@/lib/offline-mode';
import { setRouteHasCache } from '@/lib/screen-cache-state';
import { categoryScreenStyles } from '@/styles/category-screen.styles';
import { createFavoritesScreenStyles } from '@/styles/favorites-screen.styles';
import { PopularMovie } from '@/types/api';

const CARD_MIN_WIDTH = 150;
const CARD_GAP = 16;
const INITIAL_SKELETONS = 10;

type GridItem =
  | { kind: 'item'; value: PopularMovie }
  | { kind: 'skeleton'; id: string };

export default function FavoritesScreen() {
  const { width } = useWindowDimensions();
  const theme = useTheme();
  const { copy } = useI18n();
  const styles = createFavoritesScreenStyles(theme);
  const { loading, error, movies, isAuthenticated, refresh } = useFavoritesScreen();
  const [refreshing, setRefreshing] = useState(false);
  const [offlineEnabled, setOfflineEnabled] = useState(getOfflineModeSnapshot().enabled);

  useEffect(() => subscribeOfflineMode((next) => setOfflineEnabled(next.enabled)), []);
  useEffect(() => {
    setRouteHasCache('favorites', movies.length > 0);
  }, [movies.length]);

  const columns = Math.max(
    1,
    Math.floor((Math.max(width - 32, CARD_MIN_WIDTH) + CARD_GAP) / (CARD_MIN_WIDTH + CARD_GAP))
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
    [cardWidth]
  );

  const gridData = useMemo<GridItem[]>(() => {
    if (loading && movies.length === 0) {
      return Array.from({ length: INITIAL_SKELETONS }, (_, index) => ({
        kind: 'skeleton',
        id: `skeleton-${index}`,
      }));
    }
    return movies.map((value) => ({ kind: 'item', value }));
  }, [loading, movies]);

  const onRefresh = async () => {
    setRefreshing(true);
    try {
      await refresh();
    } finally {
      setRefreshing(false);
    }
  };

  if (!loading && offlineEnabled && movies.length === 0) {
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
        key={`favorites-grid-${columns}`}
        data={gridData}
        keyExtractor={(item) => (item.kind === 'item' ? item.value.id : item.id)}
        numColumns={columns}
        contentContainerStyle={categoryScreenStyles.listContent}
        columnWrapperStyle={columns > 1 ? categoryScreenStyles.row : undefined}
        showsVerticalScrollIndicator={false}
        estimatedItemSize={260}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={theme.accent} />
        }
        renderItem={({ item }) => {
          if (item.kind === 'skeleton') {
            return (
              <View style={[categoryScreenStyles.gridItem, dynamicStyles.gridItem]}>
                <ThemedView type="backgroundSelected" style={categoryScreenStyles.skeleton} />
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
        ListEmptyComponent={
          !loading ? (
            <View style={styles.emptyWrap}>
              <View style={styles.emptyIconWrap}>
                <Heart size={24} strokeWidth={2.2} color={theme.textSecondary} />
              </View>
              {error ? (
                <ThemedText type="small" themeColor="danger" style={styles.emptyText}>
                  {copy.search.loadError}: {error}
                </ThemedText>
              ) : isAuthenticated ? (
                <ThemedText type="small" themeColor="textSecondary" style={styles.emptyText}>
                  {copy.favorites.empty}
                </ThemedText>
              ) : null}
              {!error && !isAuthenticated ? (
                <View style={styles.authLine}>
                  <Pressable onPress={() => router.push('/profile')}>
                    <ThemedText style={styles.authActionText}>{copy.favorites.authAction}</ThemedText>
                  </Pressable>
                  <ThemedText style={styles.authSuffixText}>
                    {copy.favorites.authRequiredSuffix}
                  </ThemedText>
                </View>
              ) : null}
            </View>
          ) : null
        }
      />
    </ThemedView>
  );
}
