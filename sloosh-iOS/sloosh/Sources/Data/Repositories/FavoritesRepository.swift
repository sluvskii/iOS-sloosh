import Foundation

@MainActor
class FavoritesRepository: ObservableObject {
    static let shared = FavoritesRepository()
    
    @Published var favorites: [FavoriteDto] = []
    private let defaultsKey = "local_favorites"
    private let dataStore = JSONDataStore<[FavoriteDto]>(fileName: "favorites")
    
    private init() {
        loadFavorites()
        refreshMissingMetadataIfNeeded()
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([FavoriteDto].self, from: data) {
            favorites = decoded
            dataStore.save(decoded)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        } else {
            favorites = dataStore.load(defaultValue: [])
        }
    }
    
    private func saveFavorites() {
        dataStore.save(favorites)
    }
    
    func getFavorites() -> [FavoriteDto] {
        return favorites
    }
    
    func isFavorite(mediaId: String, mediaType: String) -> Bool {
        return favorites.contains { $0.mediaId == mediaId && $0.type == mediaType }
    }
    
    func addToFavorites(mediaId: String, mediaType: String, title: String?, posterUrl: String?, rating: Double?, year: String? = nil, genres: [GenreDto]? = nil) {
        if !isFavorite(mediaId: mediaId, mediaType: mediaType) {
            let newFav = FavoriteDto(
                id: UUID().uuidString,
                mediaId: mediaId,
                type: mediaType,
                title: title,
                posterUrl: posterUrl,
                rating: rating,
                year: year,
                genres: genres
            )
            favorites.append(newFav)
            saveFavorites()
        }
    }
    
    func removeFromFavorites(mediaId: String, mediaType: String) {
        favorites.removeAll { $0.mediaId == mediaId && $0.type == mediaType }
        saveFavorites()
    }

    func refreshMissingMetadataIfNeeded() {
        let needsRefresh = favorites.contains {
            (($0.rating == nil || $0.rating == 0 || $0.year == nil || $0.genres == nil) && ($0.mediaId?.isEmpty == false))
        }

        guard needsRefresh else { return }

        Task {
            await refreshMissingMetadata()
        }
    }

    private func refreshMissingMetadata() async {
        var updatedFavorites = favorites
        var didChange = false

        for index in updatedFavorites.indices {
            let favorite = updatedFavorites[index]
            guard let mediaId = favorite.mediaId, !mediaId.isEmpty else { continue }
            guard favorite.rating == nil || favorite.rating == 0 || favorite.year == nil || favorite.genres == nil else { continue }

            do {
                guard let details = try await MoviesRepository.shared.getDetails(id: mediaId) else {
                    continue
                }

                let extractedYear = details.releaseDate.map { String($0.prefix(4)) }

                updatedFavorites[index] = FavoriteDto(
                    id: favorite.id,
                    mediaId: favorite.mediaId,
                    type: favorite.type,
                    title: favorite.title ?? details.title ?? details.name,
                    posterUrl: favorite.posterUrl ?? details.posterUrl ?? details.backdropUrl,
                    rating: details.rating ?? favorite.rating,
                    year: extractedYear ?? favorite.year,
                    genres: details.genres ?? favorite.genres
                )
                didChange = true
            } catch {
                continue
            }
        }

        if didChange {
            favorites = updatedFavorites
            saveFavorites()
        }
    }
}
