import Foundation

/// Shared by the HTTP proxy and its standalone regression tests.
enum LocalMediaPathPolicy {
    static func resolve(_ relativePath: String, documents: URL) -> URL? {
        let downloads = documents.appendingPathComponent("downloads", isDirectory: true)
            .resolvingSymlinksInPath().standardizedFileURL
        let candidate = documents.appendingPathComponent(relativePath)
            .resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(downloads.path + "/") else { return nil }
        return candidate
    }
}
