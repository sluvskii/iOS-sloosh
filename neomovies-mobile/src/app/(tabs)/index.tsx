import { useEffect, useState } from 'react';
import { Pressable, RefreshControl, View } from 'react-native';
import { router } from 'expo-router';
import { Search } from 'lucide-react-native';
import { FlashList } from '@shopify/flash-list';

import { AppStatusEmptyState } from '@/components/app-status-empty-state';
import { ContinueWatchingSection } from '@/components/home/continue-watching-section';
import { MediaCarouselSection } from '@/components/home/media-carousel-section';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useContinueWatching } from '@/hooks/use-continue-watching';
import { useHomeScreenData } from '@/hooks/use-home-screen-data';
import { useTheme } from '@/hooks/use-theme';
import { useI18n } from '@/i18n';
import { getOfflineModeSnapshot, subscribeOfflineMode } from '@/lib/offline-mode';
import { setRouteHasCache } from '@/lib/screen-cache-state';
import { homeScreenStyles } from '@/styles/home-screen.styles';

export default function HomeScreen() {
  const { copy } = useI18n();
  const theme = useTheme();
  const { loading, error, popular, topFilms, topSeries, refresh } = useHomeScreenData();
  const continueWatching = useContinueWatching();
  const [refreshing, setRefreshing] = useState(false);
  const [offlineEnabled, setOfflineEnabled] = useState(getOfflineModeSnapshot().enabled);

  useEffect(() => subscribeOfflineMode((next) => setOfflineEnabled(next.enabled)), []);

  const hasCachedData = popular.length > 0 || topFilms.length > 0 || topSeries.length > 0;

  useEffect(() => {
    setRouteHasCache('home', hasCachedData);
  }, [hasCachedData]);
  if (!loading && offlineEnabled && !hasCachedData) {
    return (
      <ThemedView style={homeScreenStyles.container}>
        <View style={[homeScreenStyles.content, { justifyContent: 'center', flex: 1 }]}>
          <AppStatusEmptyState />
        </View>
      </ThemedView>
    );
  }

  const onRefresh = async () => {
    setRefreshing(true);
    try {
      await refresh();
    } finally {
      setRefreshing(false);
    }
  };

  return (
    <ThemedView style={homeScreenStyles.container}>
      <FlashList
        data={[{ id: 'home' }]}
        keyExtractor={(item) => item.id}
        renderItem={() => (
          <View style={homeScreenStyles.content}>
            <Pressable onPress={() => router.push('/explore')}>
              <ThemedView type="backgroundElement" style={homeScreenStyles.searchRow}>
                <Search size={18} color={theme.textMuted} />
                <ThemedText type="small" themeColor="textMuted">
                  {copy.search.placeholder}
                </ThemedText>
              </ThemedView>
            </Pressable>

            {continueWatching.length > 0 ? (
              <ContinueWatchingSection
                items={continueWatching}
                title={copy.home.continueWatching}
                nextUpLabel={copy.home.nextUp}
              />
            ) : null}

            <MediaCarouselSection
              title={copy.home.popular}
              items={popular}
              categoryKind="popular"
              variant="backdrop"
              loading={loading}
            />
            <MediaCarouselSection
              title={copy.home.topFilms}
              items={topFilms}
              categoryKind="top-films"
              variant="poster"
              loading={loading}
            />
            <MediaCarouselSection
              title={copy.home.topSeries}
              items={topSeries}
              categoryKind="top-series"
              variant="poster"
              loading={loading}
            />

            {error ? (
              <ThemedView
                type="backgroundElement"
                style={[homeScreenStyles.errorCard, { borderColor: theme.danger }]}>
                <ThemedText type="small" themeColor="danger">
                  {copy.home.loadError}: {error}
                </ThemedText>
              </ThemedView>
            ) : null}
          </View>
        )}
        estimatedItemSize={800}
        showsVerticalScrollIndicator={false}
        refreshControl={
          <RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={theme.accent} />
        }
      />
    </ThemedView>
  );
}

