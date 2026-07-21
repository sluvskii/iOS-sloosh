import Foundation
import SwiftData

@MainActor
class FavoritesRepository: ObservableObject {
    static let shared = FavoritesRepository()
    
    @Published var favorites: [FavoriteDto] = []
    
    private var context: ModelContext {
        return AppDatabase.shared.container.mainContext
    }
    
    private init() {
        loadFavorites()
        refreshMissingMetadataIfNeeded()
    }
    
    private func loadFavorites() {
        let defaultsKey = "local_favorites"
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([FavoriteDto].self, from: data) {
            for dto in decoded {
                let mediaId = dto.mediaId ?? ""
                let type = dto.type ?? ""
                if !mediaId.isEmpty, !type.isEmpty {
                    let model = FavoriteModel(
                        mediaId: mediaId,
                        type: type,
                        title: dto.title,
                        posterUrl: dto.posterUrl,
                        rating: dto.rating,
                        year: dto.year,
                        genresRaw: try? String(data: JSONEncoder().encode(dto.genres), encoding: .utf8)
                    )
                    context.insert(model)
                }
            }
            try? context.save()
            UserDefaults.standard.removeObject(forKey: defaultsKey)
        }
        
        reloadFromDb()
    }
    
    private func reloadFromDb() {
        let descriptor = FetchDescriptor<FavoriteModel>(sortBy: [SortDescriptor(\FavoriteModel.addedAt, order: .reverse)])
        let models: [FavoriteModel] = (try? context.fetch(descriptor)) ?? []
        
        self.favorites = models.map { model in
            var genres: [GenreDto]? = nil
            if let raw = model.genresRaw, let data = raw.data(using: .utf8) {
                genres = try? JSONDecoder().decode([GenreDto].self, from: data)
            }
            return FavoriteDto(
                id: UUID().uuidString,
                mediaId: model.mediaId,
                type: model.type,
                title: model.title,
                posterUrl: model.posterUrl,
                rating: model.rating,
                year: model.year,
                genres: genres
            )
        }
    }
    
    func getFavorites() -> [FavoriteDto] {
        return favorites
    }
    
    func isFavorite(mediaId: String, mediaType: String) -> Bool {
        return favorites.contains { $0.mediaId == mediaId && $0.type == mediaType }
    }
    
    func addToFavorites(mediaId: String, mediaType: String, title: String?, posterUrl: String?, rating: Double?, year: String? = nil, genres: [GenreDto]? = nil) {
        if !isFavorite(mediaId: mediaId, mediaType: mediaType) {
            let genresRaw = try? String(data: JSONEncoder().encode(genres), encoding: .utf8)
            let model = FavoriteModel(
                mediaId: mediaId,
                type: mediaType,
                title: title,
                posterUrl: posterUrl,
                rating: rating,
                year: year,
                genresRaw: genresRaw
            )
            context.insert(model)
            try? context.save()
            reloadFromDb()
        }
    }
    
    func removeFromFavorites(mediaId: String, mediaType: String) {
        let key = "\(mediaId)_\(mediaType)"
        let predicate = #Predicate<FavoriteModel> { $0.mediaIdTypeKey == key }
        if let model = try? context.fetch(FetchDescriptor<FavoriteModel>(predicate: predicate)).first {
            context.delete(model)
            try? context.save()
            reloadFromDb()
        }
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
        var didChange = false

        for favorite in favorites {
            guard let mediaId = favorite.mediaId, !mediaId.isEmpty else { continue }
            guard favorite.rating == nil || favorite.rating == 0 || favorite.year == nil || favorite.genres == nil else { continue }

            do {
                guard let details = try await MoviesRepository.shared.getDetails(id: mediaId) else {
                    continue
                }

                let extractedYear = details.year?.description
                let newTitle = favorite.title ?? details.title ?? details.originalTitle
                let newPosterUrl = favorite.posterUrl ?? details.poster ?? details.backdrop
                let newRating = details.ratings?.kp ?? favorite.rating
                let newYear = extractedYear ?? favorite.year
                let newGenres = details.genres?.compactMap { GenreDto(id: $0.lowercased(), name: $0) } ?? favorite.genres

                let type = favorite.type ?? ""
                let key = "\(mediaId)_\(type)"
                
                await MainActor.run {
                    let predicate = #Predicate<FavoriteModel> { $0.mediaIdTypeKey == key }
                    if let model = try? context.fetch(FetchDescriptor<FavoriteModel>(predicate: predicate)).first {
                        model.title = newTitle
                        model.posterUrl = newPosterUrl
                        model.rating = newRating
                        model.year = newYear
                        model.genresRaw = try? String(data: JSONEncoder().encode(newGenres), encoding: .utf8)
                        didChange = true
                    }
                }
            } catch {
                continue
            }
        }

        if didChange {
            await MainActor.run {
                try? context.save()
                reloadFromDb()
            }
        }
    }
}
