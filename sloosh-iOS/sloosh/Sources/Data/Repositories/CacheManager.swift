import Foundation
import SwiftUI
import UIKit

@MainActor
public final class CacheManager: ObservableObject {
    public static let shared = CacheManager()

    @Published public private(set) var formattedCacheSize: String = "..."
    @Published public private(set) var cacheSizeBytes: Int64 = 0
    @Published public private(set) var isClearing: Bool = false

    public var isCacheEmpty: Bool {
        cacheSizeBytes < 1024
    }

    private init() {
        calculateCacheSize()
    }

    public func calculateCacheSize() {
        Task.detached(priority: .utility) {
            let size = self.computeDiskCacheSize()
            let formatted = self.formatBytes(size)
            await MainActor.run {
                self.cacheSizeBytes = size
                self.formattedCacheSize = formatted
            }
        }
    }

    private nonisolated func computeDiskCacheSize() -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0

        // 1. Scan Library/Caches folder
        if let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            total += directorySize(at: cacheDir)
        }

        // 2. URLCache current disk usage as fallback
        let urlCacheUsage = Int64(URLCache.shared.currentDiskUsage)
        if urlCacheUsage > total {
            total = urlCacheUsage
        }

        return total
    }

    private nonisolated func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return 0 }

        var size: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let resourceValues = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else { continue }
            let fileSize = resourceValues.totalFileAllocatedSize ?? resourceValues.fileSize ?? 0
            size += Int64(fileSize)
        }
        return size
    }

    private nonisolated func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return "0 КБ"
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    public func clearCache() async {
        isClearing = true
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        // 1. Clear in-memory caches
        ImageCache.shared.clear()
        MoviesRepository.shared.clearMemoryCache()
        URLCache.shared.removeAllCachedResponses()

        // 2. Clear disk caches in Library/Caches
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            if let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
                if let items = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
                    for item in items {
                        try? fm.removeItem(at: item)
                    }
                }
                // Re-create necessary directories for MoviesRepository
                try? fm.createDirectory(at: cacheDir.appendingPathComponent("sloosh.mediadetails"), withIntermediateDirectories: true)
                try? fm.createDirectory(at: cacheDir.appendingPathComponent("sloosh.medialist"), withIntermediateDirectories: true)
            }
        }.value

        // 3. Reset repository session caches
        MoviesRepository.shared.clearMemoryCache()

        // 4. Update UI state smoothly
        withAnimation(.easeInOut(duration: 0.25)) {
            self.cacheSizeBytes = 0
            self.formattedCacheSize = "0 КБ"
        }

        try? await Task.sleep(for: .milliseconds(300))
        isClearing = false

        generator.notificationOccurred(.success)
        ToastManager.shared.show(
            title: "Кэш очищен",
            icon: "checkmark.circle.fill",
            iconColor: Color.slooshAccent,
            duration: 2.0
        )

        // 5. Re-check in background
        calculateCacheSize()
    }
}
