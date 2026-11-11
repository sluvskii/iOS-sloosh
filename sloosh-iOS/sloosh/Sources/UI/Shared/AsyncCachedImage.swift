import SwiftUI
import UIKit

public final class ImageCache {
    public static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()

    /// Сеть для картинок: короткий таймаут ожидания ответа, чтобы при блокировке
    /// хостинга постеры не «висели» по минуте (системный таймаут по умолчанию — 60 с).
    /// timeoutIntervalForRequest — это простой между пакетами, поэтому медленная,
    /// но живая загрузка больших кадров не обрывается.
    public static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 40
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 6
        return URLSession(configuration: config)
    }()
    
    private init() {
        // Set maximum cost of 50 MB in memory to prevent memory pressure
        let limit = ProcessInfo.processInfo.isLowPowerModeEnabled ? 20 * 1024 * 1024 : 50 * 1024 * 1024
        cache.totalCostLimit = limit
        
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clear()
        }
    }
    
    public func image(forKey key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }
    
    public func insertImage(_ image: UIImage, forKey key: String) {
        // Estimate cost in bytes: width * height * 4 channels
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
    
    public func removeImage(forKey key: String) {
        cache.removeObject(forKey: key as NSString)
    }
    
    private let failedLock = NSLock()
    private var failures = ImageFailureBackoff()

    public func isFailed(url: String) -> Bool {
        failedLock.lock()
        defer { failedLock.unlock() }
        return failures.contains(url)
    }
    public func markFailed(url: String) {
        failedLock.lock()
        defer { failedLock.unlock() }
        failures.insert(url)
    }
    public func clear() {
        cache.removeAllObjects()
        failedLock.lock()
        failures.clear()
        failedLock.unlock()
    }

    public static func resolveEffectiveUrl(_ targetUrl: URL?) -> URL? {
        guard let original = targetUrl else { return nil }
        var str = original.absoluteString
        let base = MoviesApi.activeImagesBaseURL
        let isLowQuality = UserDefaults.standard.string(forKey: "posterQuality") == "low"
        
        // Rewrite legacy/hardcoded vercel URLs to active base URL dynamically
        if str.contains("api-sloosh.vercel.app") {
            str = str.replacingOccurrences(of: "https://api-sloosh.vercel.app", with: base)
                .replacingOccurrences(of: "http://api-sloosh.vercel.app", with: base)
        }
        
        // Proxy raw TMDB images through active base URL
        if str.contains("image.tmdb.org/t/p/") {
            str = str.replacingOccurrences(of: "https://image.tmdb.org/t/p/", with: "\(base)/api/v1/images/tmdb/")
                .replacingOccurrences(of: "http://image.tmdb.org/t/p/", with: "\(base)/api/v1/images/tmdb/")
        }

        // Apply quality size if URL routes through TMDB image proxy
        if str.contains("/api/v1/images/tmdb/") {
            let isBackdrop = str.contains("/original/") || str.contains("/w780/") || str.contains("/w1280/")
            let targetSize = isBackdrop ? (isLowQuality ? "w780" : "original") : (isLowQuality ? "w185" : "w500")
            let pattern = #"/api/v1/images/tmdb/(w\d+|original)/"#
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let range = NSRange(str.startIndex..<str.endIndex, in: str)
                str = regex.stringByReplacingMatches(in: str, options: [], range: range, withTemplate: "/api/v1/images/tmdb/\(targetSize)/")
            }
        }

        return URL(string: str) ?? original
    }

    public static func prefetch(urls: [URL]) {
        for rawUrl in urls {
            guard let url = resolveEffectiveUrl(rawUrl) else { continue }
            if shared.image(forKey: url.absoluteString) != nil {
                continue
            }
            
            Task.detached(priority: .userInitiated) {
                var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                
                if let cached = URLCache.shared.cachedResponse(for: request),
                   let img = UIImage(data: cached.data) {
                    let decoded = await img.byPreparingForDisplay() ?? img
                    shared.insertImage(decoded, forKey: url.absoluteString)
                    return
                }
                
                if let (data, resp) = try? await ImageCache.session.data(for: request),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let img = UIImage(data: data) {
                    let cachedResponse = CachedURLResponse(response: http, data: data)
                    URLCache.shared.storeCachedResponse(cachedResponse, for: request)
                    let decoded = await img.byPreparingForDisplay() ?? img
                    shared.insertImage(decoded, forKey: url.absoluteString)
                }
            }
        }
    }
}

public struct AsyncCachedImage<Placeholder: View, Content: View, Fallback: View>: View {
    public let url: URL?
    public let fallbackUrl: URL?
    public let cachePolicy: URLRequest.CachePolicy
    @ViewBuilder public let placeholder: () -> Placeholder
    @ViewBuilder public let content: (UIImage) -> Content
    @ViewBuilder public let fallback: () -> Fallback
    public var isExternalLoading: Binding<Bool>? = nil
    
    @State private var revision = 0

    public init(
        url: URL?,
        fallbackUrl: URL? = nil,
        cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad,
        isExternalLoading: Binding<Bool>? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder content: @escaping (UIImage) -> Content,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.url = url
        self.fallbackUrl = fallbackUrl
        self.cachePolicy = cachePolicy
        self.isExternalLoading = isExternalLoading
        self.placeholder = placeholder
        self.content = content
        self.fallback = fallback
        
    }

