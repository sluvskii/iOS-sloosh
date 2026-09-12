import SwiftUI
import UIKit

public final class ImageCache {
    public static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    
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
    
    public func clear() {
        cache.removeAllObjects()
    }

    public static func resolveEffectiveUrl(_ targetUrl: URL?) -> URL? {
        guard let original = targetUrl else { return nil }
        let str = original.absoluteString
        if str.contains("image.tmdb.org/t/p/") {
            let proxied = str.replacingOccurrences(of: "https://image.tmdb.org/t/p/", with: "https://api-sloosh.vercel.app/api/v1/images/tmdb/")
                .replacingOccurrences(of: "http://image.tmdb.org/t/p/", with: "https://api-sloosh.vercel.app/api/v1/images/tmdb/")
            return URL(string: proxied) ?? original
        }
        return original
    }

    public static func prefetch(urls: [URL]) {
        for rawUrl in urls {
            guard let url = resolveEffectiveUrl(rawUrl) else { continue }
            if shared.image(forKey: url.absoluteString) != nil || shared.image(forKey: rawUrl.absoluteString) != nil {
                continue
            }
            
            Task.detached(priority: .utility) {
                var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                
                if let cached = URLCache.shared.cachedResponse(for: request),
                   let base = UIImage(data: cached.data) {
                    let img = await base.byPreparingForDisplay() ?? base
                    shared.insertImage(img, forKey: url.absoluteString)
                    shared.insertImage(img, forKey: rawUrl.absoluteString)
                    return
                }
                
                if let (data, resp) = try? await URLSession.shared.data(for: request),
                   let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let base = UIImage(data: data) {
                    let img = await base.byPreparingForDisplay() ?? base
                    shared.insertImage(img, forKey: url.absoluteString)
                    shared.insertImage(img, forKey: rawUrl.absoluteString)
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
    
    @State private var image: UIImage?
    @State private var isLoading: Bool = true
    @State private var hasError: Bool = false
    
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
        
        // Try synchronously loading from in-memory cache first to avoid flashing
        let effectiveUrl = ImageCache.resolveEffectiveUrl(url)
        var initialImage: UIImage? = nil
        if let url = url {
            if let cached = ImageCache.shared.image(forKey: url.absoluteString) {
                initialImage = cached
            } else if let effective = effectiveUrl, let cached = ImageCache.shared.image(forKey: effective.absoluteString) {
                initialImage = cached
            }
        }
        
        if let initialImage = initialImage {
            _image = State(initialValue: initialImage)
            _isLoading = State(initialValue: false)
            _hasError = State(initialValue: false)
        } else if url == nil {
            _image = State(initialValue: nil)
            _isLoading = State(initialValue: false)
            _hasError = State(initialValue: true)
        } else {
            _image = State(initialValue: nil)
            _isLoading = State(initialValue: true)
            _hasError = State(initialValue: false)
        }
    }
    
    public var body: some View {
        Group {
            if let image = image {
                content(image)
            } else if isLoading {
                placeholder()
            } else {
                fallback()
            }
        }
        .task(id: url) {
            await loadImage()
        }
        .onChange(of: isLoading, initial: true) { _, newValue in
            isExternalLoading?.wrappedValue = newValue
        }
    }

    private func loadImage() async {
        guard let rawUrl = url, let url = ImageCache.resolveEffectiveUrl(rawUrl) else {
            await loadFallbackImage()
            return
        }
        
        // Check in-memory cache again (e.g. if loaded while task was scheduled)
        if let cached = ImageCache.shared.image(forKey: url.absoluteString) ?? ImageCache.shared.image(forKey: rawUrl.absoluteString) {
            await MainActor.run {
                self.image = cached
                self.isLoading = false
                self.hasError = false
            }
            return
        }
        
        var request = URLRequest(url: url, cachePolicy: cachePolicy)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        
        if let cachedResponse = URLCache.shared.cachedResponse(for: request) {
            let uiImg = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let base = UIImage(data: cachedResponse.data) else { return nil }
                return await base.byPreparingForDisplay() ?? base
            }.value
            
            if let uiImg = uiImg {
                ImageCache.shared.insertImage(uiImg, forKey: url.absoluteString)
                ImageCache.shared.insertImage(uiImg, forKey: rawUrl.absoluteString)
                await MainActor.run {
                    self.image = uiImg
                    self.isLoading = false
                    self.hasError = false
                }
                return
            }
        }
        
        await MainActor.run {
            self.isLoading = true
            self.hasError = false
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let isSuccessful: Bool
            if let httpResponse = response as? HTTPURLResponse {
                isSuccessful = httpResponse.statusCode == 200
            } else {
                isSuccessful = true // For file:// URLs
            }
            
            let uiImg = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                guard let base = UIImage(data: data) else { return nil }
                return await base.byPreparingForDisplay() ?? base
            }.value
            
            if isSuccessful, let uiImg {
                ImageCache.shared.insertImage(uiImg, forKey: url.absoluteString)
                ImageCache.shared.insertImage(uiImg, forKey: rawUrl.absoluteString)
                await MainActor.run {
                    self.image = uiImg
                    self.isLoading = false
                    self.hasError = false
                }
                return
            }
        } catch {
            if Task.isCancelled { return }
        }
        
        await loadFallbackImage()
    }
    
    private func loadFallbackImage() async {
        // Handle fallback URL if provided
        if let rawFallback = fallbackUrl, let fallbackUrl = ImageCache.resolveEffectiveUrl(rawFallback) {
            if let cachedFallback = ImageCache.shared.image(forKey: fallbackUrl.absoluteString) ?? ImageCache.shared.image(forKey: rawFallback.absoluteString) {
                await MainActor.run {
                    self.image = cachedFallback
                    self.isLoading = false
                    self.hasError = false
                }
                return
            }
            
            var fallbackRequest = URLRequest(url: fallbackUrl, cachePolicy: cachePolicy)
            fallbackRequest.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
            if let cachedResponse = URLCache.shared.cachedResponse(for: fallbackRequest) {
                let uiImg = await Task.detached(priority: .userInitiated) {
                    UIImage(data: cachedResponse.data)
                }.value
                
                if let uiImg = uiImg {
                    ImageCache.shared.insertImage(uiImg, forKey: fallbackUrl.absoluteString)
                    ImageCache.shared.insertImage(uiImg, forKey: rawFallback.absoluteString)
                    await MainActor.run {
                        self.image = uiImg
                        self.isLoading = false
                        self.hasError = false
                    }
                    return
                }
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(for: fallbackRequest)
                let isSuccessful: Bool
                if let httpResponse = response as? HTTPURLResponse {
                    isSuccessful = httpResponse.statusCode == 200
                } else {
                    isSuccessful = true
                }
                
                let uiImg = await Task.detached(priority: .userInitiated) {
                    UIImage(data: data)
                }.value
                
                if isSuccessful, let uiImg {
                    ImageCache.shared.insertImage(uiImg, forKey: fallbackUrl.absoluteString)
                    ImageCache.shared.insertImage(uiImg, forKey: rawFallback.absoluteString)
                    await MainActor.run {
                        self.image = uiImg
                        self.isLoading = false
                        self.hasError = false
                    }
                    return
                }
            } catch {
                if Task.isCancelled { return }
            }
        }
        
        await MainActor.run {
            self.image = nil
            self.isLoading = false
            self.hasError = true
        }
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
