export type Dictionary = {
  appName: string;
  tabs: {
    home: string;
    search: string;
    favorites: string;
    profile: string;
    details: string;
  };
  favorites: {
    empty: string;
    authAction: string;
    authRequiredSuffix: string;
  };
  profile: {
    authTitle: string;
    authDescription: string;
    authAction: string;
    authLoading: string;
    loadingProfile: string;
    settings: string;
    about: string;
    updates?: string;
    logout: string;
  };
  about: {
    appDescription: string;
    checkUpdates: string;
    checkUpdatesDesc: string;
    credits: string;
    creditsDesc: string;
    changelog: string;
    changelogDesc: string;
    version: string;
    branch: string;
    build: string;
    updateAvailable: string;
    updateDownload: string;
    updateRemindLater: string;
    updateChecking: string;
    updateNoNew: string;
    updateError: string;
  };
  credits: {
    libraries: string;
    team: string;
    thanks: string;
    community: string;
    madeWithLove: string;
    roles: {
      ernela: string;
      chernuha: string;
      iwnuply: string;
      sophron: string;
    };
  };
  changelog: {
    versions: {
      version: string;
      changes: string[];
    }[];
  };
  media: {
    movie: string;
    tv: string;
    watch: string;
    download: string;
    downloadComingSoon: string;
    downloadComingSoonMessage: string;
  };
  home: {
    continueWatching: string;
    nextUp: string;
    popular: string;
    topFilms: string;
    topSeries: string;
    watchNow: string;
    loading: string;
    loadError: string;
  };
  search: {
    title: string;
    placeholder: string;
    loadError: string;
    recentTitle: string;
    emptyState: string;
  };
  watchSelector: {
    title: string;
    seasons: string;
    episodes: string;
    primary: string;
    missingPayload: string;
  };
  settings: {
    title: string;
    common: string;
    source: string;
    language: string;
    appearance: string;
    darkTheme: string;
    storage: string;
    clearCache: string;
    clearCacheDesc: string;
    defaultSource: string;
    sourceDefaultTitle: string;
    sourceDefaultDesc: string;
    sourceAlternativeTitle: string;
    sourceAlternativeDesc: string;
  };
  appStatus: {
    offlineBanner: string;
    offlineNoCache: string;
    offlineSearchUnavailable: string;
    noInternetTitle: string;
    noInternetDescription: string;
    maintenanceTitle: string;
    maintenanceDescription: string;
  };
};

export type Locale = 'en' | 'ru' | 'uk' | 'be' | 'ro';
