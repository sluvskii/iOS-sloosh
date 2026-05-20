import Foundation

@MainActor
final class SupportRepository: ObservableObject {
    static let shared = SupportRepository()

    private let cacheKey = "support_cache_items"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func getCached() -> [SupportItemDto]? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else {
            return nil
        }
        return try? decoder.decode([SupportItemDto].self, from: data)
    }

    func fetch() async throws -> [SupportItemDto] {
        let items = try await MoviesApi.shared.getSupportList()
        cache(items)
        return items
    }

    private func cache(_ items: [SupportItemDto]) {
        guard let data = try? encoder.encode(items) else {
            return
        }
        UserDefaults.standard.set(data, forKey: cacheKey)
    }
}
