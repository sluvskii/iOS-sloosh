import { ChevronDown, Menu } from "lucide-react-native";
import { Dispatch, ReactElement, SetStateAction, useEffect, useMemo, useState } from "react";
import { Pressable, ScrollView, View } from "react-native";

import { ThemedText } from "@/components/themed-text";
import {
  CollapsCatalogSeries,
  CollapsEpisode,
  CollapsSeason,
} from "@/native/collaps-parser";
import { createMediaDetailsStyles } from "@/styles/media-details.styles";
import { EpisodesListView, NativeEpisodeItem } from "neomovies-core";

type ThemePalette = {
  text: string;
  textSecondary: string;
  border: string;
  backgroundElement: string;
};

type EpisodeMeta = {
  overview?: string;
  name?: string;
  tmdbRating?: number | null;
  imdbRating?: number | null;
};

type SeriesEpisodesSectionProps = {
  copy: { watchSelector: { episodes: string; seasons: string } };
  theme: ThemePalette;
  styles: ReturnType<typeof createMediaDetailsStyles>;
  detailsId: string;
  detailsDescription: string;
  canReadProgress: boolean;
  selectedSeasonData: CollapsSeason;
  seriesCatalog: CollapsCatalogSeries;
  isSeasonPickerExpanded: boolean;
  setSeasonPickerExpanded: Dispatch<SetStateAction<boolean>>;
  setSelectedSeason: (season: number) => void;
  sortedEpisodes: CollapsEpisode[];
  episodeMetaMap: Record<string, EpisodeMeta>;
  seasonProgressMap: Record<string, number>;
  seasonWatchedMap: Record<string, boolean>;
  posterUri: string | null;
  resolveEpisodeStillUrl: (
    movieId?: string | null,
    season?: number,
    episode?: number,
    size?: "small" | "large",
  ) => string | null;
  onOpenEpisode: (season: number, episode: number) => void;
  onToggleEpisodeWatched: (season: number, episode: number) => void;
  headerContent?: ReactElement | null;
};

export function SeriesEpisodesSection(props: SeriesEpisodesSectionProps) {
  const {
    copy,
    theme,
    styles,
    detailsId,
    detailsDescription,
    canReadProgress,
    selectedSeasonData,
    seriesCatalog,
    isSeasonPickerExpanded,
    setSeasonPickerExpanded,
    setSelectedSeason,
    sortedEpisodes,
    episodeMetaMap,
    seasonProgressMap,
    seasonWatchedMap,
    posterUri,
    resolveEpisodeStillUrl,
    onOpenEpisode,
    onToggleEpisodeWatched,
    headerContent,
  } = props;
  const [listHeight, setListHeight] = useState(1);
  useEffect(() => {
    setListHeight(1);
  }, [selectedSeasonData.season]);

  const sortedSeasons = useMemo(() => {
    return seriesCatalog.seasons.slice().sort((a, b) => a.season - b.season);
  }, [seriesCatalog.seasons]);

  const nativeEpisodes = useMemo<NativeEpisodeItem[]>(() => {
    return sortedEpisodes.map((item) => {
      const key = `${item.season}-${item.episode}`;
      const meta = episodeMetaMap[key];
      const progress = canReadProgress
        ? Math.max(0, Math.min(seasonProgressMap[key] ?? 0, 100))
        : 0;
      const watched = canReadProgress ? (seasonWatchedMap[key] ?? false) : false;

      return {
        season: item.season,
        episode: item.episode,
        title: meta?.name || item.title || `Episode ${item.episode}`,
        description: meta?.overview || detailsDescription,
        progress,
        watched,
        stillUrl: resolveEpisodeStillUrl(detailsId, item.season, item.episode, "large"),
        fallbackPosterUrl: posterUri,
        tmdbRating: meta?.tmdbRating,
        imdbRating: meta?.imdbRating,
      };
    });
  }, [
    canReadProgress,
    detailsDescription,
    detailsId,
    episodeMetaMap,
    posterUri,
    resolveEpisodeStillUrl,
    seasonProgressMap,
    seasonWatchedMap,
    sortedEpisodes,
  ]);

  return (
    <ScrollView
      style={{ flex: 1, width: "100%" }}
      contentContainerStyle={styles.flashListContent}
      showsVerticalScrollIndicator={false}
    >
      <View style={styles.flashListHeader}>
        {headerContent}
        <ThemedText style={styles.sectionTitle}>
          {copy.watchSelector.episodes}
        </ThemedText>

        <View style={styles.seasonSelectorWrapper}>
          <Pressable
            style={styles.seasonsHeader}
            onPress={() => setSeasonPickerExpanded((prev) => !prev)}
          >
            <View style={styles.seasonsHeaderLeft}>
              <Menu size={18} color={theme.text} />
              <ThemedText style={styles.seasonsHeaderLabel}>
                Season {selectedSeasonData.season}
              </ThemedText>
            </View>
            <View style={styles.seasonsHeaderLeft}>
              <ThemedText style={styles.seasonMeta}>
                {seriesCatalog.seasons.length} {copy.watchSelector.seasons},{" "}
                {selectedSeasonData.episodes.length} {copy.watchSelector.episodes}
              </ThemedText>
              <ChevronDown size={16} color={theme.textSecondary} />
            </View>
          </Pressable>

          {isSeasonPickerExpanded ? (
            <View style={styles.seasonDropdownList}>
              {sortedSeasons.map((season) => (
                <Pressable
                  key={`season-${season.season}`}
                  style={[
                    styles.seasonOptionRow,
                    season.season === selectedSeasonData.season
                      ? styles.seasonOptionRowActive
                      : null,
                  ]}
                  onPress={() => {
                    setSelectedSeason(season.season);
                    setSeasonPickerExpanded(false);
                  }}
                >
                  <ThemedText style={styles.seasonOptionText}>
                    Season {season.season}
                  </ThemedText>
                  {season.season === selectedSeasonData.season ? (
                    <ThemedText style={styles.seasonOptionCheck}>✓</ThemedText>
                  ) : null}
                </Pressable>
              ))}
            </View>
          ) : null}
        </View>
      </View>

      <EpisodesListView
        key={`episodes-${selectedSeasonData.season}-${nativeEpisodes.length}`}
        style={{ width: "100%", height: listHeight, marginTop: 12 }}
        episodes={nativeEpisodes}
        textColor={theme.text}
        secondaryTextColor={theme.textSecondary}
        borderColor={theme.border}
        backgroundColor={theme.backgroundElement}
        onContentHeight={(event) => {
          const next = Math.max(1, Math.ceil(event.nativeEvent.height));
          if (next !== listHeight) setListHeight(next);
        }}
        onEpisodePress={(event) => {
          onOpenEpisode(event.nativeEvent.season, event.nativeEvent.episode);
        }}
        onWatchedToggle={(event: { nativeEvent: { season: number; episode: number } }) => {
          onToggleEpisodeWatched(event.nativeEvent.season, event.nativeEvent.episode);
        }}
      />
    </ScrollView>
  );
}
