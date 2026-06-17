import { Image } from 'expo-image';
import { Download, Play } from 'lucide-react-native';
import { router, useLocalSearchParams } from 'expo-router';
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Pressable, View } from 'react-native';
import { FlashList } from '@shopify/flash-list';

import { AppStatusEmptyState } from '@/components/app-status-empty-state';
import { MediaImage } from '@/components/cards/media-image';
import { RatingsRow } from '@/components/media/ratings-row';
import { SeriesEpisodesSection } from '@/components/media/series-episodes-section';
import { ThemedText } from '@/components/themed-text';
import { ThemedView } from '@/components/themed-view';
import { useMediaDetails } from '@/hooks/use-media-details';
import { useSeriesDetails } from '@/hooks/use-series-details';
import { useTheme } from '@/hooks/use-theme';
import { useWatchProgress } from '@/hooks/use-watch-progress';
import { useI18n } from '@/i18n';
import { addFavorite, checkFavorite, removeFavorite, resolveEpisodeStillUrl, resolveBackdropUrl, resolveLogoUrl, resolvePosterUrl } from '@/lib/neomovies-api';
import { getStoredTokens } from '@/lib/neoid-auth';
import { resetMediaFavoriteHeader, setMediaFavoriteHeader } from '@/lib/media-favorite-header';
import { setRouteHasCache } from '@/lib/screen-cache-state';
import { createMediaDetailsStyles } from '@/styles/media-details.styles';

