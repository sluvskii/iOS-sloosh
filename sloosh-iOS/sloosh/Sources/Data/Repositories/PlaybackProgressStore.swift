import Foundation
import SwiftData
import SwiftUI
import Combine

public struct PlaybackProgressRecord: Identifiable, Codable {
    public let mediaId: String
    public let kpId: Int
    public var tmdbId: Int?
    public let season: Int?
    public let episode: Int?
    public var voiceover: String?
    public var positionSec: Double
    public var durationSec: Double
    public var watched: Bool
    public var updatedAtMs: Int

    public var id: String { mediaId }

    public var isEpisode: Bool {
        season != nil && episode != nil
    }

    public var rootMediaKey: String {
        if let sRange = mediaId.range(of: "_s\\d+_e\\d+", options: .regularExpression) {
            return String(mediaId[..<sRange.lowerBound])
        }
        return mediaId
    }

    public var progressFraction: Double {
        guard durationSec.isFinite, durationSec > 0, positionSec.isFinite else { return 0 }
        return max(0, min(positionSec / durationSec, 0.999))
    }

    public init(
        mediaId: String,
        kpId: Int,
        tmdbId: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        voiceover: String? = nil,
        positionSec: Double = 0,
        durationSec: Double = 0,
        watched: Bool = false,
        updatedAtMs: Int = Int(Date().timeIntervalSince1970 * 1000)
    ) {
        self.mediaId = mediaId
        self.kpId = kpId
        self.tmdbId = tmdbId
        self.season = season
        self.episode = episode
        self.voiceover = voiceover
        self.positionSec = positionSec
        self.durationSec = durationSec
        self.watched = watched
        self.updatedAtMs = updatedAtMs
    }
}

public struct PlaybackMediaMetadata: Codable {
    public let kpId: Int
    public let tmdbId: Int?
    public let detailsId: String
    public let title: String
    public let type: String?
    public let posterUrl: String?
    public let backdropUrl: String?
    public let logoUrl: String?
    public let mediaKey: String?

    public init(
        kpId: Int,
        tmdbId: Int? = nil,
        detailsId: String,
        title: String,
        type: String? = nil,
        posterUrl: String? = nil,
        backdropUrl: String? = nil,
        logoUrl: String? = nil,
        mediaKey: String? = nil
    ) {
        self.kpId = kpId
        self.tmdbId = tmdbId
        self.detailsId = detailsId
        self.title = title
        self.type = type
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
        self.mediaKey = mediaKey
    }
}

@MainActor
public final class PlaybackProgressStore: ObservableObject {
    public static let shared = PlaybackProgressStore()
    
    private var context: ModelContext { AppDatabase.shared.container.mainContext }
    private var cancellables = Set<AnyCancellable>()

    private static let episodeRegex = try! NSRegularExpression(pattern: "^(.+)_s(\\d+)_e(\\d+)$")
    private static let kpMovieRegex = try! NSRegularExpression(pattern: "^kp_(\\d+)$")
    private static let tmdbMovieRegex = try! NSRegularExpression(pattern: "^tmdb_(\\d+)$")

    public var currentUserId: String {
        guard let user = AuthRepository.shared.currentUser, !user.isAnonymous else {
            return "guest"
        }
        return user.id
    }

