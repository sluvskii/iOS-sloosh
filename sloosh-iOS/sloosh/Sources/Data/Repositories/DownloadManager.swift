import Foundation
import Combine
import UIKit

enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed
}

struct DownloadItem: Identifiable, Codable, Equatable {
    let id: String // "kp_{kpId}" (movies) or "kp_{kpId}_s{season}_e{episode}" (shows)
    let kpId: Int
    let title: String
    let season: Int?
    let episode: Int?
    let episodeTitle: String?
    let mediaType: String // "movie" or "tv"
    let posterUrl: String?
    let localDirectory: String // Relative to Documents directory
    let localPlayableFileName: String // "local.m3u8"
    var progress: Double // 0.0 to 1.0
    var status: DownloadStatus
    var downloadedBytes: Int64? // Currently represents downloaded segment count
    var totalBytes: Int64? // Currently represents total segment count
    let translationName: String?
    let iframeUrl: String
    let addedAt: Date
    var errorMessage: String?
    
    var localPlayableUrl: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(localDirectory).appendingPathComponent(localPlayableFileName)
    }
    
    var localPosterUrl: URL? {
        guard posterUrl != nil else { return nil }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent(localDirectory).appendingPathComponent("poster.jpg")
    }
    
    var sizeString: String {
        guard let downloaded = downloadedBytes, let total = totalBytes, total > 0 else { return "" }
        let totalMB = Double(total) * 1.5
        if status == .completed {
            return String(format: "%.0f МБ", totalMB)
        } else {
            let downloadedMB = Double(downloaded) * 1.5
            return String(format: "%.0f / %.0f МБ", downloadedMB, totalMB)
        }
    }
}

@MainActor
final class DownloadManager: ObservableObject {
    static let shared = DownloadManager()
    
    @Published private(set) var downloads: [DownloadItem] = []
    
    private let saveKey = "sloosh_downloads"
    private var activeTasks: [String: Task<Void, Never>] = [:]
    private var backgroundTaskIds: [String: UIBackgroundTaskIdentifier] = [:]
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        let delegate = TrustAllSessionDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    
    private init() {
        loadDownloads()
    }
    
