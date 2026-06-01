import Foundation
import AVFoundation

/// Manages video quality selection and parsing for AVPlayer
final class CollapsAVQualityManager {
    
    // MARK: - Dependencies
    
    private weak var player: AVPlayer?
    
    // MARK: - State
    
    private(set) var currentQualityOptions: [CollapsAVQualityOption] = []
    private(set) var selectedQualityIndex: Int = 0
    private(set) var selectedQualityHeight: Int?
    private(set) var selectedQualityBitrate: Int?
    
    // MARK: - Initialization
    
    init(player: AVPlayer) {
        self.player = player
    }
    
    // MARK: - Public API
    
    /// Lists available quality options
    func listQualityOptions() -> [[String: Any]] {
        currentQualityOptions.map { $0.asDictionary() }
    }
    
    /// Selects a quality option by index
    func selectQuality(index: Int?) {
        guard let index,
              let option = currentQualityOptions.first(where: { $0.index == index }) else {
            player?.currentItem?.preferredPeakBitRate = 0
            selectedQualityIndex = 0
            selectedQualityHeight = nil
            selectedQualityBitrate = nil
            return
        }
        if let forcedUrl = option.url, !forcedUrl.isEmpty, !option.isAuto {
            player?.currentItem?.preferredPeakBitRate = option.isAuto ? 0 : option.bitrate
        } else {
            player?.currentItem?.preferredPeakBitRate = option.isAuto ? 0 : option.bitrate
        }
        selectedQualityIndex = option.index
        selectedQualityHeight = option.height
        selectedQualityBitrate = option.bitrate > 0 ? Int(option.bitrate) : nil
    }
    
    /// Refreshes quality options from HLS playlist
    func refreshQualityOptions(urlString: String, headers: [String: String]) async -> [[String: Any]] {
        currentQualityOptions = await Self.parseHlsQualityOptions(urlString: urlString, headers: headers)
        // Restore quality selection by height/bitrate
        if let savedHeight = selectedQualityHeight, let savedBitrate = selectedQualityBitrate {
            if let matched = currentQualityOptions.first(where: { $0.height == savedHeight && Int($0.bitrate) == savedBitrate }) {
                selectedQualityIndex = matched.index
            } else if let matched = currentQualityOptions.first(where: { $0.height == savedHeight }) {
                selectedQualityIndex = matched.index
            } else {
                selectedQualityIndex = 0
            }
        } else if !currentQualityOptions.contains(where: { $0.index == selectedQualityIndex }) {
            selectedQualityIndex = 0
        }
        return listQualityOptions()
    }
    
    /// Sets quality options directly (for Alloha)
    func setQualityOptions(_ options: [CollapsAVQualityOption]) {
        currentQualityOptions = options
    }
    
    /// Resets quality selection
    func resetQualitySelection() {
        selectedQualityIndex = 0
        selectedQualityHeight = nil
        selectedQualityBitrate = nil
    }
    
    /// Creates quality options for Alloha items
    func makeAllohaQualityOptions(for item: CollapsAVPlaylistItem, selectedAudioVariantIndex: Int) -> [CollapsAVQualityOption] {
        let rawOptions: [CollapsAVQualityOption]
        if !item.audioVariants.isEmpty,
           item.audioVariants.indices.contains(selectedAudioVariantIndex),
           !item.audioVariants[selectedAudioVariantIndex].qualityVariants.isEmpty {
            rawOptions = item.audioVariants[selectedAudioVariantIndex].qualityVariants
        } else {
            rawOptions = item.qualityVariants
        }

        let filtered = rawOptions
            .filter { option in
                let label = option.label.lowercased()
                let height = option.height ?? 0
                // Filter out AV1 codecs
                if label.contains("av1") || label.contains("av01") {
                    return false
                }
                // Filter out anything above 1080p — iOS can't decode AV1/1440p+
                if height > 1080 {
                    return false
                }
                return true
            }
            .sorted { lhs, rhs in
                let l = lhs.height ?? 0
                let r = rhs.height ?? 0
                if l == r { return lhs.bitrate > rhs.bitrate }
                return l > r
            }

        var result: [CollapsAVQualityOption] = [
            CollapsAVQualityOption(index: 0, bitrate: 0, height: nil, label: "Auto", isAuto: true, url: nil)
        ]
        for (offset, option) in filtered.enumerated() {
            result.append(
                CollapsAVQualityOption(
                    index: offset + 1,
                    bitrate: option.bitrate,
                    height: option.height,
                    label: option.label,
                    isAuto: false,
                    url: option.url
                )
            )
        }
        return result
    }
    
