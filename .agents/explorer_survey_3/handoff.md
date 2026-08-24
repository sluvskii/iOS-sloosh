# Handoff Report — Media Card Integration, Movie Selection Sheet & Channel Interactions

## 1. Observation

Direct investigation of the Sloosh iOS codebase (`W:\iOS-sloosh\sloosh-iOS\sloosh\Sources\`) and reference codebase (`W:\iOS-sloosh\neomovies-mobile\`) revealed the following concrete mechanisms and structures:

### 1.1 Existing Movie Search, Discovery & Details APIs
- **`MoviesApi.swift`** (`Data/Network/MoviesApi.swift:136-150`):
  ```swift
  func searchMovies(query: String, page: Int = 1) async throws -> ApiEnvelope<MediaResponse> {
      var queryItems = [URLQueryItem(name: "page", value: String(page))]
      let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty { queryItems.append(URLQueryItem(name: "query", value: trimmed)) }
      return try await performRequest(endpoint: "api/v1/search", queryItems: queryItems)
  }
  ```
  - Uses Kinopoisk Full-Text Fuzzy Search (`api/v1/search`), handling Russian transliteration, typos, and ranking.
  - Popular movies: `api/v1/movies/popular` (`MoviesApi.swift:116`).
  - Top rated: `api/v1/movies/top-rated` and `api/v1/tv/top-rated` (`MoviesApi.swift:120, 124`).
  - Media details: `api/v2/movie/\(id)` (`MoviesApi.swift:128`).
- **`MoviesRepository.swift`** (`Data/Repositories/MoviesRepository.swift:47-158`):
  - `@MainActor class MoviesRepository: ObservableObject` with `static let shared = MoviesRepository()`.
  - In-memory session caches (`popularCache`, `topMoviesCache`, `detailsMemory`) and disk caches (`MediaListDiskCache` 4h TTL, `MediaDetailsDiskCache` 24h TTL in `Library/Caches`).
  - `searchMoviesResponse(query:page:filters:)` handles paginated search results, soft filtering, and sorting (`MoviesRepository.swift:160-207`).
- **`MediaDto` and `MediaDetailsDto`** (`Data/Models/Models.swift:69-252`):
  - `MediaDto`: contains `id`, `originalId`, `title`, `name`, `originalTitle`, `year`, `rating`, `ratings`, `posterUrl`, `genres`, `displayTitle`, `displayPosterUrl`.
  - `MediaDetailsDto`: contains `id`, `title`, `originalTitle`, `description`, `type`, `year`, `genres`, `ratings`, `ids`, `displayPosterUrl`, `displayBackdropUrl`, `displayLogoUrl`.
- **`MediaCardPayload`** (`Data/Models/MessengerModels.swift:8-32`):
  ```swift
  public struct MediaCardPayload: Identifiable, Codable, Equatable, Hashable {
      public var id: String { mediaId }
      public let mediaId: String
      public let type: String
      public let title: String
      public let posterUrl: String?
      public let rating: Double?
      public let year: String?
  }
  ```

### 1.2 Direct Chats & Existing Media Card
- **`MediaMessageCardView.swift`** (`UI/Messenger/MediaMessageCardView.swift:1-131`):
  - Renders 2:3 poster via `AsyncCachedImage` with `averageColor` extraction for the card background:
    ```swift
    if let avg = image.averageColor {
        let blended = avg.blended(with: .black, fraction: 0.65)
        cardBgColor = Color(blended)
    }
    ```
  - Rating badge via `Color.rating(rating)` (`UI/Shared/MediaHelpers.swift:7-14`).
  - White play button Capsule: `.frame(height: 40).background(Capsule().fill(Color.white.opacity(0.92))).glassEffect(in: Capsule())`.
- **`ChatDetailView.swift`** (`UI/Messenger/ChatDetailView.swift:93-122`):
  - Handles two interaction channels for media cards:
    1. **Details Navigation**: `selectedMovieIdForDetails: String?` -> `.navigationDestination(item: $selectedMovieIdForDetails) { DetailsView(movieId: $0, ...) }`.
    2. **Direct Play**: `selectedMediaForDirectPlay: MediaCardPayload?` -> `.sheet(item: $selectedMediaForDirectPlay)` presenting `HomeDirectPlayWrapper` -> resolves source and launches `.fullScreenCover(item: $activePlayerConfig) { PlayerView(...) }`.

### 1.3 Sloosh Design System & Theme Rules
- Liquid Glass styling: `.glassEffect(.regular.interactive(), in: ...)` or `.glassEffect(in: ...)`.
- Strictly NO `.ultraThinMaterial` (`AGENTS.md`).
- Rating badge helper: `Color.rating(Double)` in `UI/Shared/MediaHelpers.swift`.
- Accent color: `Color.slooshAccent` in `UI/Color+Theme.swift`.

---

## 2. Logic Chain

1. **Movie Search and Selection for Authors**:
   - Channel authors need a frictionless way to attach movies/shows to their broadcast posts without leaving the channel composer.
   - `MoviesRepository.shared.getPopularMovies()` provides instant trending suggestions on cold open of `MovieSelectorSheet`.
   - `MoviesRepository.shared.searchMoviesResponse(query:page:)` gives fast, fuzzy-matched Kinopoisk search with posters and ratings.
   - Once chosen, `MediaDto` or `MediaDetailsDto` is mapped to `MediaCardPayload` and attached to the draft post.

2. **Channel Post Media Card Design**:
   - Unlike 1-on-1 chats where cards are 220pt wide aligned to left/right chat bubbles, channel posts are wide broadcast cards.
   - `ChannelMediaCardView` should span the full post width (or card container width) in the channel feed.
   - To match Sloosh's flagship aesthetic:
     - Prominent 2:3 poster or backdrop with rounded continuous corners (`16pt`).
     - Floating rating pill (`Color.rating(rating)`).
     - Title, year, and genre badge.
     - Dynamic background tint extracted from poster `averageColor` blended with dark background.
     - One-tap prominent "Смотреть" button with Liquid Glass capsule.

3. **Linking Playback and Details Screens**:
   - **One-tap Playback**: Tapping "Смотреть" invokes `HomeDirectPlayWrapper(movieId: media.mediaId, fallbackTitle: media.title, initialKpId: Int(media.mediaId))`. This seamlessly queries Alloha translations/episodes and launches `PlayerView` full-screen without manual boilerplate.
   - **Full Details View**: Tapping on the poster or title pushes `DetailsView(movieId: media.mediaId, ...)`, allowing subscribers to view description, cast, backdrop gallery, and add the movie to favorites.

4. **Emoji Reactions Flow**:
   - Telegram-style reactions require per-post aggregation and multi-user participation.
   - Storing reactions as `reactions: [String: String]?` (userId -> emoji) in each post node (`/channels/{channelId}/posts/{postId}/reactions/{userId}`) ensures idempotent writes, simple toggle logic, and concurrent safety without race conditions.
   - The UI aggregates reactions into dynamic pills `(emoji, count, isMine)` displayed beneath the post with Liquid Glass styling (`.glassEffect(.regular.interactive(), in: Capsule())`).

---

## 3. Caveats

- **Network Mode**: Offline channel viewing will rely on `MediaListDiskCache` / `MediaDetailsDiskCache` and local message disk caches. If the user is offline, cached poster images in `URLCache` / `AsyncCachedImage` will display properly.
- **TV Series Direct Play**: When a TV series card is tapped with "Смотреть", `HomeDirectPlayWrapper` presents season/episode picker first; it does not automatically assume Episode 1 if previous progress exists in `PlaybackProgressStore`.
- **Reactions Count Scale**: For public channels with large subscriber counts, client-side aggregation from `[String: String]` is optimal up to thousands of reactions per post, matching the Firebase RTDB REST model used across the rest of `MessengerRepository`.

---

## 4. Conclusion & Proposed Architecture

### 4.1 Component 1: `MovieSelectorSheet`
A dedicated sheet allowing channel authors to search and attach movies/shows.

```swift
import SwiftUI

public struct MovieSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = MoviesRepository.shared
    
    @State private var query: String = ""
    @State private var searchResults: [MediaDto] = []
    @State private var popularMovies: [MediaDto] = []
    @State private var isLoading: Bool = false
    @State private var searchTask: Task<Void, Never>? = nil
    
    public let onSelect: (MediaCardPayload) -> Void

    public init(onSelect: @escaping (MediaCardPayload) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                // Liquid Glass Search Bar
                searchBar
                
                if isLoading && searchResults.isEmpty && !query.isEmpty {
                    ProgressView("Поиск...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    trendingSection
                } else if searchResults.isEmpty {
                    AppEmptyStateView(
                        icon: "film",
                        title: "Ничего не найдено",
                        description: "Попробуйте изменить поисковый запрос"
                    )
                } else {
                    resultsGrid(searchResults)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .navigationTitle("Прикрепить фильм")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .task {
                if popularMovies.isEmpty {
                    popularMovies = (try? await repo.getPopularMovies(page: 1)) ?? []
                }
            }
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("Название фильма или сериала", text: $query)
                .font(.system(size: 15))
                .foregroundColor(.primary)
                .autocorrectionDisabled()
                .onChange(of: query) { _, newQuery in
                    performDebouncedSearch(query: newQuery)
                }
            if !query.isEmpty {
                Button {
                    query = ""
                    searchResults = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .glassEffect(.regular.interactive(), in: Capsule())
    }

    private var trendingSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("ПОПУЛЯРНОЕ СЕЙЧАС")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 4)
                
                resultsGrid(popularMovies)
            }
        }
        .scrollIndicators(.hidden)
    }

    private func resultsGrid(_ items: [MediaDto]) -> some View {
        let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(items) { movie in
                    Button {
                        selectMovie(movie)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack(alignment: .topLeading) {
                                AsyncCachedImage(urlString: movie.displayPosterUrl ?? "") {
                                    Rectangle().fill(Color.white.opacity(0.1)).aspectRatio(2/3, contentMode: .fill)
                                } content: { image in
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(2/3, contentMode: .fill)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                
                                if let rating = movie.rating, rating > 0 {
                                    Text(String(format: "%.1f", rating))
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.rating(rating))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .padding(6)
                                }
                            }
                            
                            Text(movie.displayTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            if let year = movie.year?.stringValue {
                                Text(year)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
    }

    private func performDebouncedSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchResults = []
            isLoading = false
            return
        }
        
        isLoading = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if Task.isCancelled { return }
            let response = try? await repo.searchMovies(query: trimmed, page: 1)
            if !Task.isCancelled {
                self.searchResults = response ?? []
                self.isLoading = false
            }
        }
    }

    private func selectMovie(_ movie: MediaDto) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let payload = MediaCardPayload(
            mediaId: movie.id,
            type: movie.type ?? "movie",
            title: movie.displayTitle,
            posterUrl: movie.displayPosterUrl,
            rating: movie.rating ?? movie.ratings?.kp,
            year: movie.year?.stringValue
        )
        onSelect(payload)
        dismiss()
    }
}
```

---

### 4.2 Component 2: `ChannelMediaCardView`
The full-width interactive media card rendered inside channel posts.

```swift
import SwiftUI

