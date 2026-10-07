import Foundation

// MARK: - Media Artwork Override & Image Models

public struct MediaArtworkOverride: Codable, Equatable, Sendable, Identifiable {
    public var id: String { mediaId }
    public let mediaId: String
    public var kpId: Int?
    public var tmdbId: Int?
    public var title: String?
    public var posterUrl: String?
    public var logoUrl: String?
    public var backdropUrl: String?
    public var updatedAt: TimeInterval
    public var updatedBy: String?

    public init(
        mediaId: String,
        kpId: Int? = nil,
        tmdbId: Int? = nil,
        title: String? = nil,
        posterUrl: String? = nil,
        logoUrl: String? = nil,
        backdropUrl: String? = nil,
        updatedAt: TimeInterval = Date().timeIntervalSince1970,
        updatedBy: String? = nil
    ) {
        self.mediaId = mediaId
        self.kpId = kpId
        self.tmdbId = tmdbId
        self.title = title
        self.posterUrl = posterUrl
        self.logoUrl = logoUrl
        self.backdropUrl = backdropUrl
        self.updatedAt = updatedAt
        self.updatedBy = updatedBy
    }
}

public struct MediaImageItemDto: Codable, Identifiable, Equatable, Sendable {
    public var id: String { url }
    public let url: String
    public let filePath: String?
    public let width: Int?
    public let height: Int?
    public let aspectRatio: Double?
    public let iso6391: String?
    public let voteAverage: Double?
    public let voteCount: Int?

    public var fullUrl: String { url }
    public var iso_639_1: String? { iso6391 }

    enum CodingKeys: String, CodingKey {
        case url
        case filePath = "file_path"
        case width
        case height
        case aspectRatio = "aspect_ratio"
        case iso6391 = "iso_639_1"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.url = try container.decode(String.self, forKey: .url)
        self.filePath = try? container.decodeIfPresent(String.self, forKey: .filePath)
        self.width = try? container.decodeIfPresent(Int.self, forKey: .width)
        self.height = try? container.decodeIfPresent(Int.self, forKey: .height)
        self.aspectRatio = try? container.decodeIfPresent(Double.self, forKey: .aspectRatio)
        self.iso6391 = try? container.decodeIfPresent(String.self, forKey: .iso6391)
        self.voteAverage = try? container.decodeIfPresent(Double.self, forKey: .voteAverage)
        self.voteCount = try? container.decodeIfPresent(Int.self, forKey: .voteCount)
    }

    public init(
        url: String,
        filePath: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        aspectRatio: Double? = nil,
        iso6391: String? = nil,
        voteAverage: Double? = nil,
        voteCount: Int? = nil
    ) {
        self.url = url
        self.filePath = filePath
        self.width = width
        self.height = height
        self.aspectRatio = aspectRatio
        self.iso6391 = iso6391
        self.voteAverage = voteAverage
        self.voteCount = voteCount
    }
}

public struct MediaImagesResponseDto: Codable, Sendable {
    public let logos: [MediaImageItemDto]?
    public let posters: [MediaImageItemDto]?
    public let backdrops: [MediaImageItemDto]?

    public init(
        logos: [MediaImageItemDto]? = nil,
        posters: [MediaImageItemDto]? = nil,
        backdrops: [MediaImageItemDto]? = nil
    ) {
        self.logos = logos
        self.posters = posters
        self.backdrops = backdrops
    }
}