    /// Gets quality recovery candidates for fallback
    func qualityRecoveryCandidates(from options: [CollapsAVQualityOption]) -> [Int] {
        let nonAuto = options.filter { !$0.isAuto }
        guard !nonAuto.isEmpty else { return [] }

        let preferredMediumOrLow = nonAuto
            .filter { ($0.height ?? Int.max) <= 720 }
            .sorted { lhs, rhs in
                let l = lhs.height ?? 0
                let r = rhs.height ?? 0
                if l == r { return lhs.bitrate > rhs.bitrate }
                return l > r
            }

        let remaining = nonAuto
            .filter { candidate in
                !preferredMediumOrLow.contains(where: { $0.index == candidate.index })
            }
            .sorted { lhs, rhs in
                let l = lhs.height ?? 0
                let r = rhs.height ?? 0
                if l == r { return lhs.bitrate > rhs.bitrate }
                return l > r
            }

        return (preferredMediumOrLow + remaining).map(\.index)
    }
    
    // MARK: - Static Helper Methods
    
    /// Parses HLS quality options from a URL
    static func parseHlsQualityOptions(urlString: String, headers: [String: String]) async -> [CollapsAVQualityOption] {
        guard let url = URL(string: urlString) else {
            return [CollapsAVQualityOption(index: 0, bitrate: 0, height: nil, label: "Auto", isAuto: true, url: nil)]
        }
        
        do {
            let content = try await Self.fetchMaster(url: url, headers: headers)
            return Self.parseMasterPlaylist(content)
        } catch {
            return [CollapsAVQualityOption(index: 0, bitrate: 0, height: nil, label: "Auto", isAuto: true, url: nil)]
        }
    }
    
    /// Extracts height from quality label
    static func heightFromQualityLabel(_ label: String) -> Int? {
        let lowercased = label.lowercased()
        if lowercased.contains("2160") || lowercased.contains("4k") { return 2160 }
        if lowercased.contains("1440") { return 1440 }
        if lowercased.contains("1080") { return 1080 }
        if lowercased.contains("720") { return 720 }
        if lowercased.contains("480") { return 480 }
        if lowercased.contains("360") { return 360 }
        if lowercased.contains("240") { return 240 }
        return nil
    }
    
    // MARK: - Private Helper Methods
    
    private static func fetchMaster(url: URL, headers: [String: String]) async throws -> String {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "CollapsAVQualityManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode response"])
        }
        return content
    }
    
    private static func parseMasterPlaylist(_ content: String) -> [CollapsAVQualityOption] {
        var options: [CollapsAVQualityOption] = []
        var index = 0
        
        let lines = content.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            if line.hasPrefix("#EXT-X-STREAM-INF") {
                var bandwidth: Double = 0
                var resolution: String?
                var _: String?
                
                let parts = line.components(separatedBy: ",")
                for part in parts {
                    let trimmed = part.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("BANDWIDTH=") {
                        bandwidth = Double(trimmed.replacingOccurrences(of: "BANDWIDTH=", with: "")) ?? 0
                    } else if trimmed.hasPrefix("RESOLUTION=") {
                        resolution = trimmed.replacingOccurrences(of: "RESOLUTION=", with: "").replacingOccurrences(of: "\"", with: "")
                    } else if trimmed.hasPrefix("CODECS=") {
                        _ = trimmed.replacingOccurrences(of: "CODECS=", with: "").replacingOccurrences(of: "\"", with: "")
                    }
                }
                
                var height: Int?
                if let res = resolution {
                    let parts = res.components(separatedBy: "x")
                    if parts.count == 2, let h = Int(parts[1]) {
                        height = h
                    }
                }
                
                let label: String
                if let h = height {
                    label = "\(h)p"
                } else {
                    label = "Stream"
                }
                
                let url = i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespaces) : nil
                
                // Skip streams above 1080p (1440p+, 4K)
                if let h = height, h > 1080 {
                    continue
                }

                options.append(CollapsAVQualityOption(
                    index: index,
                    bitrate: bandwidth,
                    height: height,
                    label: label,
                    isAuto: false,
                    url: url
                ))
                index += 1
            }
        }
        
        if options.isEmpty {
            return [CollapsAVQualityOption(index: 0, bitrate: 0, height: nil, label: "Auto", isAuto: true, url: nil)]
        }
        
        return options
    }
}
