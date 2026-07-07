import Foundation

struct DownloadManifest: Codable {
    let itemId: String
    let segmentUrls: [URL]
    let headers: [String: String]
    let keyUrl: URL?
    let localDirectory: String
}
