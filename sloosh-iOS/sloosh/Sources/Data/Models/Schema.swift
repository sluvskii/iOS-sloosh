import Foundation
import SwiftData

@Model
final class ProgressRecordModel {
    @Attribute(.unique) var userMediaIdKey: String // composite key: "<userId>_<mediaId>"
    var userId: String
    var mediaId: String
    var kpId: Int
    var season: Int?
    var episode: Int?
    var positionSec: Double
    var durationSec: Double
    var watched: Bool
    var updatedAtMs: Int

    init(userId: String = "guest", mediaId: String, kpId: Int, season: Int? = nil, episode: Int? = nil, positionSec: Double = 0, durationSec: Double = 0, watched: Bool = false, updatedAtMs: Int) {
        self.userId = userId
        self.mediaId = mediaId
        self.userMediaIdKey = "\(userId)_\(mediaId)"
        self.kpId = kpId
        self.season = season
        self.episode = episode
        self.positionSec = positionSec
        self.durationSec = durationSec
        self.watched = watched
        self.updatedAtMs = updatedAtMs
    }
}

@Model
final class PlaybackMetadataModel {
    @Attribute(.unique) var userKpIdKey: String // composite key: "<userId>_<kpId>"
    var userId: String
    var kpId: Int
    var detailsId: String
    var title: String
    var type: String?
    var posterUrl: String?
    var backdropUrl: String?
    var logoUrl: String?

    init(userId: String = "guest", kpId: Int, detailsId: String, title: String, type: String? = nil, posterUrl: String? = nil, backdropUrl: String? = nil, logoUrl: String? = nil) {
        self.userId = userId
        self.kpId = kpId
        self.userKpIdKey = "\(userId)_\(kpId)"
        self.detailsId = detailsId
        self.title = title
        self.type = type
        self.posterUrl = posterUrl
        self.backdropUrl = backdropUrl
        self.logoUrl = logoUrl
    }
}

@Model
final class LastPlayedVoiceoverModel {
    @Attribute(.unique) var userSourceKey: String // composite key: "<userId>_<key>"
    var userId: String
    var key: String // e.g. "alloha_12345"
    var source: String
    var voiceover: String

    init(userId: String = "guest", key: String, source: String, voiceover: String) {
        self.userId = userId
        self.key = key
        self.userSourceKey = "\(userId)_\(key)"
        self.source = source
        self.voiceover = voiceover
    }
}

@Model
final class LastPlayedEpisodeModel {
    @Attribute(.unique) var userKpIdKey: String // composite key: "<userId>_<kpId>"
    var userId: String
    var kpId: Int
    var season: Int?
    var episode: Int?
    
    init(userId: String = "guest", kpId: Int, season: Int? = nil, episode: Int? = nil) {
        self.userId = userId
        self.kpId = kpId
        self.userKpIdKey = "\(userId)_\(kpId)"
        self.season = season
        self.episode = episode
    }
}

@Model
final class FavoriteModel {
    @Attribute(.unique) var userMediaIdTypeKey: String // composite key: "<userId>_<mediaId>_<type>"
    var userId: String
    var mediaId: String
    var type: String
    var title: String?
    var posterUrl: String?
    var rating: Double?
    var year: String?
    var genresRaw: String? // JSON encoded
    var addedAt: Date
    
    init(userId: String = "guest", mediaId: String, type: String, title: String? = nil, posterUrl: String? = nil, rating: Double? = nil, year: String? = nil, genresRaw: String? = nil, addedAt: Date = Date()) {
        self.userId = userId
        self.mediaId = mediaId
        self.type = type
        self.userMediaIdTypeKey = "\(userId)_\(mediaId)_\(type)"
        self.title = title
        self.posterUrl = posterUrl
        self.rating = rating
        self.year = year
        self.genresRaw = genresRaw
        self.addedAt = addedAt
    }
}
