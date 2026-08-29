import Foundation
import Combine
import UIKit

enum DownloadStatus: String, Codable {
    case pending
    case downloading
    case completed
    case failed
    case paused
}

struct DownloadItem: Identifiable, Codable, Equatable {
    let id: String
    let kpId: Int
    let title: String
    let season: Int?
    let episode: Int?
    let episodeTitle: String?
    let mediaType: String
    let posterUrl: String?
    let localDirectory: String
    let localPlayableFileName: String
    var progress: Double
    var status: DownloadStatus
    var downloadedBytes: Int64?
    var totalBytes: Int64?
    let translationName: String?
    let iframeUrl: String
    var preferredQuality: VideoQualityPreference
    let addedAt: Date
    var errorMessage: String?

    // MARK: - Custom Codable for backward compatibility
    // preferredQuality was added later, so existing JSON may not have it.
    enum CodingKeys: String, CodingKey {
        case id, kpId, title, season, episode, episodeTitle, mediaType, posterUrl
        case localDirectory, localPlayableFileName, progress, status
        case downloadedBytes, totalBytes, translationName, iframeUrl
        case preferredQuality, addedAt, errorMessage
    }

    init(id: String, kpId: Int, title: String, season: Int?, episode: Int?, episodeTitle: String?, mediaType: String, posterUrl: String?, localDirectory: String, localPlayableFileName: String, progress: Double, status: DownloadStatus, downloadedBytes: Int64?, totalBytes: Int64?, translationName: String?, iframeUrl: String, preferredQuality: VideoQualityPreference = .q1080, addedAt: Date) {
        self.id = id; self.kpId = kpId; self.title = title; self.season = season; self.episode = episode
        self.episodeTitle = episodeTitle; self.mediaType = mediaType; self.posterUrl = posterUrl
        self.localDirectory = localDirectory; self.localPlayableFileName = localPlayableFileName
        self.progress = progress; self.status = status; self.downloadedBytes = downloadedBytes; self.totalBytes = totalBytes
        self.translationName = translationName; self.iframeUrl = iframeUrl
        self.preferredQuality = preferredQuality; self.addedAt = addedAt; self.errorMessage = nil
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kpId = try container.decode(Int.self, forKey: .kpId)
        title = try container.decode(String.self, forKey: .title)
        season = try container.decodeIfPresent(Int.self, forKey: .season)
        episode = try container.decodeIfPresent(Int.self, forKey: .episode)
        episodeTitle = try container.decodeIfPresent(String.self, forKey: .episodeTitle)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        posterUrl = try container.decodeIfPresent(String.self, forKey: .posterUrl)
        localDirectory = try container.decode(String.self, forKey: .localDirectory)
        localPlayableFileName = try container.decode(String.self, forKey: .localPlayableFileName)
        progress = try container.decode(Double.self, forKey: .progress)
        status = try container.decode(DownloadStatus.self, forKey: .status)
        downloadedBytes = try container.decodeIfPresent(Int64.self, forKey: .downloadedBytes)
        totalBytes = try container.decodeIfPresent(Int64.self, forKey: .totalBytes)
        translationName = try container.decodeIfPresent(String.self, forKey: .translationName)
        iframeUrl = try container.decode(String.self, forKey: .iframeUrl)
        // Backward compatibility: field may not exist in older saved files
        preferredQuality = try container.decodeIfPresent(VideoQualityPreference.self, forKey: .preferredQuality) ?? .q1080
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        errorMessage = try container.decodeIfPresent(String.self, forKey: .errorMessage)
    }
    
    var localPlayableUrl: URL? {
        let relative = "\(localDirectory)/\(localPlayableFileName)"
        guard let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else { return nil }
        return URL(string: "http://127.0.0.1:8181/local/\(encoded)")
    }
    
    var localPosterUrl: URL? {
        guard posterUrl != nil else { return nil }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(localDirectory).appendingPathComponent("poster.jpg")
    }
    
