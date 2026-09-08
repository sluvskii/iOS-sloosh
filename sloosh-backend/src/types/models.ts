export interface CastMemberDto {
  id: number
  name: string
  originalName: string
  character: string
  photo: string | null
}

export interface TrailerVideoDto {
  id: string
  name: string
  key: string
  site: string
  url: string
}

export interface CollectionPartDto {
  id: string
  title: string
  originalTitle: string
  overview: string
  poster: string | null
  backdrop: string | null
  year: number | null
  rating: number
  type: string
}

export interface MovieCollectionDto {
  id: number
  name: string
  overview: string
  poster: string | null
  backdrop: string | null
  parts: CollectionPartDto[]
}

export interface ProductionCompanyDto {
  id: number
  name: string
  logo: string | null
}

export interface NetworkDto {
  id: number
  name: string
  logo: string | null
}

export interface MediaDto {
  id: string
  title: string
  name?: string
  originalTitle?: string
  original_title?: string
  description?: string
  overview?: string
  type: "movie" | "tv"
  year?: number
  releaseDate?: string
  rating?: number
  ratings?: {
    kp?: number
    imdb?: number
    tmdb?: number
  }
  poster?: string
  posterUrl?: string
  poster_path?: string
  backdrop?: string
  backdropUrl?: string
  backdrop_path?: string
  genres?: Array<{ id: string | number; name: string }>
  countries?: string[]
  externalIds?: {
    kp?: number
    tmdb?: number
    imdb?: string
  }
  ids?: {
    kp?: number
    tmdb?: number
    imdb?: string
  }
}

export interface MediaDetailsDto extends MediaDto {
  duration?: number
  countries?: string[]
  logo?: string | null
  cast?: CastMemberDto[]
  trailers?: TrailerVideoDto[]
  collection?: MovieCollectionDto | null
  productionCompanies?: ProductionCompanyDto[]
  networks?: NetworkDto[]
  similar?: MediaDto[]
  alloha?: {
    kpId: number | null
    imdbId: string | null
    iframeUrl: string | null
  }
}

export interface MediaResponse {
  results: MediaDto[]
  page: number
  total_pages: number
  total_results: number
  items?: MediaDto[]
  pages?: number
  total?: number
}

export interface CategoryItemDto {
  id: string
  name: string
  slug: string
  type: "movie" | "tv"
  backdrop: string | null
}

export interface CategorySectionDto {
  section: string
  items: CategoryItemDto[]
}

export interface PersonDetailsDto {
  id: number
  name: string
  originalName?: string
  biography?: string
  birthday?: string
  deathday?: string | null
  placeOfBirth?: string
  photo?: string | null
  knownForDepartment?: string
  department?: string
  gender?: number
  filmography: MediaDto[]
  photos?: string[]
  awards?: string
  keyProjects?: string
  interestingFact?: string
}
