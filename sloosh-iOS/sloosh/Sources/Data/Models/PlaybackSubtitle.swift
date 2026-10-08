import Foundation

public struct PlaybackSubtitle: Codable, Hashable, Equatable, Sendable {
    public let url: String
    public let label: String
    public let lang: String
}