    var sizeString: String {
        guard let downloaded = downloadedBytes, let total = totalBytes, total > 0 else { return "" }
        let totalMB = Double(total) * 1.5
        
        func formatMB(_ mb: Double) -> String {
            if mb >= 1024 {
                return String(format: "%.2f ГБ", mb / 1024.0)
            } else {
                return String(format: "%.0f МБ", mb)
            }
        }
        
        if status == .completed {
            return formatMB(totalMB)
        } else {
            let downloadedMB = Double(downloaded) * 1.5
            return "\(formatMB(downloadedMB)) / \(formatMB(totalMB))"
        }
    }
}

@MainActor
final class DownloadManager: NSObject, ObservableObject, URLSessionDownloadDelegate, URLSessionTaskDelegate {
    static let shared = DownloadManager()
    
    @Published private(set) var downloads: [DownloadItem] = []
    
    private let saveKey = "sloosh_downloads"
    private let dataStore = JSONDataStore<[DownloadItem]>(fileName: "downloads")
    
    private var session: URLSession!
    private var activeManifests: [String: DownloadManifest] = [:]
    private var downloadedSegmentsCache: [String: Set<Int>] = [:]
    
    // Concurrent segment limit
    private let concurrencyLimit = 4
    
    // Fallback URLSession for initial metadata parsing
    private lazy var defaultSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        let delegate = TrustAllSessionDelegate()
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }()
    
    var backgroundCompletionHandler: (() -> Void)?
    
    private override init() {
        super.init()
        
        let config = URLSessionConfiguration.background(withIdentifier: "com.sloosh.downloads.bg")
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        // iOS requires background session delegate to run on a background queue
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
        
        loadDownloads()
    }
    
    private func loadDownloads() {
        if let data = UserDefaults.standard.data(forKey: saveKey),
           let list = try? JSONDecoder().decode([DownloadItem].self, from: data) {
            self.downloads = processLoadedDownloads(list)
            dataStore.save(self.downloads)
            UserDefaults.standard.removeObject(forKey: saveKey)
        } else {
            let list = dataStore.load(defaultValue: [])
            self.downloads = processLoadedDownloads(list)
        }
        
        // Resume pending/downloading
        for item in downloads where item.status == .downloading || item.status == .pending {
            resumeDownload(id: item.id)
        }
    }
    
    private func processLoadedDownloads(_ list: [DownloadItem]) -> [DownloadItem] {
        return list.map { item in
            if item.status == .downloading || item.status == .pending {
                var updated = item
                updated.status = .paused // Mark as paused until resumed
                return updated
            }
            return item
        }
    }
    
    private func saveDownloads() {
        dataStore.save(downloads)
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
        let kpId = details.ids?.kp ?? 0
        guard kpId > 0 else { return }
        
        let itemId = makeItemId(kpId: kpId, season: season, episode: episode)
        
        let localDir: String
        let epTitle: String?
        if let s = season, let e = episode {
            localDir = "downloads/shows/\(kpId)/s\(s)_e\(e)"
            epTitle = "Сезон \(s), Серия \(e)"
        } else {
            localDir = "downloads/movies/\(kpId)"
            epTitle = nil
        }
        
        var item: DownloadItem
        if let existingIdx = downloads.firstIndex(where: { $0.id == itemId }) {
            downloads[existingIdx].status = .pending
            downloads[existingIdx].progress = 0.0
            downloads[existingIdx].errorMessage = nil
            item = downloads[existingIdx]
        } else {
            item = DownloadItem(
                id: itemId,
                kpId: kpId,
                title: details.title ?? details.originalTitle ?? "Без названия",
                season: season,
                episode: episode,
                episodeTitle: epTitle,
                mediaType: details.type ?? "movie",
                posterUrl: details.poster ?? details.backdrop,
                localDirectory: localDir,
                localPlayableFileName: "local.m3u8",
                progress: 0.0,
                status: .pending,
                downloadedBytes: 0,
                totalBytes: 0,
                translationName: translation.name,
                iframeUrl: translation.iframeUrl,
                preferredQuality: preferredQuality,
                addedAt: Date()
            )
            downloads.append(item)
        }
        
        ToastManager.shared.show(
            title: "Загрузка началась",
            subtitle: "Скачивание «\(item.title)» добавлено в очередь",
            icon: "arrow.down.circle.fill"
        )
        
        saveDownloads()
        
        Task {
            await prepareAndEnqueue(itemId: itemId, item: item, preferredQuality: preferredQuality)
        }
    }
    
    func resumeDownload(id: String) {
        guard let item = downloads.first(where: { $0.id == id }) else { return }
        updateItem(id: id) { $0.status = .pending; $0.errorMessage = nil }
        
        ToastManager.shared.show(
            title: "Загрузка возобновлена",
            subtitle: "Скачивание «\(item.title)» продолжено",
            icon: "play.circle.fill"
        )
        
        Task {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let taskDir = docs.appendingPathComponent(item.localDirectory)
            let manifestUrl = taskDir.appendingPathComponent("manifest.json")
            
            if FileManager.default.fileExists(atPath: manifestUrl.path) {
                if let data = try? Data(contentsOf: manifestUrl),
                   let manifest = try? JSONDecoder().decode(DownloadManifest.self, from: data) {
                    self.activeManifests[id] = manifest
                    await self.enqueueNextBatch(for: id)
                    return
                }
            }
            await prepareAndEnqueue(itemId: id, item: item, preferredQuality: item.preferredQuality)
        }
    }
    
    func pauseDownload(id: String, silent: Bool = false) {
        updateItem(id: id) {
            $0.status = .paused
            $0.errorMessage = "Приостановлено"
        }
        
        if !silent {
            ToastManager.shared.show(
                title: "Пауза",
                icon: "pause.circle.fill"
            )
        }
        
        session.getAllTasks { tasks in
            for task in tasks {
                if let desc = task.taskDescription, desc.starts(with: "\(id)|") {
                    task.cancel()
                }
            }
        }
    }
    
    func deleteDownload(id: String) {
        pauseDownload(id: id, silent: true)
        
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            let item = downloads[idx]
            
            ToastManager.shared.show(
                title: "Удалено",
                subtitle: item.title,
                icon: "trash.fill"
            )
            
            downloads.remove(at: idx)
            saveDownloads()
            
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let taskDir = docs.appendingPathComponent(item.localDirectory)
            try? FileManager.default.removeItem(at: taskDir)
        }
        activeManifests.removeValue(forKey: id)
    }
    
    private func makeItemId(kpId: Int, season: Int?, episode: Int?) -> String {
        if let s = season, let e = episode {
            return "kp_\(kpId)_s\(s)_e\(e)"
        }
        return "kp_\(kpId)"
    }
    
    private func updateItem(id: String, block: @escaping (inout DownloadItem) -> Void) {
        if let idx = downloads.firstIndex(where: { $0.id == id }) {
            block(&downloads[idx])
            saveDownloads()
        }
    }
    
    private func prepareAndEnqueue(itemId: String, item: DownloadItem, preferredQuality: VideoQualityPreference) async {
        updateItem(id: itemId) {
            $0.status = .downloading
            $0.errorMessage = nil
        }
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let taskDir = docs.appendingPathComponent(item.localDirectory)
        try? FileManager.default.createDirectory(at: taskDir, withIntermediateDirectories: true)
        
        if let posterStr = item.posterUrl, let posterUrl = URL(string: posterStr) {
            do {
                let posterData = try await downloadDataDirectly(from: posterUrl, headers: [:])
                try posterData.write(to: taskDir.appendingPathComponent("poster.jpg"))
            } catch { print("Poster failed") }
        }
        
        let resolver = AllohaRuntimeResolver()
        let resolved: [String: Any]
        do {
            resolved = try await resolver.resolve(iframeUrl: item.iframeUrl)
        } catch {
            await finishWithError(id: itemId, message: "Не удалось получить источник")
            return
        }
        
        var streamUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let audioVariants = (resolved["audioVariants"] as? [[String: Any]]) ?? []
        if let matchingVariant = audioVariants.first(where: { variant in
            let title = (variant["title"] as? String) ?? ""
            return allohaTranslationNamesMatch(title, item.translationName)
        }), let variantUrl = (matchingVariant["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !variantUrl.isEmpty {
            streamUrlString = variantUrl
        }
        let headers = (resolved["headers"] as? [String: String]) ?? [:]
        
        guard let masterPlaylistUrl = URL(string: streamUrlString) else {
            await finishWithError(id: itemId, message: "Не удалось получить ссылку на поток")
            return
        }
        
        let playlistData: Data
        do {
            playlistData = try await downloadDataDirectly(from: masterPlaylistUrl, headers: headers)
        } catch {
            await finishWithError(id: itemId, message: "Не удалось скачать плейлист")
            return
        }
        guard let playlistContent = String(data: playlistData, encoding: .utf8) else {
            await finishWithError(id: itemId, message: "Ошибка парсинга плейлиста")
            return
        }
        
        var mediaPlaylistUrl = masterPlaylistUrl
        if playlistContent.contains("#EXT-X-STREAM-INF") {
            if let chosenUrl = chooseMediaPlaylistUrl(from: playlistContent, baseUrl: masterPlaylistUrl, preferredQuality: preferredQuality) {
                mediaPlaylistUrl = chosenUrl
            } else {
                await finishWithError(id: itemId, message: "Не удалось выбрать качество")
                return
            }
        }
        
        let mediaPlaylistData: Data
        do {
            mediaPlaylistData = try await downloadDataDirectly(from: mediaPlaylistUrl, headers: headers)
        } catch {
            await finishWithError(id: itemId, message: "Ошибка скачивания медиа-плейлиста")
            return
        }
        guard let mediaPlaylistContent = String(data: mediaPlaylistData, encoding: .utf8) else {
            await finishWithError(id: itemId, message: "Ошибка декодирования медиа-плейлиста")
            return
        }
        
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
                    if let range = trimmed.range(of: "URI=\"([^\"]+)\"", options: .regularExpression) {
                        let match = String(trimmed[range])
                        let uriString = match.replacingOccurrences(of: "URI=\"", with: "").replacingOccurrences(of: "\"", with: "")
                        if !uriString.isEmpty && uriString != "none" {
                            keyUrl = uriString.hasPrefix("http") ? URL(string: uriString) : URL(string: uriString, relativeTo: mediaPlaylistUrl)
                            keyLineIndex = i
                        }
                    }
                }
            } else {
                let url = trimmed.hasPrefix("http") ? URL(string: trimmed) : URL(string: trimmed, relativeTo: mediaPlaylistUrl)
                if let url = url {
                    segmentUrls.append(url)
                    segmentLines.append(i)
                }
            }
        }
        
        if segmentUrls.isEmpty {
            await finishWithError(id: itemId, message: "Нет сегментов для скачивания")
            return
        }
        
        updateItem(id: itemId) { $0.totalBytes = Int64(segmentUrls.count) }
        
        if let keyUrl {
            do {
                let keyData = try await downloadDataDirectly(from: keyUrl, headers: headers)
                let keyFile = taskDir.appendingPathComponent("key.bin")
                try keyData.write(to: keyFile, options: [.atomic, .completeFileProtection])
                var rv = URLResourceValues()
                rv.isExcludedFromBackup = true
                var mutableKeyFile = keyFile
                try mutableKeyFile.setResourceValues(rv)
            } catch {
                await finishWithError(id: itemId, message: "Ошибка ключа")
                return
            }
        }
        
        var rewrittenLines = lines
        if let keyLineIndex, let originalKeyLine = rewrittenLines[safe: keyLineIndex] {
            if let range = originalKeyLine.range(of: "URI=\"([^\"]+)\"", options: .regularExpression) {
                var modifiedLine = originalKeyLine
                modifiedLine.replaceSubrange(range, with: "URI=\"key.bin\"")
                rewrittenLines[keyLineIndex] = modifiedLine
            }
        }
        for (segIdx, lineIdx) in segmentLines.enumerated() {
            rewrittenLines[lineIdx] = "segment_\(segIdx).ts"
        }
        let rewrittenContent = rewrittenLines.joined(separator: "\n")
        try? rewrittenContent.write(to: taskDir.appendingPathComponent(item.localPlayableFileName), atomically: true, encoding: .utf8)
        
        let manifest = DownloadManifest(itemId: itemId, segmentUrls: segmentUrls, headers: headers, keyUrl: keyUrl, localDirectory: item.localDirectory)
        activeManifests[itemId] = manifest
        let manifestUrl = taskDir.appendingPathComponent("manifest.json")
        if let md = try? JSONEncoder().encode(manifest) {
            try? md.write(to: manifestUrl)
        }
        
        await enqueueNextBatch(for: itemId)
    }
    
    private func enqueueNextBatch(for itemId: String) async {
        guard let item = downloads.first(where: { $0.id == itemId }), item.status == .downloading || item.status == .pending else { return }
        guard let manifest = activeManifests[itemId] else { return }
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let taskDir = docs.appendingPathComponent(manifest.localDirectory)
        let totalSegments = manifest.segmentUrls.count
        
        let downloadedSet: Set<Int>
        if let cached = downloadedSegmentsCache[itemId] {
            downloadedSet = cached
        } else {
            let initialSet = await Task.detached(priority: .background) { () -> Set<Int> in
                var set = Set<Int>()
                let fm = FileManager.default
                for i in 0..<totalSegments {
                    let fileUrl = taskDir.appendingPathComponent("segment_\(i).ts")
                    if let size = (try? fm.attributesOfItem(atPath: fileUrl.path)[.size] as? Int64), size > 0 {
                        set.insert(i)
                    }
                }
                return set
            }.value
            downloadedSegmentsCache[itemId] = initialSet
            downloadedSet = initialSet
        }
        
        let downloadedCount = downloadedSet.count
        let missingIndices = (0..<totalSegments).filter { !downloadedSet.contains($0) }
        
        let progress = Double(downloadedCount) / Double(totalSegments)
        updateItem(id: itemId) {
            $0.progress = progress
            $0.downloadedBytes = Int64(downloadedCount)
            $0.totalBytes = Int64(totalSegments)
            $0.status = downloadedCount == totalSegments ? .completed : .downloading
        }
        
        if downloadedCount == totalSegments {
            if let downloadedItem = downloads.first(where: { $0.id == itemId }) {
                ToastManager.shared.show(
                    title: "Загрузка завершена",
                    subtitle: "«\(downloadedItem.title)» сохранено",
                    icon: "checkmark.circle.fill"
                )
            }
            activeManifests.removeValue(forKey: itemId)
            return
        }
        
        let activeBgTasks = await session.tasks.2
        let runningForThisItem = activeBgTasks.compactMap { task -> Int? in
            guard let desc = task.taskDescription, desc.starts(with: "\(itemId)|") else { return nil }
            let comps = desc.split(separator: "|")
            if comps.count >= 2, let idx = Int(comps[1]) { return idx }
            return nil
        }
        
        let neededSlots = max(0, concurrencyLimit - runningForThisItem.count)
        if neededSlots > 0 {
            let indicesToStart = missingIndices.filter { !runningForThisItem.contains($0) }.prefix(neededSlots)
            for idx in indicesToStart {
                let url = manifest.segmentUrls[idx]
                var request = URLRequest(url: url)
                for (k, v) in manifest.headers { request.setValue(v, forHTTPHeaderField: k) }
                if request.value(forHTTPHeaderField: "User-Agent") == nil {
                    request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")
                }
                
                let task = session.downloadTask(with: request)
                task.taskDescription = "\(itemId)|\(idx)|0|\(manifest.localDirectory)"
                task.resume()
            }
        }
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let desc = downloadTask.taskDescription, let comps = extractTaskInfo(desc: desc) else { return }
        
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "ProcessSegment_\(comps.itemId)_\(comps.index)") {
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }
        
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let taskDir = docs.appendingPathComponent(comps.localDirectory)
        let finalUrl = taskDir.appendingPathComponent("segment_\(comps.index).ts")
        
        try? FileManager.default.removeItem(at: finalUrl)
        try? FileManager.default.moveItem(at: location, to: finalUrl)
        
        Task { @MainActor in
            defer {
                if bgTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskId)
                    bgTaskId = .invalid
                }
            }
            self.downloadedSegmentsCache[comps.itemId]?.insert(comps.index)
            await self.enqueueNextBatch(for: comps.itemId)
        }
    }
    
    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let desc = task.taskDescription, let comps = extractTaskInfo(desc: desc) else { return }
        
        if let error = error as NSError?, error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
            return
        }
        
        var bgTaskId: UIBackgroundTaskIdentifier = .invalid
        bgTaskId = UIApplication.shared.beginBackgroundTask(withName: "RetrySegment_\(comps.itemId)_\(comps.index)") {
            if bgTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskId)
                bgTaskId = .invalid
            }
        }
        
        Task { @MainActor in
            defer {
                if bgTaskId != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskId)
                    bgTaskId = .invalid
                }
            }
            
            // Ленивое восстановление манифеста при пробуждении в фоне
            if self.activeManifests[comps.itemId] == nil {
                let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let manifestUrl = docs.appendingPathComponent(comps.localDirectory).appendingPathComponent("manifest.json")
                if let data = try? Data(contentsOf: manifestUrl),
                   let manifest = try? JSONDecoder().decode(DownloadManifest.self, from: data) {
                    self.activeManifests[comps.itemId] = manifest
                }
            }
            
            guard let manifest = self.activeManifests[comps.itemId] else { return }
            
            if error != nil {
                if comps.retries < 3 {
                    let url = manifest.segmentUrls[comps.index]
                    var request = URLRequest(url: url)
                    for (k, v) in manifest.headers { request.setValue(v, forHTTPHeaderField: k) }
                    
                    let newTask = self.session.downloadTask(with: request)
                    newTask.taskDescription = "\(comps.itemId)|\(comps.index)|\(comps.retries + 1)|\(manifest.localDirectory)"
                    newTask.resume()
                } else {
                    await self.finishWithError(id: comps.itemId, message: "Ошибка сети после 3 попыток")
                }
            }
        }
    }
    
    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
    
    private nonisolated func extractTaskInfo(desc: String) -> (itemId: String, index: Int, retries: Int, localDirectory: String)? {
        let parts = desc.split(separator: "|")
        if parts.count >= 4, let idx = Int(parts[1]) {
            let retries = Int(parts[2]) ?? 0
            let localDirectory = String(parts[3])
            return (String(parts[0]), idx, retries, localDirectory)
        }
        return nil
    }
    
    private func finishWithError(id: String, message: String) async {
        updateItem(id: id) {
            $0.status = .failed
            $0.errorMessage = message
        }
        
        // Отменяем все активные таски URLSession для данного item
        session.getAllTasks { tasks in
            for task in tasks {
                if let desc = task.taskDescription, desc.hasPrefix(id + "|") {
                    task.cancel()
                }
            }
        }
        
        if let item = downloads.first(where: { $0.id == id }) {
            ToastManager.shared.show(
                title: "Ошибка",
                subtitle: "Не удалось скачать «\(item.title)»",
                icon: "exclamationmark.triangle.fill"
            )
        }
    }
    
    private func downloadDataDirectly(from url: URL, headers: [String: String]) async throws -> Data {
        var request = URLRequest(url: url)
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        let (data, response) = try await defaultSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
    
    private func chooseMediaPlaylistUrl(from content: String, baseUrl: URL, preferredQuality: VideoQualityPreference) -> URL? {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        
        var variants: [(url: URL, height: Int, bandwidth: Double)] = []
        var currentBandwidth: Double = 0
        var currentHeight: Int = 0
        var isAv1 = false
        var hasStreamInf = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            
            if trimmed.hasPrefix("#EXT-X-STREAM-INF:") {
                hasStreamInf = true
                currentBandwidth = 0
                currentHeight = 0
                isAv1 = false
                
                let lower = trimmed.lowercased()
                
                // Parse CODECS and filter out AV1 streams
                if lower.contains("av01") || lower.contains("codecs=\"av01") || lower.contains("codecs=\"av1") || lower.contains("codecs='av1") {
                    isAv1 = true
                }
                
                // Parse BANDWIDTH or AVERAGE-BANDWIDTH
                if let bwRange = trimmed.range(of: #"BANDWIDTH=([0-9]+)"#, options: .regularExpression) {
                    let match = String(trimmed[bwRange])
                    let comps = match.components(separatedBy: "=")
                    if comps.count == 2, let bw = Double(comps[1]) {
                        currentBandwidth = bw
                    }
                } else if let avgBwRange = trimmed.range(of: #"AVERAGE-BANDWIDTH=([0-9]+)"#, options: .regularExpression) {
                    let match = String(trimmed[avgBwRange])
                    let comps = match.components(separatedBy: "=")
                    if comps.count == 2, let bw = Double(comps[1]) {
                        currentBandwidth = bw
                    }
                }
                
                // Parse RESOLUTION=WxH
                if let resRange = trimmed.range(of: #"RESOLUTION=([0-9]+)x([0-9]+)"#, options: .regularExpression) {
                    let match = String(trimmed[resRange]).replacingOccurrences(of: "RESOLUTION=", with: "")
                    let comps = match.components(separatedBy: "x")
                    if comps.count == 2, let h = Int(comps[1]) {
                        currentHeight = h
                    }
                }
            } else if hasStreamInf && !trimmed.hasPrefix("#") {
                hasStreamInf = false
                
                let lowerUrl = trimmed.lowercased()
                if lowerUrl.contains("av01") || lowerUrl.contains("_av1") || lowerUrl.contains(".av1") {
                    isAv1 = true
                }
                
                // If AV1 stream, filter out completely
                if isAv1 {
                    continue
                }
                
                // Fallback resolution detection from variant URL if not found in #EXT-X-STREAM-INF
                if currentHeight == 0 {
                    currentHeight = extractHeightFromUrlString(trimmed)
                }
                
                let variantUrl = trimmed.hasPrefix("http") ? URL(string: trimmed) : URL(string: trimmed, relativeTo: baseUrl)
                if let variantUrl = variantUrl?.absoluteURL {
                    variants.append((url: variantUrl, height: currentHeight, bandwidth: currentBandwidth))
                }
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
        
        // Select the variant with highest resolution <= targetHeight, tie-breaking on highest bandwidth
        let eligible = variants.filter { $0.height > 0 && $0.height <= targetHeight }
        if !eligible.isEmpty {
            let sorted = eligible.sorted { a, b in
                if a.height != b.height {
                    return a.height > b.height
                }
                return a.bandwidth > b.bandwidth
            }
            return sorted.first?.url
        }
        
        // If no variant <= targetHeight exists, select the closest available resolution
        let sorted = variants.sorted { a, b in
            if a.height > 0 && b.height > 0 {
                let diffA = abs(a.height - targetHeight)
                let diffB = abs(b.height - targetHeight)
                if diffA != diffB {
                    return diffA < diffB
                }
            } else if a.height > 0 || b.height > 0 {
                return a.height > b.height
            }
            return a.bandwidth > b.bandwidth
        }
        return sorted.first?.url
    }
    
    private func extractHeightFromUrlString(_ urlString: String) -> Int {
        let pathWithoutQuery = urlString.components(separatedBy: "?").first?.lowercased() ?? urlString.lowercased()
        
        let pattern = #"(?:^|[/._\-])(2160|1440|1080|720|480|360|240)(?:p)?(?:\.m3u8|[/._\-]|$)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: pathWithoutQuery, options: [], range: NSRange(location: 0, length: pathWithoutQuery.utf16.count)),
           match.numberOfRanges >= 2,
           let range = Range(match.range(at: 1), in: pathWithoutQuery),
           let height = Int(pathWithoutQuery[range]) {
            return height
        }
        return 0
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
