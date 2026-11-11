import Foundation

/// The durable source has records, not synthetic numeric aliases. Firebase put
/// replaces a subtree, patch merges fields, and null removes it (including root).
struct ArtworkOverrideStore {
    private(set) var document: [String: Any] = [:]

    init(records: [String: MediaArtworkOverride] = [:]) {
        if let data = try? JSONEncoder().encode(records),
           let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            document = value
        }
    }

    private func decode(key: String, value: Any) -> MediaArtworkOverride? {
        guard var object = value as? [String: Any] else { return nil }
        if object["mediaId"] == nil { object["mediaId"] = key }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return try? JSONDecoder().decode(MediaArtworkOverride.self, from: data)
    }

    var records: [String: MediaArtworkOverride] {
        var result: [String: MediaArtworkOverride] = [:]
        for key in document.keys.sorted() {
            guard let item = decode(key: key, value: document[key]!), item.updatedBy != "system" else { continue }
            if let old = result[item.mediaId], (old.updatedAt ?? 0) > (item.updatedAt ?? 0) { continue }
            result[item.mediaId] = item
        }
        return result
    }

    static func resolve(_ records: [MediaArtworkOverride], id: String?, type: String?, tmdbId: Int? = nil, kpId: Int?) -> MediaArtworkOverride? {
        let identity = CatalogArtworkIdentity(id: id, type: type)
            ?? tmdbId.flatMap { CatalogArtworkIdentity(id: String($0), type: type) }
            ?? kpId.flatMap { $0 > 0 ? CatalogArtworkIdentity(id: "kp_\($0)", type: type) : nil }
        guard let identity else { return nil }
        return records.filter { identity.matchesOverride($0, kpId: kpId) }.sorted {
            if ($0.updatedAt ?? 0) != ($1.updatedAt ?? 0) { return ($0.updatedAt ?? 0) > ($1.updatedAt ?? 0) }
            return $0.mediaId < $1.mediaId
        }.first
    }

    func sourceKeys(matching identity: CatalogArtworkIdentity, kpId: Int?) -> [String] {
        document.keys.filter { key in
            guard let item = decode(key: key, value: document[key]!) else { return false }
            return identity.matchesOverride(item, kpId: kpId)
        }.sorted()
    }

    mutating func put(_ item: MediaArtworkOverride) {
        guard let data = try? JSONEncoder().encode(item),
              let object = try? JSONSerialization.jsonObject(with: data) else { return }
        document[item.mediaId] = object
    }

    mutating func remove(keys: [String]) { for key in keys { document[key] = nil } }

    @discardableResult
    mutating func apply(event: String, payload: String) -> Bool {
        guard event == "put" || event == "patch", let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["path"] as? String, let value = object["data"] else { return false }
        let components = path.split(separator: "/").map(String.init)
        if event == "patch", let fields = value as? [String: Any] {
            for (field, child) in fields {
                Self.set(child, at: components + field.split(separator: "/").map(String.init), in: &document)
            }
        } else {
            Self.set(value, at: components, in: &document)
        }
        return true
    }

    private static func set(_ value: Any, at path: [String], in object: inout [String: Any]) {
        guard let first = path.first else {
            object = value as? [String: Any] ?? [:]
            return
        }
        if path.count == 1 {
            object[first] = value is NSNull ? nil : value
        } else {
            var child = object[first] as? [String: Any] ?? [:]
            Self.set(value, at: Array(path.dropFirst()), in: &child)
            object[first] = child.isEmpty ? nil : child
        }
    }
}
