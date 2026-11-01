import Foundation

@main
struct PosterQualityTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            count += 1
        }

        func adjustUrl(urlStr: String, isLowQuality: Bool, isBackdrop: Bool = false) -> String {
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

            if result.contains("get-kinopoisk-image") || result.contains("mds.yandex.net") {
                if let lastSlashIndex = result.lastIndex(of: "/") {
                    let prefix = result[..<lastSlashIndex]
                    let suffix = isLowQuality ? "300x450" : "orig"
                    result = String(prefix) + "/" + suffix
                }
            } else if result.contains("/api/v1/images/tmdb/") {
                let targetSize = isBackdrop ? (isLowQuality ? "w780" : "original") : (isLowQuality ? "w185" : "w500")
                let pattern = #"/api/v1/images/tmdb/(w\d+|original)/"#
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(result.startIndex..<result.endIndex, in: result)
                    result = regex.stringByReplacingMatches(in: result, options: [], range: range, withTemplate: "/api/v1/images/tmdb/\(targetSize)/")
                }
            } else if result.contains("/api/v1/images/backdrops/") {
                if isLowQuality {
                    result = result.replacingOccurrences(of: "/original", with: "/small")
                    result = result.replacingOccurrences(of: "/large", with: "/small")
                } else {
                    result = result.replacingOccurrences(of: "/small", with: "/original")
                    result = result.replacingOccurrences(of: "/large", with: "/original")
                }
            } else if result.contains("/api/v1/images/kp/") || result.contains("/api/v1/images/kp_small/") {
                if isLowQuality {
                    result = result.replacingOccurrences(of: "/api/v1/images/kp/", with: "/api/v1/images/kp_small/")
                } else {
                    result = result.replacingOccurrences(of: "/api/v1/images/kp_small/", with: "/api/v1/images/kp/")
                }
            }

            return result
        }

        // Test 1: High quality TMDB poster preserves / upgrades to w500
        let h1 = adjustUrl(urlStr: "https://api.sloosh.workers.dev/api/v1/images/tmdb/w500/poster123.jpg", isLowQuality: false)
        check(h1 == "https://api.sloosh.workers.dev/api/v1/images/tmdb/w500/poster123.jpg", "High quality preserves w500")

        let h2 = adjustUrl(urlStr: "https://api.sloosh.workers.dev/api/v1/images/tmdb/w185/poster123.jpg", isLowQuality: false)
        check(h2 == "https://api.sloosh.workers.dev/api/v1/images/tmdb/w500/poster123.jpg", "High quality upgrades w185 to w500")

        let h3 = adjustUrl(urlStr: "https://image.tmdb.org/t/p/w500/poster123.jpg", isLowQuality: false)
        check(h3 == "https://api.sloosh.workers.dev/api/v1/images/tmdb/w500/poster123.jpg", "High quality proxies raw TMDB url")

        // Test 2: Low quality TMDB poster downsizes to w185
        let l1 = adjustUrl(urlStr: "https://api.sloosh.workers.dev/api/v1/images/tmdb/w500/poster123.jpg", isLowQuality: true)
        check(l1 == "https://api.sloosh.workers.dev/api/v1/images/tmdb/w185/poster123.jpg", "Low quality downsizes w500 to w185")

        let l2 = adjustUrl(urlStr: "https://image.tmdb.org/t/p/w500/poster123.jpg", isLowQuality: true)
        check(l2 == "https://api.sloosh.workers.dev/api/v1/images/tmdb/w185/poster123.jpg", "Low quality proxies and downsizes raw TMDB to w185")

        let l3 = adjustUrl(urlStr: "https://api-sloosh.vercel.app/api/v1/images/tmdb/w500/poster123.jpg", isLowQuality: true)
        check(l3 == "https://api.sloosh.workers.dev/api/v1/images/tmdb/w185/poster123.jpg", "Low quality rewrites legacy vercel and downsizes to w185")

        // Test 3: TMDB Backdrop sizing (original vs w780)
        let bHigh = adjustUrl(urlStr: "https://api.sloosh.workers.dev/api/v1/images/tmdb/w780/bg.jpg", isLowQuality: false, isBackdrop: true)
        check(bHigh == "https://api.sloosh.workers.dev/api/v1/images/tmdb/original/bg.jpg", "High quality backdrop upgrades to original")

        let bLow = adjustUrl(urlStr: "https://api.sloosh.workers.dev/api/v1/images/tmdb/original/bg.jpg", isLowQuality: true, isBackdrop: true)
        check(bLow == "https://api.sloosh.workers.dev/api/v1/images/tmdb/w780/bg.jpg", "Low quality backdrop downsizes to w780")

        // Test 4: Kinopoisk Yandex Avatars sizing (orig vs 300x450)
        let kpHigh = adjustUrl(urlStr: "https://avatars.mds.yandex.net/get-kinopoisk-image/123/300x450", isLowQuality: false)
        check(kpHigh == "https://avatars.mds.yandex.net/get-kinopoisk-image/123/orig", "High quality sets Kinopoisk avatar to orig")

        let kpLow = adjustUrl(urlStr: "https://avatars.mds.yandex.net/get-kinopoisk-image/123/orig", isLowQuality: true)
        check(kpLow == "https://avatars.mds.yandex.net/get-kinopoisk-image/123/300x450", "Low quality sets Kinopoisk avatar to 300x450")

        // Test 5: Backend Kinopoisk proxy (/kp/ vs /kp_small/)
        let proxyHigh = adjustUrl(urlStr: "https://api.sloosh.workers.dev/api/v1/images/kp_small/999", isLowQuality: false)
        check(proxyHigh == "https://api.sloosh.workers.dev/api/v1/images/kp/999", "High quality switches kp_small to kp")

        let proxyLow = adjustUrl(urlStr: "https://api.sloosh.workers.dev/api/v1/images/kp/999", isLowQuality: true)
        check(proxyLow == "https://api.sloosh.workers.dev/api/v1/images/kp_small/999", "Low quality switches kp to kp_small")

        // Test 6: Backend Kinopoisk backdrops proxy (/original vs /small)
        let bdHigh = adjustUrl(urlStr: "https://api.sloosh.workers.dev/api/v1/images/backdrops/999/small", isLowQuality: false)
        check(bdHigh == "https://api.sloosh.workers.dev/api/v1/images/backdrops/999/original", "High quality switches backdrop to original")

        let bdLow = adjustUrl(urlStr: "https://api.sloosh.workers.dev/api/v1/images/backdrops/999/original", isLowQuality: true)
        check(bdLow == "https://api.sloosh.workers.dev/api/v1/images/backdrops/999/small", "Low quality switches backdrop to small")

        print("PASS: \(count) poster quality test cases passed successfully")
    }
}
