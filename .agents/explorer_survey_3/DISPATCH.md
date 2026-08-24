## 2026-08-24T19:54:31Z

Investigate Media Card integration, Movie Selection sheet, Player/Details linking, and reference implementations for Channel Feeds.

Specific areas to investigate:
1. Movie search and retrieval APIs: How does `MoviesRepository.swift` or `MoviesApi.swift` provide search (`searchMovies`), popular/trending movies, and movie details (`MediaDetailsDto` / `MovieItemDto`)?
2. How to build a "Movie Selector Sheet" for the channel author to search for and attach a movie/show to a post.
3. Interactive Media Card design inside channel feed:
   - Rendering poster, title, rating, year, genre badge.
   - One-tap quick play: Opening `PlayerView` directly with media item or resolving Alloha stream.
   - Opening full `DetailsView` sheet / navigation.
4. Reference review: Inspect `neomovies-mobile/` (if any chat/channel/feed reference exists) or existing card patterns in `HomeView.swift` / `SearchView.swift` to ensure seamless Sloosh design consistency.
5. Emoji reactions interaction pattern and state management.
