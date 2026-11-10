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
        do {
            try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("Setup failed: cannot create downloads directory: \(error)")
        }
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
        do {
            try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        } catch {
            preconditionFailure("Setup failed: cannot create downloads/movies: \(error)")
        }
        check(LocalMediaPathPolicy.resolve("downloads/movies/../../downloads/x.ts", documents: docs) != nil,
              "internal traversal staying inside downloads is allowed")

        // A symlink pointing outside the downloads boundary must not resolve.
        // Only asserted when the link itself was actually created and its
        // target directory exists; on some runners Foundation refuses to
        // expand links whose final component is missing, which is a testing
        // environment quirk, not a policy property.
        let outside = root.appendingPathComponent("Library")
        do {
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let link = downloads.appendingPathComponent("escape", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
            let linkTarget = FileManager.default.destinationOfSymbolicLink(atPath: link.path)
            precondition(linkTarget != nil, "Setup failed: symlink was not created")
            let linkedSecret = link.appendingPathComponent("secret.txt")
            try? "x".write(to: linkedSecret, atomically: true, encoding: .utf8)
            check(LocalMediaPathPolicy.resolve("downloads/escape/secret.txt", documents: docs) == nil,
                  "symlink escape must be rejected")
        } catch {
            // Setup for the symlink case failed (sandbox restrictions etc.):
            // skip it rather than fail on environment quirks.
        }

        print("Local media path policy: \(count) checks passed")
    }
}
