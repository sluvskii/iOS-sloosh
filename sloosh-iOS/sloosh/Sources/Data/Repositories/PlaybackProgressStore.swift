import Foundation
import SwiftData
import SwiftUI
import Combine

public struct PlaybackProgressRecord: Identifiable, Codable {
    public let mediaId: String
    public let kpId: Int
    public let season: Int?
    public let episode: Int?
    public var positionSec: Double
    public var durationSec: Double
    public var watched: Bool
    public var updatedAtMs: Int

    public var id: String { mediaId }

    public var isEpisode: Bool {
        season != nil && episode != nil
    }

    public var progressFraction: Double {
        guard durationSec.isFinite, durationSec > 0, positionSec.isFinite else { return 0 }
        return max(0, min(positionSec / durationSec, 0.999))
    }

    public init(mediaId: String, kpId: Int, season: Int? = nil, episode: Int? = nil, positionSec: Double = 0, durationSec: Double = 0, watched: Bool = false, updatedAtMs: Int = Int(Date().timeIntervalSince1970 * 1000)) {
        self.mediaId = mediaId
        self.kpId = kpId
        self.season = season
        self.episode = episode
        self.positionSec = positionSec
        self.durationSec = durationSec
        self.watched = watched
        self.updatedAtMs = updatedAtMs
    }
}

public struct PlaybackMediaMetadata: Codable {
    public let kpId: Int
    public let detailsId: String
    public let title: String
    public let type: String?
    public let posterUrl: String?
    public let backdropUrl: String?
    public let logoUrl: String?

    public init(kpId: Int, detailsId: String, title: String, type: String? = nil, posterUrl: String? = nil, backdropUrl: String? = nil, logoUrl: String? = nil) {
        self.kpId = kpId
        self.detailsId = detailsId
        self.title = title
        self.type = type
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
    }
}

@MainActor
public final class PlaybackProgressStore: ObservableObject {
    public static let shared = PlaybackProgressStore()
    
    private var context: ModelContext { AppDatabase.shared.container.mainContext }
    private var cancellables = Set<AnyCancellable>()

