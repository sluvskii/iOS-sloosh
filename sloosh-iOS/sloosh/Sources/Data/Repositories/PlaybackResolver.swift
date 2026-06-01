import Foundation

@MainActor
class PlaybackResolver {
    
    struct ResolutionResult {
        let headers: [String: String]
        let qualities: [(key: String, url: URL)]
        let originalUrl: URL
    }
    
    static func resolveAlloha(iframeUrl: String) async throws -> ResolutionResult {
        let resolver = AllohaRuntimeResolver()
        let resolved = try await resolver.resolve(iframeUrl: iframeUrl)
        
        guard let resolvedUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let resolvedUrl = URL(string: resolvedUrlString) else {
            throw URLError(.badURL)
        }
        
        let headers = (resolved["headers"] as? [String: String]) ?? [:]
        var qualities = [(key: "Авто", url: resolvedUrl)]
        var seenKeys = Set<String>(["Авто"])
        
        let qualityVariants = (resolved["qualityVariants"] as? [[String: Any]]) ?? []
        appendQualityVariants(qualityVariants, to: &qualities, seenKeys: &seenKeys)
        
        if qualities.count == 1,
           let audioVariants = resolved["audioVariants"] as? [[String: Any]],
           let firstAudio = audioVariants.first,
           let nestedQualityVariants = firstAudio["qualityVariants"] as? [[String: Any]] {
            appendQualityVariants(nestedQualityVariants, to: &qualities, seenKeys: &seenKeys)
        }
        
        if qualities.count > 1 {
            let autoQuality = qualities.removeFirst()
            qualities.sort { (a, b) -> Bool in
                let valA = Int(a.key.replacingOccurrences(of: "p", with: "")) ?? 0
                let valB = Int(b.key.replacingOccurrences(of: "p", with: "")) ?? 0
                return valA > valB
            }
            qualities.insert(autoQuality, at: 0)
        }
        
        return ResolutionResult(headers: headers, qualities: qualities, originalUrl: resolvedUrl)
    }
    
    static func resolveDirect(url: String) async throws -> ResolutionResult {
        guard let parsedUrl = URL(string: url) else {
            throw URLError(.badURL)
        }
        
        let headers = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
            "Referer": "https://kinokrad.my/",
            "Origin": "https://kinokrad.my"
        ]
        
        var qualities = [(key: "Авто", url: parsedUrl)]
        
        do {
            var request = URLRequest(url: parsedUrl)
            headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
            let (data, _) = try await URLSession.shared.data(for: request)
            if let content = String(data: data, encoding: .utf8) {
                let parsedQualities = parseMasterPlaylist(content: content, baseUrl: parsedUrl)
                if parsedQualities.count > 1 {
                    qualities = parsedQualities
                }
            }
        } catch {
            print("PlaybackResolver: Failed to fetch master playlist: \(error)")
        }
        
        return ResolutionResult(headers: headers, qualities: qualities, originalUrl: parsedUrl)
    }
    
    private static func parseMasterPlaylist(content: String, baseUrl: URL) -> [(key: String, url: URL)] {
        var qualities: [(key: String, url: URL)] = []
        qualities.append(("Авто", baseUrl))
        
        let lines = content.components(separatedBy: .newlines)
        var currentResolution: String?
        
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                var resStr = "Поток"
                if let range = line.range(of: "RESOLUTION=([^,\\s]+)", options: .regularExpression) {
                    let match = String(line[range])
                    let res = match.replacingOccurrences(of: "RESOLUTION=", with: "")
                    let components = res.components(separatedBy: "x")
                    if components.count == 2, let height = Int(components[1]) {
                        resStr = "\(height)p"
                    }
                } else if let range = line.range(of: "BANDWIDTH=([^,\\s]+)", options: .regularExpression) {
                    let match = String(line[range])
                    let bw = match.replacingOccurrences(of: "BANDWIDTH=", with: "")
                    if let bandwidth = Int(bw) {
                        resStr = "\(bandwidth / 1000) kbps"
                    }
                }
                currentResolution = resStr
            } else if !line.hasPrefix("#") && !line.isEmpty {
                if let res = currentResolution {
                    let variantUrl: URL
                    if line.hasPrefix("http") {
                        variantUrl = URL(string: line)!
                    } else {
                        variantUrl = URL(string: line, relativeTo: baseUrl)!
                    }
                    if !qualities.contains(where: { $0.key == res }) {
                        qualities.append((res, variantUrl))
                    } else {
                        let uniqueRes = "\(res) (\(qualities.count))"
                        qualities.append((uniqueRes, variantUrl))
                    }
                    currentResolution = nil
                }
            }
        }
        
        if qualities.count > 1 {
            let autoQuality = qualities.removeFirst()
            qualities.sort { (a, b) -> Bool in
                let valA = Int(a.key.replacingOccurrences(of: "p", with: "")) ?? 0
                let valB = Int(b.key.replacingOccurrences(of: "p", with: "")) ?? 0
                return valA > valB
            }
            qualities.insert(autoQuality, at: 0)
        }
        
        return qualities
    }
    
    private static func appendQualityVariants(_ variants: [[String: Any]], to qualities: inout [(key: String, url: URL)], seenKeys: inout Set<String>) {
        for variant in variants {
            guard let urlString = variant["url"] as? String,
                  let url = URL(string: urlString),
                  !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let label = normalizedQualityLabel(from: variant["label"] as? String)
            guard seenKeys.insert(label).inserted else { continue }
            qualities.append((key: label, url: url))
        }
    }
    
    private static func normalizedQualityLabel(from rawLabel: String?) -> String {
        let label = (rawLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return "Поток" }
        if label.lowercased().hasSuffix("p") { return label }
        if Int(label) != nil { return "\(label)p" }
        return label
    }
}
