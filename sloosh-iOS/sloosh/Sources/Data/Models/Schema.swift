import Foundation
import SwiftData

@Model
final class ProgressRecordModel {
    @Attribute(.unique) var mediaId: String
    var kpId: Int
    var season: Int?
    var episode: Int?
    var positionSec: Double
    var durationSec: Double
    var watched: Bool
    var updatedAtMs: Int

    init(mediaId: String, kpId: Int, season: Int? = nil, episode: Int? = nil, positionSec: Double = 0, durationSec: Double = 0, watched: Bool = false, updatedAtMs: Int) {
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

@Model
final class PlaybackMetadataModel {
    @Attribute(.unique) var kpId: Int
    var detailsId: String
    var title: String
    var type: String?
    var posterUrl: String?
    var backdropUrl: String?
    var logoUrl: String?

    init(kpId: Int, detailsId: String, title: String, type: String? = nil, posterUrl: String? = nil, backdropUrl: String? = nil, logoUrl: String? = nil) {
        self.kpId = kpId
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
    @Attribute(.unique) var key: String // e.g. "alloha_12345"
    var source: String
    var voiceover: String

    init(key: String, source: String, voiceover: String) {
        self.key = key
        self.source = source
        self.voiceover = voiceover
    }
}

@Model
final class LastPlayedEpisodeModel {
    @Attribute(.unique) var kpId: Int
    var season: Int?
    var episode: Int?
    
    init(kpId: Int, season: Int? = nil, episode: Int? = nil) {
        self.kpId = kpId
        self.season = season
        self.episode = episode
    }
}

@Model
final class FavoriteModel {
    @Attribute(.unique) var mediaIdTypeKey: String // composite key: "12345_movie"
    var mediaId: String
    var type: String
    var title: String?
    var posterUrl: String?
    var rating: Double?
    var year: String?
    var genresRaw: String? // JSON encoded
    
    init(mediaId: String, type: String, title: String? = nil, posterUrl: String? = nil, rating: Double? = nil, year: String? = nil, genresRaw: String? = nil) {
        self.mediaIdTypeKey = "\(mediaId)_\(type)"
        self.mediaId = mediaId
        self.type = type
        self.title = title
        self.posterUrl = posterUrl
        self.rating = rating
        self.year = year
        self.genresRaw = genresRaw
    }
}