public struct ChannelMediaCardView: View {
    public let media: MediaCardPayload
    public var onOpenDetails: ((String) -> Void)?
    public var onPlayDirectly: ((MediaCardPayload) -> Void)?

    @State private var cardBgColor: Color = Color(white: 0.12)

    public init(
        media: MediaCardPayload,
        onOpenDetails: ((String) -> Void)? = nil,
        onPlayDirectly: ((MediaCardPayload) -> Void)? = nil
    ) {
        self.media = media
        self.onOpenDetails = onOpenDetails
        self.onPlayDirectly = onPlayDirectly
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Poster & metadata tap -> DetailsView
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onOpenDetails?(media.mediaId)
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    // 2:3 Poster with rating badge
                    ZStack(alignment: .topLeading) {
                        if let posterUrl = media.posterUrl, !posterUrl.isEmpty {
                            AsyncCachedImage(urlString: posterUrl) {
                                Rectangle().fill(Color.white.opacity(0.1))
                            } content: { image in
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(2/3, contentMode: .fill)
                                    .onAppear {
                                        if let avg = image.averageColor {
                                            let blended = avg.blended(with: .black, fraction: 0.7)
                                            cardBgColor = Color(blended)
                                        }
                                    }
                            }
                            .frame(width: 80, height: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        } else {
                            Rectangle()
                                .fill(Color.white.opacity(0.1))
                                .frame(width: 80, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        if let rating = media.rating, rating > 0 {
                            Text(String(format: "%.1f", rating))
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.rating(rating))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .padding(4)
                        }
                    }

                    // Metadata details
                    VStack(alignment: .leading, spacing: 6) {
                        Text(media.title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            if let year = media.year, !year.isEmpty {
                                Text(year)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            Text(media.type == "tv" ? "• Сериал" : "• Фильм")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                        }

                        Spacer(minLength: 0)

                        Text("Подробнее →")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.slooshAccent)
                    }
                    .frame(height: 120)

                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            // Direct "Смотреть" button
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                if let onPlayDirectly = onPlayDirectly {
                    onPlayDirectly(media)
                } else {
                    onOpenDetails?(media.mediaId)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .black))
                    Text("Смотреть")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(Color.white.opacity(0.92), in: Capsule())
                .glassEffect(in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(cardBgColor)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
```

---

### 4.3 Component 3: Emoji Reaction Data Flow & UI
- **Pills Layout**:
  ```swift
  struct ChannelPostReactionsView: View {
      let reactions: [String: String] // userId -> emoji
      let currentUserId: String
      let onToggleReaction: (String) -> Void

      private var groupedReactions: [(emoji: String, count: Int, isMine: Bool)] {
          let grouped = Dictionary(grouping: reactions.values, by: { $0 })
          let myReaction = reactions[currentUserId]
          return grouped.map { emoji, list in
              (emoji: emoji, count: list.count, isMine: myReaction == emoji)
          }.sorted { $0.count > $1.count }
      }

      var body: some View {
          HStack(spacing: 6) {
              ForEach(groupedReactions, id: \.emoji) { item in
                  Button {
                      UIImpactFeedbackGenerator(style: .light).impactOccurred()
                      onToggleReaction(item.emoji)
                  } label: {
                      HStack(spacing: 4) {
                          Text(item.emoji)
                              .font(.system(size: 13))
                          Text("\(item.count)")
                              .font(.system(size: 12, weight: .bold))
                              .foregroundColor(item.isMine ? .slooshAccent : .secondary)
                      }
                      .padding(.horizontal, 8)
                      .padding(.vertical, 5)
                      .background(
                          Capsule()
                              .fill(item.isMine ? Color.slooshAccent.opacity(0.2) : Color.white.opacity(0.08))
                      )
                      .glassEffect(.regular.interactive(), in: Capsule())
                  }
                  .buttonStyle(.plain)
              }
          }
      }
  }
  ```

---

## 5. Verification Method

1. **Verify Search & Popular Movie Retrieval**:
   - Inspect `MoviesRepository.swift:47-84` and `MoviesApi.swift:116-150` for signature consistency with `searchMovies(query:page:)` and `getPopularMovies(page:)`.
2. **Verify Media Card & Player Linking**:
   - Inspect `HomeDirectPlayWrapper.swift:18-74` to confirm it accepts `movieId`, `fallbackTitle`, `initialKpId` and invokes `onPlay(PlayerConfig)` which seamlessly powers `PlayerView`.
   - Inspect `ChatDetailView.swift:93-122` for the exact `.sheet(item: $selectedMediaForDirectPlay)` -> `.fullScreenCover(item: $activePlayerConfig)` handoff pattern.
3. **Verify Design System Compliance**:
   - Ensure zero instances of `.ultraThinMaterial` in all proposed components (all surfaces strictly use `.glassEffect()`).
   - Check `Color+Theme.swift` and `MediaHelpers.swift` for `Color.slooshAccent` and `Color.rating(Double)`.
