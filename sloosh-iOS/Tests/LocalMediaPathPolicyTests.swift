import Foundation

@main
struct LocalMediaPathPolicyTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let docs = root.appendingPathComponent("Documents")
        let downloads = docs.appendingPathComponent("downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for path in ["downloads/movies/1/local.m3u8", "downloads/shows/1/s1_e1/segment.ts",
                     "downloads/movies/1/../1/key.bin"] {
            precondition(LocalMediaPathPolicy.resolve(path, documents: docs) != nil, path)
        }
        for path in ["../Library/Preferences/com.sloosh.ios.plist", "downloads/../../Library/secret",
                     "downloads/../profile.json", "profile.json", "downloads-other/file", "downloads"] {
            precondition(LocalMediaPathPolicy.resolve(path, documents: docs) == nil, path)
        }
        let outside = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: downloads.appendingPathComponent("escape"),
                                                   withDestinationURL: outside)
        precondition(LocalMediaPathPolicy.resolve("downloads/escape/secret", documents: docs) == nil)
        print("Local media path policy tests passed")
    }
}
