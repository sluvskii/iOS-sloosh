import Foundation

@main
struct LocalMediaPathPolicyTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            count += 1
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let docs = root.appendingPathComponent("Documents")
        let downloads = docs.appendingPathComponent("downloads")
        try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Allowed: everything under the downloads directory.
        for path in ["downloads/movies/1/local.m3u8", "downloads/shows/1/s1_e1/segment.ts",
                     "downloads/movies/1/../1/key.bin", "downloads/a/./b/file.ts"] {
            check(LocalMediaPathPolicy.resolve(path, documents: docs) != nil, "must resolve inside downloads: \(path)")
        }
        // Traversal attempts, including via folders that do not exist on disk.
        for path in ["../Library/Preferences/com.sloosh.ios.plist", "downloads/../../Library/secret",
                     "downloads/../profile.json", "profile.json", "downloads-other/file", "downloads",
                     "downloads/missing/../../../Library/secret"] {
            check(LocalMediaPathPolicy.resolve(path, documents: docs) == nil, "must reject: \(path)")
        }
        // Traversal through a folder that exists but is still inside downloads stays inside.
        let sub = downloads.appendingPathComponent("movies", isDirectory: true)
        try? FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        check(LocalMediaPathPolicy.resolve("downloads/movies/../../downloads/x.ts", documents: docs) != nil,
              "internal traversal staying inside downloads is allowed")

        // Symlink pointing outside the downloads boundary must not resolve.
        let outside = root.appendingPathComponent("Library")
        try? FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(at: downloads.appendingPathComponent("escape"),
                                                    withDestinationURL: outside)
        check(LocalMediaPathPolicy.resolve("downloads/escape/secret", documents: docs) == nil,
              "symlink escape must be rejected")

        print("Local media path policy: \(count) checks passed")
    }
}
