import Foundation
import SwiftData
import Combine

@MainActor
public final class FavoritesRepository: ObservableObject {
    public static let shared = FavoritesRepository()
    
    @Published public private(set) var favorites: [FavoriteDto] = []
    
    private var cancellables = Set<AnyCancellable>()
    
    private var context: ModelContext {
        return AppDatabase.shared.container.mainContext
    }

    public var currentUserId: String {
        guard let user = AuthRepository.shared.currentUser, !user.isAnonymous else {
            return "guest"
        }
        return user.id
    }

    private init() {
        // Подписываемся на смену пользователя в AuthRepository
        AuthRepository.shared.$currentUser
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleUserChanged()
            }
            .store(in: &cancellables)

        reloadFromDb()
        refreshMissingMetadataIfNeeded()
    }
    
    public func handleUserChanged() {
        reloadFromDb()
        
        let user = AuthRepository.shared.currentUser
        
        if AuthRepository.shared.isAuthenticated, let user = user {
            Task {
                // Загружаем удаленные избранные конкретного аккаунта из облака Firebase
                if let remoteFavorites = await CloudSyncService.shared.fetchRemoteFavorites(userId: user.id, idToken: user.idToken) {
                    await self.syncRemoteFavoritesToLocal(remoteFavorites, userId: user.id)
                }
            }
        }
    }
    
    public func reloadFromDb() {
        let activeUserId = currentUserId
        let predicate = #Predicate<FavoriteModel> { $0.userId == activeUserId }
        let descriptor = FetchDescriptor<FavoriteModel>(
            predicate: predicate,
            sortBy: [SortDescriptor(\FavoriteModel.addedAt, order: .reverse)]
        )
        
        let models = (try? context.fetch(descriptor)) ?? []
        
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
    
    public func getFavorites() -> [FavoriteDto] {
        return favorites
    }
    
    public func isFavorite(mediaId: String, mediaType: String) -> Bool {
        return favorites.contains { $0.mediaId == mediaId && $0.type == mediaType }
    }
    
    public func addToFavorites(mediaId: String, mediaType: String, title: String?, posterUrl: String?, rating: Double?, year: String? = nil, genres: [GenreDto]? = nil) {
        if !isFavorite(mediaId: mediaId, mediaType: mediaType) {
            let activeUserId = currentUserId
            let genresRaw = try? String(data: JSONEncoder().encode(genres), encoding: .utf8)
            let model = FavoriteModel(
                userId: activeUserId,
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
            
            // Если вошёл в аккаунт — пушим изменения в облако Firebase
            if AuthRepository.shared.isAuthenticated, let user = AuthRepository.shared.currentUser {
                let currentFavs = self.favorites
                Task {
                    await CloudSyncService.shared.pushRemoteFavorites(currentFavs, userId: user.id, idToken: user.idToken)
                }
            }
        }
    }
    
    public func removeFromFavorites(mediaId: String, mediaType: String) {
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(mediaId)_\(mediaType)"
        let predicate = #Predicate<FavoriteModel> { $0.userMediaIdTypeKey == compositeKey }
        if let model = try? context.fetch(FetchDescriptor<FavoriteModel>(predicate: predicate)).first {
            context.delete(model)
            try? context.save()
            reloadFromDb()
            
            // Если вошёл в аккаунт — пушим изменения в облако Firebase
            if AuthRepository.shared.isAuthenticated, let user = AuthRepository.shared.currentUser {
                let currentFavs = self.favorites
                Task {
                    await CloudSyncService.shared.pushRemoteFavorites(currentFavs, userId: user.id, idToken: user.idToken)
                }
            }
        }
    }

    private func syncRemoteFavoritesToLocal(_ remoteFavorites: [FavoriteDto], userId: String) async {
        let predicate = #Predicate<FavoriteModel> { $0.userId == userId }
        if let existing = try? context.fetch(FetchDescriptor<FavoriteModel>(predicate: predicate)) {
            for model in existing {
                context.delete(model)
            }
        }
        
        for dto in remoteFavorites {
            let mediaId = dto.mediaId ?? ""
            let type = dto.type ?? ""
            if !mediaId.isEmpty, !type.isEmpty {
                let genresRaw = try? String(data: JSONEncoder().encode(dto.genres), encoding: .utf8)
                let model = FavoriteModel(
                    userId: userId,
                    mediaId: mediaId,
                    type: type,
                    title: dto.title,
                    posterUrl: dto.posterUrl,
                    rating: dto.rating,
                    year: dto.year,
                    genresRaw: genresRaw
                )
                context.insert(model)
            }
        }
        
        try? context.save()
        reloadFromDb()
    }

    public func refreshMissingMetadataIfNeeded() {
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
                let activeUserId = currentUserId
                let key = "\(activeUserId)_\(mediaId)_\(type)"
                
                await MainActor.run {
                    let predicate = #Predicate<FavoriteModel> { $0.userMediaIdTypeKey == key }
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
