import Foundation

/// Shared by the HTTP proxy and its standalone regression tests.
enum LocalMediaPathPolicy {
    /// Lexically removes `.`/`..` segments even when the referenced
    /// directories do not (yet) exist, so prefix checks cannot be fooled.
    private static func normalized(_ url: URL) -> URL {
        var path = url.path
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        var resolved: [String] = []
        for component in components {
            if component == "." { continue }
            if component == ".." {
                if !resolved.isEmpty { resolved.removeLast() }
                continue
            }
            resolved.append(String(component))
        }
        path = "/" + resolved.joined(separator: "/")
        return URL(fileURLWithPath: path)
    }

    static func resolve(_ relativePath: String, documents: URL) -> URL? {
        let downloads = normalized(
            documents.appendingPathComponent("downloads", isDirectory: true)
        )
        // 1. Lexical normalization defeats `../` regardless of what exists on disk.
        let lexical = normalized(documents.appendingPathComponent(relativePath))
        guard lexical.path.hasPrefix(downloads.path + "/") else { return nil }
        // 2. Resolve symlinks, then re-normalize: a link may point back outside.
        // The boundary is resolved the same way (/var vs /private/var aliases).
        let resolvedDownloads = normalized(downloads.resolvingSymlinksInPath())
        let resolved = normalized(lexical.resolvingSymlinksInPath())
        guard resolved.path.hasPrefix(resolvedDownloads.path + "/") else { return nil }
        return resolved
    }
}