export default function MediaDetailsScreen() {
  const params = useLocalSearchParams<{ id?: string }>();
  const theme = useTheme();
  const { copy } = useI18n();
  const styles = createMediaDetailsStyles(theme);
  const mediaId = params.id ?? '';
  const { loading, error, details } = useMediaDetails(mediaId);
  const [readyLogoUri, setReadyLogoUri] = useState<string | null>(null);
  const [logoFailed, setLogoFailed] = useState(false);
  const [isFavorite, setIsFavorite] = useState(false);
  const [favoriteBusy, setFavoriteBusy] = useState(false);
  const [favoriteStatusReady, setFavoriteStatusReady] = useState(false);
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const favoriteCheckVersionRef = useRef(0);

  const backdropUri = useMemo(() => (details ? resolveBackdropUrl(details.id, 'large') : null), [details]);
  const posterUri = useMemo(() => (details ? resolvePosterUrl(details.posterUrl) : null), [details]);
  const logoUri = useMemo(() => (details ? resolveLogoUrl(details.id, 'w500') : null), [details]);

  const {
    seriesCatalog,
    selectedSeasonData,
    setSelectedSeason,
    isSeasonPickerExpanded,
    setSeasonPickerExpanded,
    episodeMetaMap,
    firstEpisode,
    mediaIdNumber,
    canReadProgress,
    seriesProgress,
    seasonProgressMap,
    sortedEpisodes,
  } = useSeriesDetails(details);

  const movieKpId = details?.type === 'movie' && canReadProgress ? mediaIdNumber : null;
  const movieProgress = useWatchProgress(movieKpId);

  useEffect(() => {
    setRouteHasCache('media', Boolean(details));
  }, [details]);

  useEffect(() => {
    let active = true;
    setReadyLogoUri(null);
    setLogoFailed(false);

    if (!logoUri) {
      return () => {
        active = false;
      };
    }

    void Image.prefetch(logoUri, 'memory-disk')
      .then((result) => {
        if (!active || !result) return;
        setReadyLogoUri(logoUri);
      })
      .catch(() => {
        if (!active) return;
        setLogoFailed(true);
      });

    return () => {
      active = false;
    };
  }, [logoUri]);

  useEffect(() => {
    let active = true;
    const checkVersion = favoriteCheckVersionRef.current + 1;
    favoriteCheckVersionRef.current = checkVersion;
    setFavoriteStatusReady(false);
    void (async () => {
      if (!details) return;
      try {
        const tokens = await getStoredTokens();
        if (!tokens?.accessToken) {
          if (!active || checkVersion !== favoriteCheckVersionRef.current) return;
          setIsAuthenticated(false);
          setIsFavorite(false);
          setFavoriteStatusReady(true);
          return;
        }
        setIsAuthenticated(true);
        const result = await checkFavorite(details.id, details.type);
        if (!active || checkVersion !== favoriteCheckVersionRef.current) return;
        setIsFavorite(result.isFavorite === true);
        setFavoriteStatusReady(true);
      } catch {
        if (!active || checkVersion !== favoriteCheckVersionRef.current) return;
        setIsFavorite(false);
        setFavoriteStatusReady(true);
      }
    })();
    return () => {
      active = false;
    };
  }, [details]);

  const watchLabel = useMemo(() => {
    if (!details) return copy.media.watch;
    if (details.type === 'tv') {
      const resumeSeason = seriesProgress?.lastSeason ?? firstEpisode?.season ?? 1;
      const resumeEpisode = seriesProgress?.lastEpisode ?? firstEpisode?.episode ?? 1;
      return `${copy.media.watch} S${resumeSeason} E${resumeEpisode}`;
    }
    if (details.type === 'movie' && movieProgress && movieProgress.positionMs > 0 && !movieProgress.watched) {
      const totalMinutes = Math.floor(movieProgress.positionMs / 1000 / 60);
      const hours = Math.floor(totalMinutes / 60);
      const minutes = totalMinutes % 60;
      return `${copy.media.watch} ${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}`;
    }
    return copy.media.watch;
  }, [copy.media.watch, details, firstEpisode?.episode, firstEpisode?.season, seriesProgress, movieProgress]);

  const handleLogoError = useCallback(() => {
    setLogoFailed(true);
  }, []);

  const onToggleFavorite = useCallback(async () => {
    if (!details || favoriteBusy) return;
    favoriteCheckVersionRef.current += 1;
    setFavoriteBusy(true);
    setFavoriteStatusReady(true);
    const next = !isFavorite;
    setIsFavorite(next);
    try {
      if (next) {
        await addFavorite(details.id, details.type);
      } else {
        await removeFavorite(details.id, details.type);
      }
    } catch {
      setIsFavorite(!next);
    } finally {
      setFavoriteBusy(false);
    }
  }, [details, favoriteBusy, isFavorite]);

  const handleWatchPress = useCallback(() => {
    if (!details) return;
    router.push({
      pathname: '/watch/[id]',
      params: {
        id: details.id,
        title: details.title,
        season: details.type === 'tv' ? String(seriesProgress?.lastSeason ?? firstEpisode?.season ?? 1) : undefined,
        episode: details.type === 'tv' ? String(seriesProgress?.lastEpisode ?? firstEpisode?.episode ?? 1) : undefined,
      },
    });
  }, [details, seriesProgress?.lastSeason, seriesProgress?.lastEpisode, firstEpisode?.season, firstEpisode?.episode]);

  const handleOpenEpisode = useCallback((season: number, episode: number) => {
    if (!details) return;
    router.push({
      pathname: '/watch/[id]',
      params: {
        id: details.id,
        title: details.title,
        season: String(season),
        episode: String(episode),
      },
    });
  }, [details]);

  useEffect(() => {
    setMediaFavoriteHeader({
      visible: Boolean(details) && favoriteStatusReady && isAuthenticated,
      isFavorite,
      busy: favoriteBusy,
      onPress: () => {
        void onToggleFavorite();
      },
    });
    return () => {
      resetMediaFavoriteHeader();
    };
  }, [details, favoriteBusy, favoriteStatusReady, isAuthenticated, isFavorite, onToggleFavorite]);

  const detailsHeaderContent = useMemo(() => {
    if (loading || !details) return null;
    return (
      <>
        <View style={styles.heroCard}>
          <MediaImage primaryUri={backdropUri} fallbackUris={[posterUri]} style={styles.heroImage} imageKey={details.id} priority="high" />
          {!logoFailed && logoUri && readyLogoUri === logoUri ? (
            <View style={styles.logoWrap}>
              <Image
                source={{ uri: logoUri }}
                style={styles.logo}
                contentFit="contain"
                transition={0}
                onError={handleLogoError}
              />
            </View>
          ) : null}
        </View>

        <ThemedText style={styles.title}>{details.title}</ThemedText>
        <View style={styles.metaRow}>
          <ThemedText style={styles.metaItem}>{details.type === 'tv' ? copy.media.tv : copy.media.movie}</ThemedText>
          {!!details.releaseDate ? <ThemedText style={styles.metaItem}>{details.releaseDate.slice(0, 4)}</ThemedText> : null}
        </View>

        <RatingsRow
          theme={theme}
          kp={details.ratings?.kp ?? details.rating}
          tmdb={details.ratings?.tmdb}
          imdb={details.ratings?.imdb}
        />

        {details.genres && details.genres.length > 0 ? (
          <View style={styles.genresRow}>
            {details.genres.map((genre) => (
              <View key={genre.id} style={styles.genreChip}>
                <ThemedText style={styles.genreText}>{genre.name}</ThemedText>
              </View>
            ))}
          </View>
        ) : null}

        <View style={styles.actionsRow}>
          <Pressable style={styles.watchButton} onPress={handleWatchPress}>
            <View style={styles.watchButtonContent}>
              <Play size={18} strokeWidth={2.4} color="#FFFFFF" />
              <ThemedText style={styles.watchButtonText}>{watchLabel}</ThemedText>
            </View>
          </Pressable>
          <Pressable style={styles.iconButton} accessibilityLabel={copy.media.download}>
            <Download size={20} strokeWidth={2.3} color={theme.text} />
          </Pressable>
        </View>

        {!!details.description ? <ThemedText style={styles.description}>{details.description}</ThemedText> : null}
      </>
    );
  }, [
    backdropUri,
    copy.media.download,
    copy.media.movie,
    copy.media.tv,
    details,
    loading,
    logoFailed,
    logoUri,
    posterUri,
    readyLogoUri,
    styles,
    theme,
    watchLabel,
    handleLogoError,
    handleWatchPress,
  ]);

  if (!loading && details?.type === 'tv' && seriesCatalog && selectedSeasonData) {
    return (
      <ThemedView style={styles.container}>
        <SeriesEpisodesSection
          copy={copy}
          theme={theme}
          styles={styles}
          detailsId={details.id}
          detailsDescription={details.description}
          canReadProgress={canReadProgress}
          selectedSeasonData={selectedSeasonData}
          seriesCatalog={seriesCatalog}
          isSeasonPickerExpanded={isSeasonPickerExpanded}
          setSeasonPickerExpanded={setSeasonPickerExpanded}
          setSelectedSeason={setSelectedSeason}
          sortedEpisodes={sortedEpisodes}
          episodeMetaMap={episodeMetaMap}
          seasonProgressMap={seasonProgressMap}
          posterUri={posterUri}
          resolveEpisodeStillUrl={resolveEpisodeStillUrl}
          headerContent={detailsHeaderContent}
          onOpenEpisode={handleOpenEpisode}
        />
      </ThemedView>
    );
  }

  if (!loading && !details && error) {
    return (
      <ThemedView style={styles.container}>
        <View style={[styles.content, { justifyContent: 'center', flex: 1 }]}>
          <AppStatusEmptyState />
        </View>
      </ThemedView>
    );
  }

  return (
    <ThemedView style={styles.container}>
      <FlashList
        data={[{ id: 'media-static' }]}
        keyExtractor={(item) => item.id}
        showsVerticalScrollIndicator={false}
        renderItem={() => (
          <View style={styles.content}>
        {loading ? (
          <>
            <ThemedView type="backgroundSelected" style={styles.skeletonHero} />
            <ThemedView type="backgroundSelected" style={styles.skeleton} />
            <ThemedView type="backgroundSelected" style={styles.skeleton} />
          </>
        ) : null}

        {!loading && details ? (
          <>
            <View style={styles.heroCard}>
              <MediaImage primaryUri={backdropUri} fallbackUris={[posterUri]} style={styles.heroImage} priority="high" />
              {!logoFailed && logoUri && readyLogoUri === logoUri ? (
                <View style={styles.logoWrap}>
                  <Image
                    source={{ uri: logoUri }}
                    style={styles.logo}
                    contentFit="contain"
                    transition={0}
                    onError={() => setLogoFailed(true)}
                  />
                </View>
              ) : null}
            </View>

            <ThemedText style={styles.title}>{details.title}</ThemedText>
            <View style={styles.metaRow}>
              <ThemedText style={styles.metaItem}>{details.type === 'tv' ? copy.media.tv : copy.media.movie}</ThemedText>
              {!!details.releaseDate ? <ThemedText style={styles.metaItem}>{details.releaseDate.slice(0, 4)}</ThemedText> : null}
            </View>

            <RatingsRow
              theme={theme}
              kp={details.ratings?.kp ?? details.rating}
              tmdb={details.ratings?.tmdb}
              imdb={details.ratings?.imdb}
            />

            {details.genres && details.genres.length > 0 ? (
              <View style={styles.genresRow}>
                {details.genres.map((genre) => (
                  <View key={genre.id} style={styles.genreChip}>
                    <ThemedText style={styles.genreText}>{genre.name}</ThemedText>
                  </View>
                ))}
              </View>
            ) : null}

            <View style={styles.actionsRow}>
              <Pressable
                style={styles.watchButton}
onPress={() =>
                  router.push({
                    pathname: '/watch/[id]',
                    params: {
                      id: details.id,
                      title: details.title,
                      season: details.type === 'tv' ? String(seriesProgress?.lastSeason ?? firstEpisode?.season ?? 1) : undefined,
                      episode: details.type === 'tv' ? String(seriesProgress?.lastEpisode ?? firstEpisode?.episode ?? 1) : undefined,
                    },
                  })
                }>
                <View style={styles.watchButtonContent}>
                  <Play size={18} strokeWidth={2.4} color="#FFFFFF" />
                  <ThemedText style={styles.watchButtonText}>{watchLabel}</ThemedText>
                </View>
              </Pressable>
              <Pressable style={styles.iconButton} accessibilityLabel={copy.media.download}>
                <Download size={20} strokeWidth={2.3} color={theme.text} />
              </Pressable>
            </View>

            {!!details.description ? <ThemedText style={styles.description}>{details.description}</ThemedText> : null}

          </>
        ) : null}

        {!loading && error && details ? (
          <ThemedText type="small" themeColor="danger">
            {copy.home.loadError}: {error}
          </ThemedText>
        ) : null}
          </View>
        )}
      />
    </ThemedView>
  );
}
