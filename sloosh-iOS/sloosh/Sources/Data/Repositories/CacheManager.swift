import Foundation
import SwiftUI
import UIKit
import WebKit

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

    private nonisolated func isSystemDirectory(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        // Filter out OS-level GPU shader compilation archives and system snapshots
        if name.hasPrefix("com.apple.metal") ||
           name.hasPrefix("com.apple.dyld") ||
           name == "Snapshots" ||
           name.hasPrefix("com.apple.SplashBoard") {
            return true
        }
        return false
    }

    private nonisolated func computeDiskCacheSize() -> Int64 {
        let fm = FileManager.default
        var total: Int64 = 0

        // 1. Scan Library/Caches folder (excluding system Metal shader cache)
        if let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            if let items = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
                for item in items {
                    if !isSystemDirectory(item) {
                        total += directorySize(at: item)
                    }
                }
            }
        }

        // 2. Scan NSTemporaryDirectory()
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        if let items = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil) {
            for item in items {
                total += directorySize(at: item)
            }
        }

        // 3. Fallback to URLCache disk usage if larger
        let urlCacheUsage = Int64(URLCache.shared.currentDiskUsage)
        if urlCacheUsage > total {
            total = urlCacheUsage
        }

        return total
    }

    private nonisolated func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if !isDir.boolValue {
            if let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) {
                return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
            }
            return 0
        }

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

        // 2. Clear WebKit website data (Alloha iframe resolver cache)
        let dataStore = WKWebsiteDataStore.default()
        let dataTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        await dataStore.removeData(ofTypes: dataTypes, modifiedSince: .distantPast)

        // 3. Clear disk caches in Library/Caches (skipping system Metal shader caches)
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            if let cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
                if let items = try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
                    for item in items {
                        if !self.isSystemDirectory(item) {
                            try? fm.removeItem(at: item)
                        }
                    }
                }
                // Re-create necessary directories for MoviesRepository
                try? fm.createDirectory(at: cacheDir.appendingPathComponent("sloosh.mediadetails"), withIntermediateDirectories: true)
                try? fm.createDirectory(at: cacheDir.appendingPathComponent("sloosh.medialist"), withIntermediateDirectories: true)
            }

            // Also clear temporary directory
            let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            if let tmpItems = try? fm.contentsOfDirectory(at: tmpDir, includingPropertiesForKeys: nil) {
                for item in tmpItems {
                    try? fm.removeItem(at: item)
                }
            }
        }.value

        // 4. Reset repository session caches
        MoviesRepository.shared.clearMemoryCache()

        // 5. Update UI state smoothly
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

        // 6. Re-check in background
        calculateCacheSize()
    }
}
