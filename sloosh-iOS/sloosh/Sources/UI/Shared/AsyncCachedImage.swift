import SwiftUI
import UIKit

public final class ImageCache {
    public static let shared = ImageCache()
    private let cache = NSCache<NSString, UIImage>()
    
    private init() {
        // Set maximum cost of 50 MB in memory to prevent memory pressure
        cache.totalCostLimit = 50 * 1024 * 1024
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
    @State private var isLoading = false
    @State private var hasError = false
    
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
        if let url = url, let cached = ImageCache.shared.image(forKey: url.absoluteString) {
            _image = State(initialValue: cached)
            _isLoading = State(initialValue: false)
            _hasError = State(initialValue: false)
        } else if let url = url,
                  let cachedResponse = URLCache.shared.cachedResponse(for: URLRequest(url: url, cachePolicy: cachePolicy)),
                  let uiImg = UIImage(data: cachedResponse.data) {
            ImageCache.shared.insertImage(uiImg, forKey: url.absoluteString)
            _image = State(initialValue: uiImg)
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
        guard let url = url else {
            await loadFallbackImage()
            return
        }
        
        // Check in-memory cache again (e.g. if loaded while task was scheduled)
        if let cached = ImageCache.shared.image(forKey: url.absoluteString) {
            await MainActor.run {
                self.image = cached
                self.isLoading = false
                self.hasError = false
            }
            return
        }
        
        // Check URLCache
        let request = URLRequest(url: url, cachePolicy: cachePolicy)
        if let cachedResponse = URLCache.shared.cachedResponse(for: request),
           let uiImg = UIImage(data: cachedResponse.data) {
            ImageCache.shared.insertImage(uiImg, forKey: url.absoluteString)
            await MainActor.run {
                self.image = uiImg
                self.isLoading = false
                self.hasError = false
            }
            return
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
            
            if isSuccessful, let uiImg = UIImage(data: data) {
                ImageCache.shared.insertImage(uiImg, forKey: url.absoluteString)
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
        if let fallbackUrl = fallbackUrl {
            if let cachedFallback = ImageCache.shared.image(forKey: fallbackUrl.absoluteString) {
                await MainActor.run {
                    self.image = cachedFallback
                    self.isLoading = false
                    self.hasError = false
                }
                return
            }
            
            let fallbackRequest = URLRequest(url: fallbackUrl, cachePolicy: cachePolicy)
            if let cachedResponse = URLCache.shared.cachedResponse(for: fallbackRequest),
               let uiImg = UIImage(data: cachedResponse.data) {
                ImageCache.shared.insertImage(uiImg, forKey: fallbackUrl.absoluteString)
                await MainActor.run {
                    self.image = uiImg
                    self.isLoading = false
                    self.hasError = false
                }
                return
            }
            
            do {
                let (data, response) = try await URLSession.shared.data(for: fallbackRequest)
                let isSuccessful: Bool
                if let httpResponse = response as? HTTPURLResponse {
                    isSuccessful = httpResponse.statusCode == 200
                } else {
                    isSuccessful = true // For file:// URLs
                }
                
                if isSuccessful, let uiImg = UIImage(data: data) {
                    ImageCache.shared.insertImage(uiImg, forKey: fallbackUrl.absoluteString)
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