    private static let episodeRegex = try! NSRegularExpression(pattern: "^kp_(\\d+)_s(\\d+)_e(\\d+)$")
    private static let movieRegex   = try! NSRegularExpression(pattern: "^kp_(\\d+)$")

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
            season: model.season,
            episode: model.episode,
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
        } else {
            let newModel = ProgressRecordModel(
                userId: activeUserId,
                mediaId: record.mediaId,
                kpId: record.kpId,
                season: record.season,
                episode: record.episode,
                positionSec: record.positionSec,
                durationSec: record.durationSec,
                watched: record.watched,
                updatedAtMs: record.updatedAtMs
            )
            context.insert(newModel)
        }

        let now = Date()
        if forceDiskSave || now.timeIntervalSince(lastDiskSaveDate) >= 15.0 {
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
        var season: Int? = nil
        var episode: Int? = nil

        if let match = Self.episodeRegex.firstMatch(in: mediaId, range: range) {
            if let kpRange = Range(match.range(at: 1), in: mediaId),
               let seasonRange = Range(match.range(at: 2), in: mediaId),
               let episodeRange = Range(match.range(at: 3), in: mediaId) {
                kpId = Int(mediaId[kpRange]) ?? 0
                season = Int(mediaId[seasonRange])
                episode = Int(mediaId[episodeRange])
            }
        } else if let match = Self.movieRegex.firstMatch(in: mediaId, range: range) {
            if let kpRange = Range(match.range(at: 1), in: mediaId) {
                kpId = Int(mediaId[kpRange]) ?? 0
            }
        }

        return PlaybackProgressRecord(
            mediaId: mediaId,
            kpId: kpId,
            season: season,
            episode: episode,
            positionSec: 0,
            durationSec: 0,
            watched: false,
            updatedAtMs: Int(Date().timeIntervalSince1970 * 1000)
        )
    }

    public func save(mediaId: String, positionSec: Double, durationSec: Double? = nil, forceDiskSave: Bool = false) {
        guard !mediaId.isEmpty, positionSec.isFinite, positionSec >= 0 else { return }
        mutateRecord(mediaId: mediaId, forceDiskSave: forceDiskSave) { record in
            record.positionSec = positionSec
            if let dur = durationSec, dur > 0, dur.isFinite {
                record.durationSec = dur
                if positionSec / dur >= 0.9 {
                    record.watched = true
                }
            }
        }
    }

    public func load(mediaId: String) -> Double {
        guard !mediaId.isEmpty else { return 0 }
        return getRecord(mediaId: mediaId)?.positionSec ?? 0
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
        kpId: Int,
        detailsId: String,
        title: String,
        type: String?,
        posterUrl: String?,
        backdropUrl: String?,
        logoUrl: String?
    ) {
        guard kpId > 0, !detailsId.isEmpty, !title.isEmpty else { return }
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(kpId)"

        let descriptor = FetchDescriptor<PlaybackMetadataModel>(predicate: #Predicate { $0.userKpIdKey == compositeKey })
        if let model = try? context.fetch(descriptor).first {
            model.detailsId = detailsId
            model.title = title
            model.type = type
            model.posterUrl = posterUrl
            model.backdropUrl = backdropUrl
            model.logoUrl = logoUrl
        } else {
            let model = PlaybackMetadataModel(
                userId: activeUserId,
                kpId: kpId,
                detailsId: detailsId,
                title: title,
                type: type,
                posterUrl: posterUrl,
                backdropUrl: backdropUrl,
                logoUrl: logoUrl
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

    func saveMetadata(details: MediaDetailsDto) {
        guard let kpId = details.ids?.kp else { return }

        let detailsId = details.id ?? String(kpId)
        let title = details.title ?? details.originalTitle ?? "Без названия"

        saveMetadata(
            kpId: kpId,
            detailsId: detailsId,
            title: title,
            type: details.type,
            posterUrl: details.displayPosterUrl,
            backdropUrl: details.displayBackdropUrl ?? details.displayPosterUrl,
            logoUrl: details.displayLogoUrl
        )
    }

    public func loadMetadata(kpId: Int) -> PlaybackMediaMetadata? {
        guard kpId > 0 else { return nil }
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(kpId)"
        let descriptor = FetchDescriptor<PlaybackMetadataModel>(predicate: #Predicate { $0.userKpIdKey == compositeKey })
        guard let model = try? context.fetch(descriptor).first else { return nil }
        return PlaybackMediaMetadata(
            kpId: model.kpId,
            detailsId: model.detailsId,
            title: model.title,
            type: model.type,
            posterUrl: model.posterUrl,
            backdropUrl: model.backdropUrl,
            logoUrl: model.logoUrl
        )
    }

    public func listAllMetadata() -> [PlaybackMediaMetadata] {
        let activeUserId = currentUserId
        let descriptor = FetchDescriptor<PlaybackMetadataModel>(predicate: #Predicate { $0.userId == activeUserId })
        let models = (try? context.fetch(descriptor)) ?? []
        return models.map {
            PlaybackMediaMetadata(
                kpId: $0.kpId,
                detailsId: $0.detailsId,
                title: $0.title,
                type: $0.type,
                posterUrl: $0.posterUrl,
                backdropUrl: $0.backdropUrl,
                logoUrl: $0.logoUrl
            )
        }
    }

    public func listProgressRecords(kpId: Int? = nil) -> [PlaybackProgressRecord] {
        let activeUserId = currentUserId
        let descriptor = FetchDescriptor<ProgressRecordModel>(
            predicate: #Predicate { $0.userId == activeUserId },
            sortBy: [SortDescriptor(\.updatedAtMs, order: .reverse)]
        )
        let allModels = (try? context.fetch(descriptor)) ?? []
        
        var results: [PlaybackProgressRecord] = []
        var seriesKpIds = Set<Int>()
        
        // Episodes first
        for model in allModels {
            let isEpisode = model.season != nil && model.episode != nil
            if isEpisode {
                if let filterKpId = kpId, model.kpId != filterKpId { continue }
                seriesKpIds.insert(model.kpId)
                results.append(PlaybackProgressRecord(mediaId: model.mediaId, kpId: model.kpId, season: model.season, episode: model.episode, positionSec: model.positionSec, durationSec: model.durationSec, watched: model.watched, updatedAtMs: model.updatedAtMs))
            }
        }
        
        // Movies
        for model in allModels {
            let isEpisode = model.season != nil && model.episode != nil
            if !isEpisode {
                if let filterKpId = kpId, model.kpId != filterKpId { continue }
                if seriesKpIds.contains(model.kpId) { continue }
                results.append(PlaybackProgressRecord(mediaId: model.mediaId, kpId: model.kpId, season: model.season, episode: model.episode, positionSec: model.positionSec, durationSec: model.durationSec, watched: model.watched, updatedAtMs: model.updatedAtMs))
            }
        }
        
        return results.sorted { $0.updatedAtMs > $1.updatedAtMs }
    }

    public func saveLastVoiceover(kpId: Int, source: String, voiceover: String?) {
        let activeUserId = currentUserId
        let key = "neomovies.\(source).lastVoiceover.kp_\(kpId)"
        let compositeKey = "\(activeUserId)_\(key)"
        let descriptor = FetchDescriptor<LastPlayedVoiceoverModel>(predicate: #Predicate { $0.userSourceKey == compositeKey })
        
        if let v = voiceover {
            if let model = try? context.fetch(descriptor).first {
                model.voiceover = v
            } else {
                context.insert(LastPlayedVoiceoverModel(userId: activeUserId, key: key, source: source, voiceover: v))
            }
        } else {
            if let model = try? context.fetch(descriptor).first {
                context.delete(model)
            }
        }
        try? context.save()
    }

    public func loadLastVoiceover(kpId: Int, source: String) -> String? {
        let activeUserId = currentUserId
        let key = "neomovies.\(source).lastVoiceover.kp_\(kpId)"
        let compositeKey = "\(activeUserId)_\(key)"
        let descriptor = FetchDescriptor<LastPlayedVoiceoverModel>(predicate: #Predicate { $0.userSourceKey == compositeKey })
        return try? context.fetch(descriptor).first?.voiceover
    }

    public func saveLastPlayed(kpId: Int, season: Int?, episode: Int?) {
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(kpId)"
        let descriptor = FetchDescriptor<LastPlayedEpisodeModel>(predicate: #Predicate { $0.userKpIdKey == compositeKey })
        if let model = try? context.fetch(descriptor).first {
            if let s = season { model.season = s }
            if let e = episode { model.episode = e }
        } else {
            context.insert(LastPlayedEpisodeModel(userId: activeUserId, kpId: kpId, season: season, episode: episode))
        }
        try? context.save()
    }

    public func loadLastSeason(kpId: Int) -> Int? {
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(kpId)"
        let descriptor = FetchDescriptor<LastPlayedEpisodeModel>(predicate: #Predicate { $0.userKpIdKey == compositeKey })
        return try? context.fetch(descriptor).first?.season
    }

    public func loadLastEpisode(kpId: Int) -> Int? {
        let activeUserId = currentUserId
        let compositeKey = "\(activeUserId)_\(kpId)"
        let descriptor = FetchDescriptor<LastPlayedEpisodeModel>(predicate: #Predicate { $0.userKpIdKey == compositeKey })
        return try? context.fetch(descriptor).first?.episode
    }

    private func syncRemoteProgressToLocal(_ remoteRecords: [PlaybackProgressRecord], userId: String) async {
        let predicate = #Predicate<ProgressRecordModel> { $0.userId == userId }
        if let existing = try? context.fetch(FetchDescriptor<ProgressRecordModel>(predicate: predicate)) {
            for model in existing {
                context.delete(model)
            }
        }

        for record in remoteRecords {
            let model = ProgressRecordModel(
                userId: userId,
                mediaId: record.mediaId,
                kpId: record.kpId,
                season: record.season,
                episode: record.episode,
                positionSec: record.positionSec,
                durationSec: record.durationSec,
                watched: record.watched,
                updatedAtMs: record.updatedAtMs
            )
            context.insert(model)
        }

        try? context.save()
    }

    private func syncRemoteMetadataToLocal(_ remoteMetadata: [PlaybackMediaMetadata], userId: String) async {
        let predicate = #Predicate<PlaybackMetadataModel> { $0.userId == userId }
        if let existing = try? context.fetch(FetchDescriptor<PlaybackMetadataModel>(predicate: predicate)) {
            for model in existing {
                context.delete(model)
            }
        }

        for item in remoteMetadata {
            let model = PlaybackMetadataModel(
                userId: userId,
                kpId: item.kpId,
                detailsId: item.detailsId,
                title: item.title,
                type: item.type,
                posterUrl: item.posterUrl,
                backdropUrl: item.backdropUrl,
                logoUrl: item.logoUrl
            )
            context.insert(model)
        }

        try? context.save()
    }
}
