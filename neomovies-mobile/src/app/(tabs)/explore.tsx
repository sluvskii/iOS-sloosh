import { router } from 'expo-router';
import { useEffect, useMemo, useState } from 'react';
import {
  FlatList,
  Pressable,
  RefreshControl,
  StyleSheet,
  TextInput,
  useWindowDimensions,
  View,
} from 'react-native';
import { Clock3, Search, X } from 'lucide-react-native';

import { AppStatusEmptyState } from '@/components/app-status-empty-state';
import { PosterCard } from '@/components/cards/poster-card';
import { Spacing } from '@/constants/theme';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useSearchScreen } from '@/hooks/use-search-screen';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { getOfflineModeSnapshot, subscribeOfflineMode } from '@/lib/offline-mode';
import { setRouteHasCache } from '@/lib/screen-cache-state';
import { createSearchScreenStyles } from '@/styles/search-screen.styles';
import { SearchResultItem } from '@/types/api';

type GridItem = { kind: 'result'; value: SearchResultItem } | { kind: 'skeleton'; id: string };

export default function SearchScreen() {
  const { copy } = useI18n();
  const theme = useTheme();
  const { width } = useWindowDimensions();
  const contentPaddingHorizontal = Spacing.four;
  const searchCardGap = Spacing.three;
  const minCardWidth = 140;
  const columns = Math.max(
    1,
    Math.floor(
      (Math.max(width - contentPaddingHorizontal * 2, minCardWidth) + searchCardGap) /
        (minCardWidth + searchCardGap)
    )
  );
  const styles = createSearchScreenStyles(theme);
  const {
    query,
    setQuery,
    loading,
    error,
    results,
    recentQueries,
    hasNextPage,
    removeRecentQuery,
    runSearch,
    loadNextPage,
    refresh,
    trackCurrentQuery,
  } = useSearchScreen();
  const [refreshing, setRefreshing] = useState(false);
  const [offlineEnabled, setOfflineEnabled] = useState(getOfflineModeSnapshot().enabled);

  useEffect(() => {
    const unsubscribe = subscribeOfflineMode((next) => setOfflineEnabled(next.enabled));
    return unsubscribe;
  }, []);

  useEffect(() => {
    setRouteHasCache('explore', results.length > 0);
  }, [results.length]);

  const cardWidth = useMemo(() => {
    const contentWidth = Math.max(width - contentPaddingHorizontal * 2, minCardWidth);
    const totalGaps = searchCardGap * Math.max(columns - 1, 0);
    return Math.floor((contentWidth - totalGaps) / columns);
  }, [columns, contentPaddingHorizontal, minCardWidth, searchCardGap, width]);

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
        gridItemSpacing: {
          marginBottom: searchCardGap,
        },
      }),
    [cardWidth, searchCardGap]
  );

  const skeletonItems = useMemo<GridItem[]>(
    () =>
      Array.from({ length: Math.max(columns * 3, 9) }, (_, index) => ({
        kind: 'skeleton',
        id: `s-${index}`,
      })),
    [columns]
  );
  const gridData = useMemo<GridItem[]>(() => {
    if (loading && results.length === 0) {
      return skeletonItems;
    }
    return results.map((value) => ({ kind: 'result', value }));
  }, [loading, results, skeletonItems]);

  const renderGridItem = ({ item, index }: { item: GridItem; index: number }) => {
    const isLastColumn = columns > 1 && (index + 1) % columns === 0;
    const spacingStyle = [
      dynamicStyles.gridItemSpacing,
      !isLastColumn ? { marginRight: searchCardGap } : null,
    ];
    if (item.kind === 'skeleton') {
      return (
        <View style={[styles.gridItem, dynamicStyles.gridItem, spacingStyle]}>
          <ThemedView type="backgroundSelected" style={styles.gridSkeleton} />
        </View>
      );
    }
    return (
      <View style={[styles.gridItem, dynamicStyles.gridItem, spacingStyle]}>
        <Pressable
          onPress={() => {
            void trackCurrentQuery();
            router.push({
              pathname: '/media/[id]',
              params: { id: item.value.id, title: item.value.title },
            });
          }}>
          <PosterCard item={item.value} fluid />
        </Pressable>
      </View>
    );
  };

  const onRefresh = async () => {
    setRefreshing(true);
    try {
      await refresh();
    } finally {
      setRefreshing(false);
    }
  };

  if (!loading && offlineEnabled && results.length === 0) {
    return (
      <ThemedView style={styles.container}>
        <View style={[styles.content, { justifyContent: 'center', flex: 1, paddingHorizontal: 16 }]}>
          <AppStatusEmptyState />
        </View>
      </ThemedView>
    );
  }

  return (
    <ThemedView style={styles.container}>
      <FlatList
        key={`search-grid-${columns}`}
        data={gridData}
        keyExtractor={(item) => (item.kind === 'result' ? item.value.id : item.id)}
        renderItem={renderGridItem}
        numColumns={columns}
        style={styles.resultsGrid}
        columnWrapperStyle={columns > 1 ? styles.rowGap : undefined}
        contentContainerStyle={styles.listContent}
        keyboardShouldPersistTaps="handled"
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={theme.accent} />
        }
        onEndReachedThreshold={0.45}
        onEndReached={() => {
          if (results.length > 0 && hasNextPage) {
            void loadNextPage();
          }
        }}
        ListHeaderComponent={
          <View style={styles.content}>
            <View style={styles.searchRow}>
              <TextInput
                value={query}
                onChangeText={setQuery}
                style={styles.input}
                placeholder={copy.search.placeholder}
                placeholderTextColor={theme.textSecondary}
                autoCapitalize="none"
                returnKeyType="search"
                onSubmitEditing={() => runSearch()}
              />
              <Pressable style={styles.searchAction} onPress={() => runSearch()} disabled={loading}>
                <Search size={19} strokeWidth={2.3} color={theme.accent} />
              </Pressable>
            </View>

            {recentQueries.length > 0 ? (
              <View style={styles.recentBlock}>
                <ThemedText style={styles.recentTitle} themeColor="textSecondary">
                  {copy.search.recentTitle}
                </ThemedText>
                <FlatList
                  horizontal
                  showsHorizontalScrollIndicator={false}
                  data={recentQueries}
                  keyExtractor={(item) => item}
                  contentContainerStyle={styles.recentRow}
                  ItemSeparatorComponent={() => <View style={styles.recentItemSeparator} />}
                  renderItem={({ item }) => (
                    <View style={styles.recentChip}>
                      <View style={styles.recentChipIconWrap}>
                        <Clock3 size={13} strokeWidth={2.2} color={theme.textSecondary} />
                      </View>
                      <Pressable style={styles.recentChipMain} onPress={() => runSearch(item)}>
                        <ThemedText type="small" numberOfLines={1} style={styles.recentChipText}>
                          {item}
                        </ThemedText>
                      </Pressable>
                      <Pressable style={styles.recentChipRemove} onPress={() => removeRecentQuery(item)}>
                        <X size={14} strokeWidth={2.4} color={theme.textSecondary} />
                      </Pressable>
                    </View>
                  )}
                />
              </View>
            ) : null}

            {error && !offlineEnabled ? (
              <ThemedText type="small" themeColor="danger">
                {copy.search.loadError}: {error}
              </ThemedText>
            ) : null}

          </View>
        }
        ListEmptyComponent={
          !loading && !offlineEnabled ? (
            <ThemedText style={styles.emptyState}>{copy.search.emptyState}</ThemedText>
          ) : null
        }
        ListFooterComponent={null}
      />
    </ThemedView>
  );
}