    public var body: some View {
        let identity = ImageRequestIdentity(primary: ImageCache.resolveEffectiveUrl(url),
                                            fallback: ImageCache.resolveEffectiveUrl(fallbackUrl),
                                            policy: cachePolicy.rawValue, revision: revision)
        CachedImageRequestView(identity: identity, cachePolicy: cachePolicy,
                               isExternalLoading: isExternalLoading,
                               placeholder: placeholder, content: content, fallback: fallback)
            .id(identity)
            .onReceive(NotificationCenter.default.publisher(for: .posterQualityDidChange)) { _ in revision += 1 }
            .onReceive(NotificationCenter.default.publisher(for: .useLogosInCatalogDidChange)) { _ in revision += 1 }
            .onReceive(NotificationCenter.default.publisher(for: .mediaArtworkOverridesDidChange)) { _ in revision += 1 }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in revision += 1 }
    }
}

/// Immutable request inputs + SwiftUI identity isolate each load. No detached
/// notification tasks can race a new cell/URL, and cancellation is checked after
/// every suspension before any image is cached or published.
private struct CachedImageRequestView<Placeholder: View, Content: View, Fallback: View>: View {
    let identity: ImageRequestIdentity
    let cachePolicy: URLRequest.CachePolicy
    let isExternalLoading: Binding<Bool>?
    let placeholder: () -> Placeholder
    let content: (UIImage) -> Content
    let fallback: () -> Fallback
    @State private var image: UIImage?
    @State private var isLoading = true

    init(identity: ImageRequestIdentity, cachePolicy: URLRequest.CachePolicy, isExternalLoading: Binding<Bool>?,
         placeholder: @escaping () -> Placeholder, content: @escaping (UIImage) -> Content, fallback: @escaping () -> Fallback) {
        self.identity = identity
        self.cachePolicy = cachePolicy
        self.isExternalLoading = isExternalLoading
        self.placeholder = placeholder
        self.content = content
        self.fallback = fallback
        let permitsMemory = cachePolicy == .returnCacheDataElseLoad || cachePolicy == .returnCacheDataDontLoad || cachePolicy == .useProtocolCachePolicy
        let cached = permitsMemory ? identity.primary.flatMap { ImageCache.shared.image(forKey: $0.absoluteString) } : nil
        _image = State(initialValue: cached)
        _isLoading = State(initialValue: cached == nil && (identity.primary != nil || identity.fallback != nil))
    }

    private var usesMemoryCache: Bool {
        cachePolicy == .returnCacheDataElseLoad || cachePolicy == .returnCacheDataDontLoad || cachePolicy == .useProtocolCachePolicy
    }
    private var current: UIImage? {
        if let image { return image }
        guard usesMemoryCache, let primary = identity.primary else { return nil }
        return ImageCache.shared.image(forKey: primary.absoluteString)
    }
    var body: some View {
        Group {
            if let image = current { content(image) }
            else if isLoading { placeholder() }
            else { fallback() }
        }
        .task(id: identity) { await load() }
        .onChange(of: isLoading, initial: true) { _, value in isExternalLoading?.wrappedValue = value }
    }

    private func decoded(_ data: Data) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let raw = UIImage(data: data) else { return nil }
            return await raw.byPreparingForDisplay() ?? raw
        }.value
    }

    private func load() async {
        for candidate in [identity.primary, identity.fallback].compactMap({ $0 }) {
            guard !Task.isCancelled else { return }
            let key = candidate.absoluteString
            if usesMemoryCache, let cached = ImageCache.shared.image(forKey: key) {
                image = cached; isLoading = false
                return
            }
            if ImageCache.shared.isFailed(url: key) { continue }
            var request = URLRequest(url: candidate, cachePolicy: cachePolicy)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            if cachePolicy == .returnCacheDataElseLoad || cachePolicy == .returnCacheDataDontLoad,
               let cached = URLCache.shared.cachedResponse(for: request), let prepared = await decoded(cached.data) {
                guard !Task.isCancelled else { return }
                ImageCache.shared.insertImage(prepared, forKey: key)
                image = prepared; isLoading = false
                return
            }
            do {
                let (data, response) = try await ImageCache.session.data(for: request)
                guard !Task.isCancelled else { return }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    if http.statusCode == 404 {
                        URLCache.shared.removeCachedResponse(for: request)
                        ImageCache.shared.markFailed(url: key)
                    }
                    continue
                }
                guard let prepared = await decoded(data), !Task.isCancelled else { continue }
                ImageCache.shared.insertImage(prepared, forKey: key)
                image = prepared; isLoading = false
                return
            } catch {
                guard !Task.isCancelled else { return }
            }
        }
        guard !Task.isCancelled else { return }
        image = nil; isLoading = false
    }
}

extension AsyncCachedImage where Fallback == Placeholder {
    public init(
        url: URL?,
        fallbackUrl: URL? = nil,
        cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad,
        isExternalLoading: Binding<Bool>? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder content: @escaping (UIImage) -> Content
    ) {
        self.init(
            url: url,
            fallbackUrl: fallbackUrl,
            cachePolicy: cachePolicy,
            isExternalLoading: isExternalLoading,
            placeholder: placeholder,
            content: content,
            fallback: placeholder
        )
    }

    public init(
        urlString: String?,
        fallbackUrlString: String? = nil,
        cachePolicy: URLRequest.CachePolicy = .returnCacheDataElseLoad,
        isExternalLoading: Binding<Bool>? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder content: @escaping (UIImage) -> Content
    ) {
        let u = urlString.flatMap { URL(string: $0) }
        let f = fallbackUrlString.flatMap { URL(string: $0) }
        self.init(
            url: u,
            fallbackUrl: f,
            cachePolicy: cachePolicy,
            isExternalLoading: isExternalLoading,
            placeholder: placeholder,
            content: content,
            fallback: placeholder
        )
    }
}
