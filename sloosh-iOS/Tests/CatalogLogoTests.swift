import Foundation

@main
struct CatalogLogoTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            count += 1
        }

        func adjustLogo(urlStr: String, targetSize: String = "w300") -> String {
            var result = urlStr
            let base = "https://api.sloosh.workers.dev"

            if result.contains("api-sloosh.vercel.app") {
                result = result.replacingOccurrences(of: "https://api-sloosh.vercel.app", with: base)
                    .replacingOccurrences(of: "http://api-sloosh.vercel.app", with: base)
            }
            if result.contains("image.tmdb.org/t/p/") {
                result = result.replacingOccurrences(of: "https://image.tmdb.org/t/p/", with: "\(base)/api/v1/images/tmdb/")
                    .replacingOccurrences(of: "http://image.tmdb.org/t/p/", with: "\(base)/api/v1/images/tmdb/")
            }

            if result.contains("/api/v1/images/tmdb/") {
                let pattern = #"/api/v1/images/tmdb/(w\d+|original)/"#
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(result.startIndex..<result.endIndex, in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "/api/v1/images/tmdb/\(targetSize)/")
                }
            } else if result.contains("/api/v1/images/logos/") {
                let isSmall = (targetSize == "w300" || targetSize == "small" || targetSize == "w185" || targetSize == "w154")
                let targetSegment = isSmall ? "small" : "original"
                let pattern = #"/api/v1/images/logos/([^/]+)/(original|small|w\d+)"#
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(result.startIndex..<result.endIndex, in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "/api/v1/images/logos/$1/\(targetSegment)")
                }
            }
            return result
        }

        // Test 1: TMDB original logo downscaled to w300 for compact card
        let t1 = adjustLogo(urlStr: "https://api.sloosh.workers.dev/api/v1/images/tmdb/original/logo123.png", targetSize: "w300")
        check(t1 == "https://api.sloosh.workers.dev/api/v1/images/tmdb/w300/logo123.png", "Downscales TMDB original logo to w300")

        // Test 2: Raw TMDB image URL sanitized and downscaled to w300
        let t2 = adjustLogo(urlStr: "https://image.tmdb.org/t/p/original/logo123.png", targetSize: "w300")
        check(t2 == "https://api.sloosh.workers.dev/api/v1/images/tmdb/w300/logo123.png", "Sanitizes raw TMDB logo and downscales to w300")

        // Test 3: Legacy vercel domain sanitized and downscaled
        let t3 = adjustLogo(urlStr: "https://api-sloosh.vercel.app/api/v1/images/tmdb/w500/logo123.png", targetSize: "w300")
        check(t3 == "https://api.sloosh.workers.dev/api/v1/images/tmdb/w300/logo123.png", "Sanitizes legacy vercel URL and sets w300")

        // Test 4: Server logo proxy /original downscaled to /small
        let t4 = adjustLogo(urlStr: "https://api.sloosh.workers.dev/api/v1/images/logos/550/original", targetSize: "w300")
        check(t4 == "https://api.sloosh.workers.dev/api/v1/images/logos/550/small", "Server logo proxy /original converted to /small")

        // Test 5: Server logo proxy preserves /original when targetSize is original (for DetailsView)
        let t5 = adjustLogo(urlStr: "https://api.sloosh.workers.dev/api/v1/images/logos/550/small", targetSize: "original")
        check(t5 == "https://api.sloosh.workers.dev/api/v1/images/logos/550/original", "Server logo proxy /small converted to /original for details")

        // Test 6: TMDB logo preserves original when targetSize is original
        let t6 = adjustLogo(urlStr: "https://api.sloosh.workers.dev/api/v1/images/tmdb/w300/logo123.png", targetSize: "original")
        check(t6 == "https://api.sloosh.workers.dev/api/v1/images/tmdb/original/logo123.png", "TMDB logo upgrades to original for details")

        // Test 7: TV and movie ID prefix stripping for logo resolution
        func cleanMediaId(_ raw: String) -> String {
            raw.replacingOccurrences(of: "kp_", with: "")
                .replacingOccurrences(of: "tmdb_", with: "")
                .replacingOccurrences(of: "tv_", with: "")
                .replacingOccurrences(of: "movie_", with: "")
        }

        check(cleanMediaId("tv_1396") == "1396", "Strips tv_ prefix correctly for TV show logos")
        check(cleanMediaId("movie_550") == "550", "Strips movie_ prefix correctly for movie logos")
        check(cleanMediaId("tmdb_12345") == "12345", "Strips tmdb_ prefix correctly")
        check(cleanMediaId("kp_6789") == "6789", "Strips kp_ prefix correctly")

        // Test 8: Textless poster fallback URL construction
        func resolveCatalogPosterUrl(
            origId: String,
            forLogoMode: Bool,
            overrideTextless: String? = nil,
            dtoTextless: String? = nil,
            standardPoster: String
        ) -> String {
            if forLogoMode {
                if let o = overrideTextless, !o.isEmpty { return o }
                if let d = dtoTextless, !d.isEmpty { return d }
                let validId = cleanMediaId(origId)
                return "https://api.sloosh.workers.dev/api/v1/images/posters/\(validId)/w500/textless"
            }
            return standardPoster
        }

        let standard = "https://api.sloosh.workers.dev/api/v1/images/tmdb/w500/standard_poster.jpg"
        let textlessOverride = "https://api.sloosh.workers.dev/api/v1/images/tmdb/w500/curated_textless.jpg"
        let textlessDto = "https://api.sloosh.workers.dev/api/v1/images/tmdb/w500/dto_textless.jpg"

        // Mode: standard (logos off) -> always returns standard poster
        let r1 = resolveCatalogPosterUrl(origId: "tv_1396", forLogoMode: false, overrideTextless: textlessOverride, dtoTextless: textlessDto, standardPoster: standard)
        check(r1 == standard, "Returns standard poster when logo mode is off")

        // Mode: textless with curated override -> returns curated textless poster
        let r2 = resolveCatalogPosterUrl(origId: "tv_1396", forLogoMode: true, overrideTextless: textlessOverride, dtoTextless: textlessDto, standardPoster: standard)
        check(r2 == textlessOverride, "Prefers curated textless override when logo mode is on")

        // Mode: textless with DTO textless -> returns DTO textless poster
        let r3 = resolveCatalogPosterUrl(origId: "tv_1396", forLogoMode: true, overrideTextless: nil, dtoTextless: textlessDto, standardPoster: standard)
        check(r3 == textlessDto, "Uses DTO textless poster when override is absent")

        // Mode: textless fallback to server textless proxy
        let r4 = resolveCatalogPosterUrl(origId: "tv_1396", forLogoMode: true, overrideTextless: nil, dtoTextless: nil, standardPoster: standard)
        check(r4 == "https://api.sloosh.workers.dev/api/v1/images/posters/1396/w500/textless", "Falls back to server textless proxy with cleaned id")

        print("Catalog logo tests passed: \(count) assertions verified.")
    }
}