    private init() {
        AuthRepository.shared.$currentUser
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.handleUserChanged()
            }
            .store(in: &cancellables)
    }

    private var lastSyncedUserId: String?
    private var lastSyncTime: Date = .distantPast

    public func handleUserChanged(force: Bool = false) {
        let user = AuthRepository.shared.currentUser
        if AuthRepository.shared.isAuthenticated, let user = user {
            let now = Date()
            if !force && lastSyncedUserId == user.id && now.timeIntervalSince(lastSyncTime) < 30.0 {
                return
            }
            lastSyncedUserId = user.id
            lastSyncTime = now
            
            Task {
                if let remoteProgress = await CloudSyncService.shared.fetchRemoteProgress(userId: user.id, idToken: user.idToken) {
                    await self.syncRemoteProgressToLocal(remoteProgress, userId: user.id)
                }
                if let remoteMetadata = await CloudSyncService.shared.fetchRemoteMetadata(userId: user.id, idToken: user.idToken) {
                    await self.syncRemoteMetadataToLocal(remoteMetadata, userId: user.id)
                }
            }
        } else {
            lastSyncedUserId = nil
        }
    }

    private func getRecordModel(mediaId: String) -> ProgressRecordModel? {
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(mediaId)"
        let descriptor = FetchDescriptor<ProgressRecordModel>(predicate: #Predicate { $0.userMediaIdKey == compositeKey })
        return try? context.fetch(descriptor).first
    }
    
    private func getRecord(mediaId: String) -> PlaybackProgressRecord? {
        guard let model = getRecordModel(mediaId: mediaId) else { return nil }
        return PlaybackProgressRecord(
            mediaId: model.mediaId,
            kpId: model.kpId,
            tmdbId: model.tmdbId,
            season: model.season,
            episode: model.episode,
            voiceover: model.voiceover,
            positionSec: model.positionSec,
            durationSec: model.durationSec,
            watched: model.watched,
            updatedAtMs: model.updatedAtMs
        )
    }

    private var lastDiskSaveDate: Date = .distantPast

    private func mutateRecord(mediaId: String, forceDiskSave: Bool = false, mutate: @escaping (inout PlaybackProgressRecord) -> Void) {
        let activeUserId = currentUserId
        var record = getRecord(mediaId: mediaId) ?? createDefaultRecord(mediaId: mediaId)
        mutate(&record)
        record.updatedAtMs = Int(Date().timeIntervalSince1970 * 1000)
        
        if let model = getRecordModel(mediaId: mediaId) {
            model.positionSec = record.positionSec
            model.durationSec = record.durationSec
            model.watched = record.watched
            model.updatedAtMs = record.updatedAtMs
            if let v = record.voiceover { model.voiceover = v }
            if let t = record.tmdbId { model.tmdbId = t }
            if let s = record.season { model.season = s }
            if let e = record.episode { model.episode = e }
        } else {
            let newModel = ProgressRecordModel(
                userId: activeUserId,
                mediaId: record.mediaId,
                kpId: record.kpId,
                tmdbId: record.tmdbId,
                season: record.season,
                episode: record.episode,
                voiceover: record.voiceover,
                positionSec: record.positionSec,
                durationSec: record.durationSec,
                watched: record.watched,
                updatedAtMs: record.updatedAtMs
            )
            context.insert(newModel)
        }

        let now = Date()
        if forceDiskSave || now.timeIntervalSince(lastDiskSaveDate) >= 2.0 {
            lastDiskSaveDate = now
            try? context.save()
            scheduleCloudProgressPush()
        }
    }

    private var lastCloudProgressPushDate: Date?

    public func scheduleCloudProgressPush(force: Bool = false) {
        guard AuthRepository.shared.isAuthenticated, let user = AuthRepository.shared.currentUser else { return }
        
        let now = Date()
        if !force, let lastPush = lastCloudProgressPushDate, now.timeIntervalSince(lastPush) < 60.0 {
            return
        }
        
        lastCloudProgressPushDate = now
        let allRecords = self.listProgressRecords()
        Task {
            await CloudSyncService.shared.pushRemoteProgress(allRecords, userId: user.id, idToken: user.idToken)
        }
    }
    
    private func createDefaultRecord(mediaId: String) -> PlaybackProgressRecord {
        let range = NSRange(mediaId.startIndex..., in: mediaId)
        var kpId = 0
        var tmdbId: Int? = nil
        var season: Int? = nil
        var episode: Int? = nil

        if let match = Self.episodeRegex.firstMatch(in: mediaId, range: range) {
            if let rootRange = Range(match.range(at: 1), in: mediaId),
               let seasonRange = Range(match.range(at: 2), in: mediaId),
               let episodeRange = Range(match.range(at: 3), in: mediaId) {
                let rootStr = String(mediaId[rootRange])
                season = Int(mediaId[seasonRange])
                episode = Int(mediaId[episodeRange])
                if rootStr.hasPrefix("kp_") {
                    kpId = Int(rootStr.dropFirst(3)) ?? 0
                } else if rootStr.hasPrefix("tmdb_") {
                    tmdbId = Int(rootStr.dropFirst(5))
                } else if rootStr.hasPrefix("movie_") {
                    tmdbId = Int(rootStr.dropFirst(6))
                } else if rootStr.hasPrefix("tv_") {
                    tmdbId = Int(rootStr.dropFirst(3))
                } else if let intVal = Int(rootStr) {
                    tmdbId = intVal
                }
            }
        } else if let match = Self.kpMovieRegex.firstMatch(in: mediaId, range: range) {
            if let kpRange = Range(match.range(at: 1), in: mediaId) {
                kpId = Int(mediaId[kpRange]) ?? 0
            }
        } else if let match = Self.tmdbMovieRegex.firstMatch(in: mediaId, range: range) {
            if let tmdbRange = Range(match.range(at: 1), in: mediaId) {
                tmdbId = Int(mediaId[tmdbRange])
            }
        } else if mediaId.hasPrefix("movie_") {
            tmdbId = Int(mediaId.dropFirst(6))
        } else if mediaId.hasPrefix("tv_") {
            tmdbId = Int(mediaId.dropFirst(3))
        } else if let intVal = Int(mediaId) {
            tmdbId = intVal
        }

        return PlaybackProgressRecord(
            mediaId: mediaId,
            kpId: kpId,
            tmdbId: tmdbId,
            season: season,
            episode: episode,
            voiceover: nil,
            positionSec: 0,
            durationSec: 0,
            watched: false,
            updatedAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
    }

    public func save(
        mediaId: String,
        positionSec: Double,
        durationSec: Double? = nil,
        voiceover: String? = nil,
        forceDiskSave: Bool = false
    ) {
        guard !mediaId.isEmpty, positionSec.isFinite, positionSec >= 0 else { return }
        mutateRecord(mediaId: mediaId, forceDiskSave: forceDiskSave) { record in
            // Protect against zeroing out valid non-zero progress
            if positionSec > 1 || record.positionSec <= 1 {
                record.positionSec = positionSec
            }
            if let v = voiceover, !v.isEmpty {
                record.voiceover = v
            }
            if let dur = durationSec, dur >= 120, dur.isFinite {
                record.durationSec = dur
                if dur >= 180 && record.positionSec >= 120 && ((record.positionSec / dur >= 0.93) || (dur - record.positionSec <= 90)) {
                    record.watched = true
                } else if dur >= 180 && record.positionSec < dur * 0.90 && (dur - record.positionSec > 120) {
                    record.watched = false
                }
            }
        }
    }

    public func save(mediaId: String, positionSec: Double, durationSec: Double? = nil, forceDiskSave: Bool = false) {
        save(mediaId: mediaId, positionSec: positionSec, durationSec: durationSec, voiceover: nil, forceDiskSave: forceDiskSave)
    }

    public func load(mediaId: String) -> Double {
        guard !mediaId.isEmpty else { return 0 }
        return getRecord(mediaId: mediaId)?.positionSec ?? 0
    }

    public func loadVoiceover(mediaId: String) -> String? {
        guard !mediaId.isEmpty else { return nil }
        return getRecord(mediaId: mediaId)?.voiceover
    }

    public func loadDuration(mediaId: String) -> Double {
        guard !mediaId.isEmpty else { return 0 }
        return getRecord(mediaId: mediaId)?.durationSec ?? 0
    }

    public func normalizedProgress(mediaId: String) -> Double? {
        guard !mediaId.isEmpty else { return nil }
        guard let record = getRecord(mediaId: mediaId) else { return nil }
        let duration = record.durationSec
        let position = record.positionSec
        guard position.isFinite, duration.isFinite, duration > 0 else { return nil }
        return max(0, min(position / duration, 0.999))
    }

    public func loadWatched(mediaId: String) -> Bool {
        guard !mediaId.isEmpty else { return false }
        return getRecord(mediaId: mediaId)?.watched ?? false
    }

    public func markAsWatched(mediaId: String) {
        guard !mediaId.isEmpty else { return }
        mutateRecord(mediaId: mediaId, forceDiskSave: true) { record in
            record.watched = true
        }
    }

    public func setWatched(mediaId: String, watched: Bool) {
        guard !mediaId.isEmpty else { return }
        mutateRecord(mediaId: mediaId, forceDiskSave: true) { record in
            record.watched = watched
        }
    }

    public func loadUpdatedAtMs(mediaId: String) -> Int {
        guard !mediaId.isEmpty else { return 0 }
        return getRecord(mediaId: mediaId)?.updatedAtMs ?? 0
    }

    public func removeRecord(mediaId: String) {
        guard !mediaId.isEmpty else { return }
        if let model = getRecordModel(mediaId: mediaId) {
            context.delete(model)
            try? context.save()
        }
    }

    public func saveMetadata(
        kpId: Int = 0,
        tmdbId: Int? = nil,
        detailsId: String,
        title: String,
        type: String?,
        posterUrl: String?,
        backdropUrl: String?,
        logoUrl: String?,
        mediaKey: String? = nil
    ) {
        guard !detailsId.isEmpty, !title.isEmpty else { return }
        let activeUserId = currentUserId
        let resolvedKey = mediaKey ?? (kpId > 0 ? "kp_\(kpId)" : (detailsId.isEmpty ? "tmdb_\(tmdbId ?? 0)" : detailsId))
        let compositeKey = "\(activeUserId)_\(resolvedKey)"

        let descriptor = FetchDescriptor<PlaybackMetadataModel>(predicate: #Predicate { $0.userKpIdKey == compositeKey })
        if let model = try? context.fetch(descriptor).first {
            model.detailsId = detailsId
            model.title = title
            model.type = type
            model.kpId = kpId
            if let t = tmdbId { model.tmdbId = t }
            model.posterUrl = posterUrl
            model.backdropUrl = backdropUrl
            model.logoUrl = logoUrl
        } else {
            let model = PlaybackMetadataModel(
                userId: activeUserId,
                kpId: kpId,
                tmdbId: tmdbId,
                detailsId: detailsId,
                title: title,
                type: type,
                posterUrl: posterUrl,
                backdropUrl: backdropUrl,
                logoUrl: logoUrl,
                mediaKey: resolvedKey
            )
            context.insert(model)
        }
        try? context.save()

        if AuthRepository.shared.isAuthenticated, let user = AuthRepository.shared.currentUser {
            let allMetadata = self.listAllMetadata()
            Task {
                await CloudSyncService.shared.pushRemoteMetadata(allMetadata, userId: user.id, idToken: user.idToken)
            }
        }
    }

    public func saveMetadata(
        kpId: Int,
        detailsId: String,
        title: String,
        type: String?,
        posterUrl: String?,
        backdropUrl: String?,
        logoUrl: String?
    ) {
        saveMetadata(
            kpId: kpId,
            tmdbId: nil,
            detailsId: detailsId,
            title: title,
            type: type,
            posterUrl: posterUrl,
            backdropUrl: backdropUrl,
            logoUrl: logoUrl,
            mediaKey: kpId > 0 ? "kp_\(kpId)" : detailsId
        )
    }

    func saveMetadata(details: MediaDetailsDto) {
        let kpId = details.ids?.kp ?? details.externalIds?.kp ?? 0
        let tmdbId = details.externalIds?.tmdb ?? details.ids?.tmdb ?? Int(details.id ?? "")
        let detailsId = details.id ?? (kpId > 0 ? "kp_\(kpId)" : String(tmdbId ?? 0))
        let title = details.title ?? details.originalTitle ?? "Без названия"

        saveMetadata(
            kpId: kpId,
            tmdbId: tmdbId,
            detailsId: detailsId,
            title: title,
            type: details.type,
            posterUrl: details.displayPosterUrl,
            backdropUrl: details.displayBackdropUrl ?? details.displayPosterUrl,
            logoUrl: details.displayLogoUrl,
            mediaKey: kpId > 0 ? "kp_\(kpId)" : (details.id ?? "tmdb_\(tmdbId ?? 0)")
        )
    }

    public func loadMetadata(mediaKey: String) -> PlaybackMediaMetadata? {
        guard !mediaKey.isEmpty else { return nil }
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(mediaKey)"
        let descriptor = FetchDescriptor<PlaybackMetadataModel>(predicate: #Predicate { $0.userKpIdKey == compositeKey })
        if let model = try? context.fetch(descriptor).first {
            return PlaybackMediaMetadata(
                kpId: model.kpId,
                tmdbId: model.tmdbId,
                detailsId: model.detailsId,
                title: model.title,
                type: model.type,
                posterUrl: model.posterUrl,
                backdropUrl: model.backdropUrl,
                logoUrl: model.logoUrl,
                mediaKey: mediaKey
            )
        }
        let altDescriptor = FetchDescriptor<PlaybackMetadataModel>(
            predicate: #Predicate { $0.userId == activeUserId && $0.detailsId == mediaKey }
        )
        if let model = try? context.fetch(altDescriptor).first {
            return PlaybackMediaMetadata(
                kpId: model.kpId,
                tmdbId: model.tmdbId,
                detailsId: model.detailsId,
                title: model.title,
                type: model.type,
                posterUrl: model.posterUrl,
                backdropUrl: model.backdropUrl,
                logoUrl: model.logoUrl,
                mediaKey: mediaKey
            )
        }

        // Secondary fallback by kpId or tmdbId
        if mediaKey.hasPrefix("kp_"), let kp = Int(mediaKey.dropFirst(3)) {
            let kpDesc = FetchDescriptor<PlaybackMetadataModel>(predicate: #Predicate { $0.userId == activeUserId && $0.kpId == kp })
            if let model = try? context.fetch(kpDesc).first {
                return PlaybackMediaMetadata(
                    kpId: model.kpId,
                    tmdbId: model.tmdbId,
                    detailsId: model.detailsId,
                    title: model.title,
                    type: model.type,
                    posterUrl: model.posterUrl,
                    backdropUrl: model.backdropUrl,
                    logoUrl: model.logoUrl,
                    mediaKey: mediaKey
                )
            }
        } else if mediaKey.hasPrefix("tmdb_"), let tmdb = Int(mediaKey.dropFirst(5)) {
            let tmdbDesc = FetchDescriptor<PlaybackMetadataModel>(predicate: #Predicate { $0.userId == activeUserId && $0.tmdbId == tmdb })
            if let model = try? context.fetch(tmdbDesc).first {
                return PlaybackMediaMetadata(
                    kpId: model.kpId,
                    tmdbId: model.tmdbId,
                    detailsId: model.detailsId,
                    title: model.title,
                    type: model.type,
                    posterUrl: model.posterUrl,
                    backdropUrl: model.backdropUrl,
                    logoUrl: model.logoUrl,
                    mediaKey: mediaKey
                )
            }
        } else if let intVal = Int(mediaKey) {
            let intDesc = FetchDescriptor<PlaybackMetadataModel>(predicate: #Predicate { $0.userId == activeUserId && ($0.kpId == intVal || $0.tmdbId == intVal) })
            if let model = try? context.fetch(intDesc).first {
                return PlaybackMediaMetadata(
                    kpId: model.kpId,
                    tmdbId: model.tmdbId,
                    detailsId: model.detailsId,
                    title: model.title,
                    type: model.type,
                    posterUrl: model.posterUrl,
                    backdropUrl: model.backdropUrl,
                    logoUrl: model.logoUrl,
                    mediaKey: mediaKey
                )
            }
        }
        return nil
    }

    public func loadMetadata(kpId: Int) -> PlaybackMediaMetadata? {
        guard kpId > 0 else { return nil }
        return loadMetadata(mediaKey: "kp_\(kpId)")
    }

    public func listAllMetadata() -> [PlaybackMediaMetadata] {
        let activeUserId = currentUserId
        let descriptor = FetchDescriptor<PlaybackMetadataModel>(predicate: #Predicate { $0.userId == activeUserId })
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map {
            PlaybackMediaMetadata(
                kpId: $0.kpId,
                tmdbId: $0.tmdbId,
                detailsId: $0.detailsId,
                title: $0.title,
                type: $0.type,
                posterUrl: $0.posterUrl,
                backdropUrl: $0.backdropUrl,
                logoUrl: $0.logoUrl,
                mediaKey: $0.kpId > 0 ? "kp_\($0.kpId)" : $0.detailsId
            )
        }
    }

    public func listProgressRecords(kpId: Int? = nil, mediaKey: String? = nil) -> [PlaybackProgressRecord] {
        let activeUserId = currentUserId
        let descriptor = FetchDescriptor<ProgressRecordModel>(
            predicate: #Predicate { $0.userId == activeUserId },
            sortBy: [SortDescriptor(\.updatedAtMs, order: .reverse)]
        )
        var allModels = (try? context.fetch(descriptor)) ?? []

        // If active user is authenticated, migrate any guest records seamlessly
        if activeUserId != "guest" {
            let guestDesc = FetchDescriptor<ProgressRecordModel>(predicate: #Predicate { $0.userId == "guest" })
            if let guestModels = try? context.fetch(guestDesc), !guestModels.isEmpty {
                var hasMigrated = false
                for g in guestModels {
                    if !allModels.contains(where: { $0.mediaId == g.mediaId }) {
                        g.userId = activeUserId
                        g.userMediaIdKey = "\(activeUserId)_\(g.mediaId)"
                        allModels.append(g)
                        hasMigrated = true
                    }
                }
                if hasMigrated {
                    try? context.save()
                }
            }
        }
        
        var results: [PlaybackProgressRecord] = []
        var seriesRootKeys = Set<String>()
        
        // Episodes first
        for model in allModels {
            let isEpisode = model.season != nil && model.episode != nil
            if isEpisode {
                if let filterKpId = kpId, model.kpId != filterKpId { continue }
                let rootKey = model.mediaId.components(separatedBy: "_s")[0]
                if let filterKey = mediaKey, rootKey != filterKey { continue }
                seriesRootKeys.insert(rootKey)
                results.append(PlaybackProgressRecord(
                    mediaId: model.mediaId,
                    kpId: model.kpId,
                    tmdbId: model.tmdbId,
                    season: model.season,
                    episode: model.episode,
                    voiceover: model.voiceover,
                    positionSec: model.positionSec,
                    durationSec: model.durationSec,
                    watched: model.watched,
                    updatedAtMs: model.updatedAtMs
                ))
            }
        }
        
        // Movies
        for model in allModels {
            let isEpisode = model.season != nil && model.episode != nil
            if !isEpisode {
                if let filterKpId = kpId, model.kpId != filterKpId { continue }
                let rootKey = model.mediaId
                if let filterKey = mediaKey, rootKey != filterKey { continue }
                if seriesRootKeys.contains(rootKey) { continue }
                results.append(PlaybackProgressRecord(
                    mediaId: model.mediaId,
                    kpId: model.kpId,
                    tmdbId: model.tmdbId,
                    season: model.season,
                    episode: model.episode,
                    voiceover: model.voiceover,
                    positionSec: model.positionSec,
                    durationSec: model.durationSec,
                    watched: model.watched,
                    updatedAtMs: model.updatedAtMs
                ))
            }
        }
        
        return results.sorted { $0.updatedAtMs > $1.updatedAtMs }
    }

    public func saveLastVoiceover(mediaKey: String, source: String = "alloha", voiceover: String?) {
        guard !mediaKey.isEmpty else { return }
        let activeUserId = currentUserId
        let key = "\(source).lastVoiceover.\(mediaKey)"
        let compositeKey = "\(activeUserId)_\(key)"
        let descriptor = FetchDescriptor<LastPlayedVoiceoverModel>(predicate: #Predicate { $0.userSourceKey == compositeKey })
        
        if let v = voiceover, !v.isEmpty {
            if let model = try? context.fetch(descriptor).first {
                model.voiceover = v
            } else {
                context.insert(LastPlayedVoiceoverModel(userId: activeUserId, key: key, source: source, voiceover: v))
            }
            UserDefaults.standard.set(v, forKey: "alloha_last_translation_name")
        } else {
            if let model = try? context.fetch(descriptor).first {
                context.delete(model)
            }
        }
        try? context.save()
    }

    public func loadLastVoiceover(mediaKey: String, source: String = "alloha") -> String? {
        guard !mediaKey.isEmpty else { return nil }
        let activeUserId = currentUserId
        let key = "\(source).lastVoiceover.\(mediaKey)"
        let compositeKey = "\(activeUserId)_\(key)"
        let descriptor = FetchDescriptor<LastPlayedVoiceoverModel>(predicate: #Predicate { $0.userSourceKey == compositeKey })
        return try? context.fetch(descriptor).first?.voiceover
    }

    public func saveLastVoiceover(kpId: Int, source: String = "alloha", voiceover: String?) {
        if kpId > 0 {
            saveLastVoiceover(mediaKey: "kp_\(kpId)", source: source, voiceover: voiceover)
        }
    }

    public func loadLastVoiceover(kpId: Int, source: String = "alloha") -> String? {
        guard kpId > 0 else { return nil }
        return loadLastVoiceover(mediaKey: "kp_\(kpId)", source: source)
    }

    public func saveLastPlayed(mediaKey: String, season: Int?, episode: Int?) {
        guard !mediaKey.isEmpty else { return }
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(mediaKey)"
        let descriptor = FetchDescriptor<LastPlayedEpisodeModel>(predicate: #Predicate { $0.userKpIdKey == compositeKey })
        if let model = try? context.fetch(descriptor).first {
            if let s = season { model.season = s }
            if let e = episode { model.episode = e }
        } else {
            context.insert(LastPlayedEpisodeModel(userId: activeUserId, kpId: 0, mediaKey: mediaKey, season: season, episode: episode))
        }
        try? context.save()
    }

    public func loadLastSeason(mediaKey: String) -> Int? {
        guard !mediaKey.isEmpty else { return nil }
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(mediaKey)"
        let descriptor = FetchDescriptor<LastPlayedEpisodeModel>(predicate: #Predicate { $0.userKpIdKey == compositeKey })
        return try? context.fetch(descriptor).first?.season
    }

    public func loadLastEpisode(mediaKey: String) -> Int? {
        guard !mediaKey.isEmpty else { return nil }
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(mediaKey)"
        let descriptor = FetchDescriptor<LastPlayedEpisodeModel>(predicate: #Predicate { $0.userKpIdKey == compositeKey })
        return try? context.fetch(descriptor).first?.episode
    }

    public func saveLastPlayed(kpId: Int, season: Int?, episode: Int?) {
        if kpId > 0 {
            saveLastPlayed(mediaKey: "kp_\(kpId)", season: season, episode: episode)
        }
    }

    public func loadLastSeason(kpId: Int) -> Int? {
        guard kpId > 0 else { return nil }
        return loadLastSeason(mediaKey: "kp_\(kpId)")
    }

    public func loadLastEpisode(kpId: Int) -> Int? {
        guard kpId > 0 else { return nil }
        return loadLastEpisode(mediaKey: "kp_\(kpId)")
    }

    private func syncRemoteProgressToLocal(_ remoteRecords: [PlaybackProgressRecord], userId: String) async {
        guard !userId.isEmpty else { return }
        let predicate = #Predicate<ProgressRecordModel> { $0.userId == userId }
        let existing = (try? context.fetch(FetchDescriptor<ProgressRecordModel>(predicate: predicate))) ?? []
        var existingByMediaId: [String: ProgressRecordModel] = [:]
        for model in existing {
            existingByMediaId[model.mediaId] = model
        }

        var shouldPushBack = false

        for remote in remoteRecords {
            if let local = existingByMediaId[remote.mediaId] {
                if remote.updatedAtMs > local.updatedAtMs {
                    local.positionSec = remote.positionSec
                    local.durationSec = remote.durationSec
                    local.watched = remote.watched
                    local.updatedAtMs = remote.updatedAtMs
                    if let v = remote.voiceover { local.voiceover = v }
                    if let t = remote.tmdbId { local.tmdbId = t }
                    if let s = remote.season { local.season = s }
                    if let e = remote.episode { local.episode = e }
                } else if local.updatedAtMs > remote.updatedAtMs {
                    shouldPushBack = true
                }
            } else {
                let model = ProgressRecordModel(
                    userId: userId,
                    mediaId: remote.mediaId,
                    kpId: remote.kpId,
                    tmdbId: remote.tmdbId,
                    season: remote.season,
                    episode: remote.episode,
                    voiceover: remote.voiceover,
                    positionSec: remote.positionSec,
                    durationSec: remote.durationSec,
                    watched: remote.watched,
                    updatedAtMs: remote.updatedAtMs
                )
                context.insert(model)
            }
        }

        // If local had records not in remote, or if remote was empty and local had items:
        if existing.count > remoteRecords.count || (remoteRecords.isEmpty && !existing.isEmpty) {
            shouldPushBack = true
        }

        try? context.save()

        if shouldPushBack, AuthRepository.shared.isAuthenticated, let user = AuthRepository.shared.currentUser, user.id == userId {
            let all = self.listProgressRecords()
            Task {
                await CloudSyncService.shared.pushRemoteProgress(all, userId: userId, idToken: user.idToken)
            }
        }
    }

    private func syncRemoteMetadataToLocal(_ remoteMetadata: [PlaybackMediaMetadata], userId: String) async {
        guard !userId.isEmpty else { return }
        let predicate = #Predicate<PlaybackMetadataModel> { $0.userId == userId }
        let existing = (try? context.fetch(FetchDescriptor<PlaybackMetadataModel>(predicate: predicate))) ?? []
        var existingByKey: [String: PlaybackMetadataModel] = [:]
        for model in existing {
            let key = model.mediaKey ?? (model.kpId > 0 ? "kp_\(model.kpId)" : model.detailsId)
            existingByKey[key] = model
        }

        for item in remoteMetadata {
            let key = item.mediaKey ?? (item.kpId > 0 ? "kp_\(item.kpId)" : item.detailsId)
            if let local = existingByKey[key] {
                local.title = item.title
                local.type = item.type
                local.posterUrl = item.posterUrl
                local.backdropUrl = item.backdropUrl
                local.logoUrl = item.logoUrl
                if let t = item.tmdbId { local.tmdbId = t }
            } else {
                let model = PlaybackMetadataModel(
                    userId: userId,
                    kpId: item.kpId,
                    tmdbId: item.tmdbId,
                    detailsId: item.detailsId,
                    title: item.title,
                    type: item.type,
                    posterUrl: item.posterUrl,
                    backdropUrl: item.backdropUrl,
                    logoUrl: item.logoUrl,
                    mediaKey: key
                )
                context.insert(model)
            }
        }

        try? context.save()
    }
}
