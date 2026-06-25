import Foundation

public struct PlaybackSubtitle: Codable, Hashable, Equatable {
    public let url: String
    public let label: String
    public let lang: String
}
