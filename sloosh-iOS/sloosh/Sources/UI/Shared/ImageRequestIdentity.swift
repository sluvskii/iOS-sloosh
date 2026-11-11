import Foundation

/// Both URLs and policy define one image state. A new request must never display
/// a previous primary/fallback image just because SwiftUI reused the same cell.
struct ImageRequestIdentity: Hashable {
    let primary: URL?
    let fallback: URL?
    let policy: UInt
    let revision: Int
}

struct ImageFailureBackoff {
    private var failures: [String: Date] = [:]
    var lifetime: TimeInterval = 60

    mutating func contains(_ key: String, at now: Date = Date()) -> Bool {
        guard let failed = failures[key] else { return false }
        guard now.timeIntervalSince(failed) < lifetime else { failures[key] = nil; return false }
        return true
    }
    mutating func insert(_ key: String, at now: Date = Date()) {
        if failures.count > 1000 { failures = failures.filter { now.timeIntervalSince($0.value) < lifetime } }
        failures[key] = now
    }
    mutating func clear() { failures.removeAll() }
}
