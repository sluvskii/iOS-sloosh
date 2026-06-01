import { useLocalSearchParams } from 'expo-router';
import { ActivityIndicator, StyleSheet } from 'react-native';

import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useWatchPlayerLaunch } from '@/hooks/use-watch-player-launch';
import { useWatchPlayerParams, WatchPlayerRouteParams } from '@/hooks/use-watch-player-params';

export default function WatchPlayerScreen() {
  const params = useLocalSearchParams<WatchPlayerRouteParams>();
  const { mediaId, title, initialSeason, initialEpisode } = useWatchPlayerParams(params);
  const { loading, error } = useWatchPlayerLaunch({
    mediaId,
    title,
    initialSeason,
    initialEpisode,
  });

  return (
    <ThemedView style={styles.container}>
      {loading ? (
        <ActivityIndicator size="large" />
      ) : error ? (
        <ThemedText style={styles.errorText}>{error}</ThemedText>
      ) : null}
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  errorText: {
    color: 'red',
    padding: 20,
    textAlign: 'center',
  },
});
