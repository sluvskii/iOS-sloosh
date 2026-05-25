import Foundation

@MainActor
class FavoritesRepository: ObservableObject {
    static let shared = FavoritesRepository()
    
    @Published var favorites: [FavoriteDto] = []
    private let defaultsKey = "local_favorites"
    
    private init() {
        loadFavorites()
    }
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([FavoriteDto].self, from: data) {
            favorites = decoded
        }
    }
    
    private func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(encoded, forKey: defaultsKey)
        }
    }
    
    func getFavorites() -> [FavoriteDto] {
        return favorites
    }
    
    func isFavorite(mediaId: String, mediaType: String) -> Bool {
        return favorites.contains { $0.mediaId == mediaId && $0.type == mediaType }
    }
    
    func addToFavorites(mediaId: String, mediaType: String, title: String?, posterUrl: String?) {
        if !isFavorite(mediaId: mediaId, mediaType: mediaType) {
            let newFav = FavoriteDto(
                id: UUID().uuidString,
                mediaId: mediaId,
                type: mediaType,
                title: title,
                posterUrl: posterUrl
            )
            favorites.append(newFav)
            saveFavorites()
        }
    }
    
    func removeFromFavorites(mediaId: String, mediaType: String) {
        favorites.removeAll { $0.mediaId == mediaId && $0.type == mediaType }
        saveFavorites()
    }
}
