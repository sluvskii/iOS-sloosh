import Foundation

public struct CollapsSubtitle: Codable {
    public let url: String
    public let label: String
    public let language: String
    
    public init(url: String, label: String, language: String) {
        self.url = url
        self.label = label
        self.language = language
    }
}

public struct CollapsPlaylist: Codable {
    public let primaryUrl: String
    public let hlsUrl: String?
    public let dashUrl: String?
    public let voiceovers: [String]
    public let subtitles: [CollapsSubtitle]
    
    public init(primaryUrl: String, hlsUrl: String?, dashUrl: String?, voiceovers: [String], subtitles: [CollapsSubtitle]) {
        self.primaryUrl = primaryUrl
        self.hlsUrl = hlsUrl
        self.dashUrl = dashUrl
        self.voiceovers = voiceovers
        self.subtitles = subtitles
    }
}

public struct CollapsEpisode: Codable {
    public let season: Int
    public let episode: Int
    public let title: String
    public let playlist: CollapsPlaylist
    
    public init(season: Int, episode: Int, title: String, playlist: CollapsPlaylist) {
        self.season = season
        self.episode = episode
        self.title = title
        self.playlist = playlist
    }
}

public struct CollapsSeason: Codable {
    public let season: Int
    public let title: String
    public let episodes: [CollapsEpisode]
    
    public init(season: Int, title: String, episodes: [CollapsEpisode]) {
        self.season = season
        self.title = title
        self.episodes = episodes
    }
}

public enum CollapsCatalog: Codable {
    case movie(source: String, playlist: CollapsPlaylist)
    case series(source: String, seasons: [CollapsSeason])
    
    enum CodingKeys: String, CodingKey {
        case kind, source, playlist, seasons
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(String.self, forKey: .kind)
        let source = try container.decode(String.self, forKey: .source)
        
        switch kind {
        case "movie":
            let playlist = try container.decode(CollapsPlaylist.self, forKey: .playlist)
            self = .movie(source: source, playlist: playlist)
        case "series":
            let seasons = try container.decode([CollapsSeason].self, forKey: .seasons)
            self = .series(source: source, seasons: seasons)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: container, debugDescription: "Unknown kind: \(kind)")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .movie(let source, let playlist):
            try container.encode("movie", forKey: .kind)
            try container.encode(source, forKey: .source)
            try container.encode(playlist, forKey: .playlist)
        case .series(let source, let seasons):
            try container.encode("series", forKey: .kind)
            try container.encode(source, forKey: .source)
            try container.encode(seasons, forKey: .seasons)
        }
    }
}
