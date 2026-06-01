export type MediaType = 'movie' | 'tv';

export type SearchResultItem = {
  id: string;
  title: string;
  originalTitle: string;
  year?: number | null;
  rating: number;
  posterUrl: string;
  description: string;
  type: MediaType;
};

export type SearchResponse = {
  results: SearchResultItem[];
  total: number;
  pages: number;
};

export type MediaDetails = {
  id: string;
  sourceId: string;
  title: string;
  originalTitle: string;
  description: string;
  releaseDate: string;
  type: MediaType;
  rating: number;
  posterUrl: string;
  backdropUrl: string;
  duration: number;
  country: string;
  language: string;
  ratings?: {
    kp?: number | null;
    tmdb?: number | null;
    imdb?: number | null;
  };
  genres?: {
    id: string;
    name: string;
  }[];
};

export type TvEpisodeDetails = {
  id: number;
  name: string;
  overview: string;
  airDate: string;
  seasonNumber: number;
  episodeNumber: number;
  stillPath?: string | null;
  language: string;
  ratings: {
    tmdb?: number | null;
    imdb?: number | null;
  };
};

export type ApiEnvelope<T> = {
  success: boolean;
  data: T;
};

export type PopularMovie = {
  id: string;
  title: string;
  year?: number | null;
  rating?: number | null;
  posterUrl?: string;
};

export type PopularMoviesResponse = {
  results: PopularMovie[];
  total?: number;
  pages?: number;
};

export type FavoriteItem = {
  id: string;
  mediaId: string;
  mediaType: MediaType;
  title: string;
  posterUrl: string;
  rating?: number | null;
  year?: number | null;
  createdAt: string;
};

export type TopRatedResponse = {
  results: PopularMovie[];
  total?: number;
  pages?: number;
};