    private func loadDownloads() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let list = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            // If any item was downloading or pending when app terminated, set it to failed with message
            self.downloads = list.map { item in
                if item.status == .downloading || item.status == .pending {
                    var updated = item
                    updated.status = .failed
                    updated.errorMessage = "Загрузка прервана"
                    return updated
                }
                return item
            }
        }
    }
    
    private func saveDownloads() {
        if let data = try? JSONEncoder().encode(downloads) {
            UserDefaults.standard.set(data, forKey: saveKey)
        }
    }
    
    func isDownloaded(kpId: Int, season: Int?, episode: Int?) -> Bool {
        let itemId = makeItemId(kpId: kpId, season: season, episode: episode)
        return downloads.first(where: { $0.id == itemId })?.status == .completed
    }
    
    func getDownloadItem(kpId: Int, season: Int?, episode: Int?) -> DownloadItem? {
        let itemId = makeItemId(kpId: kpId, season: season, episode: episode)
        return downloads.first(where: { $0.id == itemId })
    }
    
    func startDownload(
        details: MediaDetailsDto,
        season: Int?,
        episode: Int?,
        translation: AllohaTranslation,
        preferredQuality: VideoQualityPreference
    ) {
        let kpId = details.externalIds?.kp ?? 0
        guard kpId > 0 else { return }
        
        let itemId = makeItemId(kpId: kpId, season: season, episode: episode)
        
        // Remove existing task if running
        activeTasks[itemId]?.cancel()
        activeTasks.removeValue(forKey: itemId)
        
        let localDir: String
        let epTitle: String?
        if let s = season, let e = episode {
            localDir = "downloads/shows/\(kpId)/s\(s)_e\(e)"
            epTitle = "Сезон \(s), Серия \(e)"
        } else {
            localDir = "downloads/movies/\(kpId)"
            epTitle = nil
        }
        
        // Check if item already exists in downloads list
        var item: DownloadItem
        if let existingIdx = downloads.firstIndex(where: { $0.id == itemId }) {
            downloads[existingIdx].status = .pending
            downloads[existingIdx].progress = 0.0
            downloads[existingIdx].errorMessage = nil
            downloads[existingIdx].downloadedBytes = 0
            downloads[existingIdx].totalBytes = 0
            item = downloads[existingIdx]
        } else {
            item = DownloadItem(
                id: itemId,
                kpId: kpId,
                title: details.title ?? details.name ?? "Без названия",
                season: season,
                episode: episode,
                episodeTitle: epTitle,
                mediaType: details.type ?? "movie",
                posterUrl: details.posterUrl ?? details.backdropUrl,
                localDirectory: localDir,
                localPlayableFileName: "local.m3u8",
                progress: 0.0,
                status: .pending,
                downloadedBytes: 0,
                totalBytes: 0,
                translationName: translation.name,
                iframeUrl: translation.iframeUrl,
                addedAt: Date()
            )
            downloads.append(item)
        }
        saveDownloads()
        
        // Start background execution assertion
        let bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "SlooshDownload_\(itemId)") { [weak self] in
            Task { @MainActor [weak self] in
                self?.pauseDownload(id: itemId)
            }
        }
        backgroundTaskIds[itemId] = bgTaskId
        
        // Spawn async download task
        let downloadTask = Task {
            await self.performDownload(itemId: itemId, item: item, preferredQuality: preferredQuality)
        }
        activeTasks[itemId] = downloadTask
    }
    
    func pauseDownload(id: String) {
        if let task = activeTasks[id] {
            task.cancel()
            activeTasks.removeValue(forKey: id)
        }
        
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            downloads[idx].status = .failed
            downloads[idx].errorMessage = "Приостановлено"
            saveDownloads()
        }
        
        endBackgroundTask(for: id)
    }
    
    func deleteDownload(id: String) {
        pauseDownload(id: id)
        
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            let item = downloads[idx]
            downloads.remove(at: idx)
            saveDownloads()
            
            // Delete folder on disk
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let taskDir = docs.appendingPathComponent(item.localDirectory)
            try? FileManager.default.removeItem(at: taskDir)
        }
    }
    
    private func endBackgroundTask(for id: String) {
        if let bgTaskId = backgroundTaskIds[id], bgTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(bgTaskId)
            backgroundTaskIds.removeValue(forKey: id)
        }
    }
    
    private func makeItemId(kpId: Int, season: Int?, episode: Int?) -> String {
        if let s = season, let e = episode {
            return "kp_\(kpId)_s\(s)_e\(e)"
        }
        return "kp_\(kpId)"
    }
    
    private func updateItem(id: String, block: (inout DownloadItem) -> Void) {
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            block(&downloads[idx])
            saveDownloads()
        }
    }
    
    private func performDownload(itemId: String, item: DownloadItem, preferredQuality: VideoQualityPreference) async {
        updateItem(id: itemId) {
            $0.status = .downloading
            $0.errorMessage = nil
        }
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let taskDir = docs.appendingPathComponent(item.localDirectory)
        try? FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)
        
        // 1. Download Poster
        if let posterStr = item.posterUrl, let posterUrl = URL(string: posterStr) {
            do {
                let posterData = try await downloadData(from: posterUrl, headers: [:])
                try posterData.write(to: taskDir.appendingPathComponent("poster.jpg"))
            } catch {
                print("Failed to download poster: \(error)")
            }
        }
        
        // 2. Resolve iframe
        let resolver = await MainActor.run { AllohaRuntimeResolver() }
        let resolved: [String: Any]
        do {
            resolved = try await resolver.resolve(iframeUrl: item.iframeUrl)
        } catch {
            await finishWithError(id: itemId, message: "Не удалось получить источник: \(error.localizedDescription)")
            return
        }
        
        if Task.isCancelled { return }
        
        // 3. Extract stream URL matching translation and quality
        let audioVariants = (resolved["audioVariants"] as? [[String: Any]]) ?? []
        var streamUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let headers = (resolved["headers"] as? [String: String]) ?? [:]
        
        if let targetVoice = item.translationName, !targetVoice.isEmpty {
            let exactMatch = audioVariants.first(where: { variant in
                let title = variant["title"] as? String
                return allohaTranslationNamesMatch(title, targetVoice, exactOnly: true)
            })
            let match = exactMatch ?? audioVariants.first(where: { variant in
                let title = variant["title"] as? String
                return allohaTranslationNamesMatch(title, targetVoice, exactOnly: false)
            })
            if let validMatch = match, let matchedUrl = validMatch["url"] as? String, !matchedUrl.isEmpty {
                streamUrlString = matchedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        guard let masterPlaylistUrl = URL(string: streamUrlString) else {
            await finishWithError(id: itemId, message: "Не удалось получить ссылку на поток")
            return
        }
        
        // 4. Fetch Master Playlist or Single Media Playlist
        let playlistData: Data
        do {
            playlistData = try await downloadData(from: masterPlaylistUrl, headers: headers)
        } catch {
            await finishWithError(id: itemId, message: "Не удалось скачать плейлист")
            return
        }
        
        guard let playlistContent = String(data: playlistData, encoding: .utf8) else {
            await finishWithError(id: itemId, message: "Не удалось прочитать плейлист")
            return
        }
        
        var mediaPlaylistUrl = masterPlaylistUrl
        if playlistContent.contains("#EXT-X-STREAM-INF") {
            // It is a Master Playlist, choose the best sub-playlist according to quality preference
            if let chosenUrl = chooseMediaPlaylistUrl(from: playlistContent, baseUrl: masterPlaylistUrl, preferredQuality: preferredQuality) {
                mediaPlaylistUrl = chosenUrl
            } else {
                await finishWithError(id: itemId, message: "Не удалось выбрать качество")
                return
            }
        }
        
        // 5. Fetch Media Playlist
        let mediaPlaylistData: Data
        do {
            mediaPlaylistData = try await downloadData(from: mediaPlaylistUrl, headers: headers)
        } catch {
            await finishWithError(id: itemId, message: "Ошибка скачивания медиа-плейлиста")
            return
        }
        
        guard let mediaPlaylistContent = String(data: mediaPlaylistData, encoding: .utf8) else {
            await finishWithError(id: itemId, message: "Ошибка декодирования медиа-плейлиста")
            return
        }
        
        // 6. Parse segments and key URLs
        let lines = mediaPlaylistContent.components(separatedBy: .newlines)
        var segmentUrls: [URL] = []
        var segmentLines: [Int] = []
        
        var keyUrl: URL? = nil
        var keyLineIndex: Int? = nil
        
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("#") {
                if trimmed.contains("URI=") {
                    // Check for encryption key
                    if let range = trimmed.range(of: "URI=\"([^\"]+)\"", options: .regularExpression) {
                        let match = String(trimmed[range])
                        let uriString = match.replacingOccurrences(of: "URI=\"", with: "").replacingOccurrences(of: "\"", with: "")
                        if !uriString.isEmpty && uriString != "none" {
                            if uriString.hasPrefix("http") {
                                keyUrl = URL(string: uriString)
                            } else {
                                keyUrl = URL(string: uriString, relativeTo: mediaPlaylistUrl)
                            }
                            keyLineIndex = i
                        }
                    }
                }
            } else {
                // Segment URL
                let url: URL
                if trimmed.hasPrefix("http") {
                    url = URL(string: trimmed)!
                } else {
                    url = URL(string: trimmed, relativeTo: mediaPlaylistUrl)!
                }
                segmentUrls.append(url)
                segmentLines.append(i)
            }
        }
        
        if segmentUrls.isEmpty {
            await finishWithError(id: itemId, message: "Не найдено сегментов для скачивания")
            return
        }
        
        // Update total segment counts
        updateItem(id: itemId) {
            $0.totalBytes = Int64(segmentUrls.count)
        }
        
        // 7. Download Key if present
        if let keyUrl {
            do {
                let keyData = try await downloadData(from: keyUrl, headers: headers)
                try keyData.write(to: taskDir.appendingPathComponent("key.bin"))
            } catch {
                await finishWithError(id: itemId, message: "Ошибка скачивания ключа дешифрования")
                return
            }
        }
        
        if Task.isCancelled { return }
        
        // 8. Download Segments concurrently
        let concurrencyLimit = 4
        var downloadedSegments = 0
        let totalSegments = segmentUrls.count
        
        do {
            try await withThrowingTaskGroup(of: (Int, Data).self) { group in
                var index = 0
                
                // Add initial batch
                while index < min(concurrencyLimit, totalSegments) {
                    if Task.isCancelled { throw CancellationError() }
                    let segmentIndex = index
                    let url = segmentUrls[segmentIndex]
                    group.addTask {
                        let data = try await self.downloadData(from: url, headers: headers)
                        return (segmentIndex, data)
                    }
                    index += 1
                }
                
                // Process completion
                while let result = try await group.next() {
                    if Task.isCancelled { throw CancellationError() }
                    let (segmentIndex, data) = result
                    
                    let segmentFileName = "segment_\(segmentIndex).ts"
                    let fileUrl = taskDir.appendingPathComponent(segmentFileName)
                    try data.write(to: fileUrl)
                    
                    downloadedSegments += 1
                    let progress = Double(downloadedSegments) / Double(totalSegments)
                    
                    updateItem(id: itemId) {
                        $0.progress = progress
                        $0.downloadedBytes = Int64(downloadedSegments)
                    }
                    
                    // Add next segment task
                    if index < totalSegments {
                        let nextIndex = index
                        let nextUrl = segmentUrls[nextIndex]
                        group.addTask {
                            let data = try await self.downloadData(from: nextUrl, headers: headers)
                            return (nextIndex, data)
                        }
                        index += 1
                    }
                }
            }
        } catch is CancellationError {
            return
        } catch {
            await finishWithError(id: itemId, message: "Ошибка скачивания сегментов: \(error.localizedDescription)")
            return
        }
        
        if Task.isCancelled { return }
        
        // 9. Rewrite and save local .m3u8 playlist file
        var rewrittenLines = lines
        
        // Rewrite key line if present
        if let keyLineIndex, let originalKeyLine = rewrittenLines[safe: keyLineIndex] {
            if let range = originalKeyLine.range(of: "URI=\"([^\"]+)\"", options: .regularExpression) {
                var modifiedLine = originalKeyLine
                modifiedLine.replaceSubrange(range, with: "URI=\"key.bin\"")
                rewrittenLines[keyLineIndex] = modifiedLine
            }
        }
        
        // Rewrite segment lines to local relative filenames
        for (segIdx, lineIdx) in segmentLines.enumerated() {
            rewrittenLines[lineIdx] = "segment_\(segIdx).ts"
        }
        
        let rewrittenContent = rewrittenLines.joined(separator: "\n")
        do {
            try rewrittenContent.write(to: taskDir.appendingPathComponent(item.localPlayableFileName), atomically: true, encoding: .utf8)
        } catch {
            await finishWithError(id: itemId, message: "Не удалось сохранить локальный плейлист")
            return
        }
        
        // 10. Completed!
        updateItem(id: itemId) {
            $0.progress = 1.0
            $0.status = .completed
        }
        
        endBackgroundTask(for: itemId)
        activeTasks.removeValue(forKey: itemId)
    }
    
    private func finishWithError(id: String, message: String) async {
        updateItem(id: id) {
            $0.status = .failed
            $0.errorMessage = message
        }
        endBackgroundTask(for: id)
        activeTasks.removeValue(forKey: id)
    }
    
    private func downloadData(from url: URL, headers: [String: String], retries: Int = 3) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<retries {
            if Task.isCancelled { throw CancellationError() }
            do {
                var request = URLRequest(url: url)
                for (k, v) in headers {
                    request.setValue(v, forHTTPHeaderField: k)
                }
                if request.value(forHTTPHeaderField: "User-Agent") == nil {
                    request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
                }
                
                let (data, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    return data
                } else {
                    let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                    throw NSError(domain: "SlooshDownload", code: code, userInfo: [NSLocalizedDescriptionKey: "Сервер вернул код: \(code)"])
                }
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * Double(attempt + 1)))
            }
        }
        throw lastError ?? NSError(domain: "SlooshDownload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось загрузить данные"])
    }
    
    private func chooseMediaPlaylistUrl(from content: String, baseUrl: URL, preferredQuality: VideoQualityPreference) -> URL? {
        let lines = content.components(separatedBy: .newlines)
        var variants: [(url: URL, height: Int, bandwidth: Double)] = []
        
        var currentBandwidth: Double = 0
        var currentHeight: Int = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
                currentBandwidth = 0
                currentHeight = 0
                
                if let range = trimmed.range(of: "RESOLUTION=([^,\\s]+)", options: .regularExpression) {
                    let match = String(trimmed[range]).replacingOccurrences(of: "RESOLUTION=", with: "")
                    let components = match.components(separatedBy: "x")
                    if components.count == 2, let h = Int(components[1]) {
                        currentHeight = h
                    }
                }
                if let range = trimmed.range(of: "BANDWIDTH=([^,\\s]+)", options: .regularExpression) {
                    let match = String(trimmed[range]).replacingOccurrences(of: "BANDWIDTH=", with: "")
                    if let bw = Double(match) {
                        currentBandwidth = bw
                    }
                }
            } else if !trimmed.hasPrefix("#") {
                let variantUrl: URL
                if trimmed.hasPrefix("http") {
                    variantUrl = URL(string: trimmed)!
                } else {
                    variantUrl = URL(string: trimmed, relativeTo: baseUrl)!
                }
                variants.append((url: variantUrl, height: currentHeight, bandwidth: currentBandwidth))
            }
        }
        
        if variants.isEmpty { return nil }
        
        let targetHeight: Int
        switch preferredQuality {
        case .q1080: targetHeight = 1080
        case .q720: targetHeight = 720
        case .q480: targetHeight = 480
        case .q360: targetHeight = 360
        default: targetHeight = 1080
        }
        
        let sorted = variants.sorted { a, b in
            let diffA = abs(a.height - targetHeight)
            let diffB = abs(b.height - targetHeight)
            if diffA != diffB {
                return diffA < diffB
            }
            return a.bandwidth > b.bandwidth
        }
        
        return sorted.first?.url
    }
}

private extension Array {
    func element(at index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
    
    subscript(safe index: Int) -> Element? {
        element(at: index)
    }
}
