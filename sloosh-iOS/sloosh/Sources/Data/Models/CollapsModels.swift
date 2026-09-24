import Foundation

struct EpisodeKey: Hashable, Codable, Sendable {
    let season: Int
    let episode: Int
    
    init(season: Int, episode: Int) {
        self.season = season
        self.episode = episode
    }
}

struct CollapsSubtitle: Codable, Hashable, Equatable {
    let url: String
    let label: String
    let language: String
    
    init(url: String, label: String, language: String) {
        self.url = url
        self.label = label
        self.language = language
    }
}

struct CollapsPlaylist: Codable, Hashable, Equatable {
    let primaryUrl: String
    let hlsUrl: String?
    let dashUrl: String?
    let voiceovers: [String]
    let subtitles: [CollapsSubtitle]
    
    init(primaryUrl: String, hlsUrl: String?, dashUrl: String?, voiceovers: [String], subtitles: [CollapsSubtitle]) {
        self.primaryUrl = primaryUrl
        self.hlsUrl = hlsUrl
        self.dashUrl = dashUrl
        self.voiceovers = voiceovers
        self.subtitles = subtitles
    }
}

struct CollapsEpisode: Codable, Hashable, Equatable {
    let season: Int
    let episode: Int
    let title: String
    let playlist: CollapsPlaylist
    
    init(season: Int, episode: Int, title: String, playlist: CollapsPlaylist) {
        self.season = season
        self.episode = episode
        self.title = title
        self.playlist = playlist
    }
}

struct CollapsSeason: Codable, Hashable, Equatable {
    let season: Int
    let title: String
    let episodes: [CollapsEpisode]
    
    init(season: Int, title: String, episodes: [CollapsEpisode]) {
        self.season = season
        self.title = title
        self.episodes = episodes
    }
}

enum CollapsCatalog: Codable, Hashable, Equatable {
    case movie(source: String, playlist: CollapsPlaylist)
    case series(source: String, seasons: [CollapsSeason])
    
    enum CodingKeys: String, CodingKey {
        case kind, source, playlist, seasons
    }
    
    init(from decoder: Decoder) throws {
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
    
    func encode(to encoder: Encoder) throws {
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
