import Foundation

@main
struct CatalogLogoTests {
    @MainActor
    static func main() async throws {
        var count = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            count += 1
        }
        // The actual layout policy is shared by cards, settings previews and
        // loading skeletons; test hidden metadata reclaiming the whole caption.
        for overlay in [false, true] {
            for scale in [CGFloat(1), 1.4, 2] {
                let shown = CatalogCaptionLayout(isOverlay: overlay, showsMetadata: true, scale: scale)
                let hidden = CatalogCaptionLayout(isOverlay: overlay, showsMetadata: false, scale: scale)
                check(shown.totalHeight == hidden.totalHeight, "Grid height must not jump on metadata toggle")
                check(hidden.titleAreaHeight == shown.titleHeight + shown.spacing + shown.metadataHeight,
                      "Logo must inherit all previous title/year/genre space")
                check(hidden.titleAreaHeight > shown.titleAreaHeight, "Logo area grows with hidden metadata")
                check(shown.titleLineLimit == 1 && hidden.titleLineLimit == 2, "No-logo/loading/error fallback can use two lines")
                for metadataVisible in [false, true] {
                    let layout = CatalogCaptionLayout(isOverlay: overlay, showsMetadata: metadataVisible, scale: scale)
                    for width in [CGFloat(69), 95, 160] {
                        for original in [CGSize(width: 600, height: 100), CGSize(width: 200, height: 180), CGSize(width: 100, height: 400)] {
                            let size = layout.fittedLogoSize(imageSize: original, availableWidth: width)
                            check(size.width <= width + 0.001 && size.height <= layout.titleAreaHeight + 0.001,
                                  "Wide/tall logo must fit compact/regular caption bounds")
                            check(abs(size.width / size.height - original.width / original.height) < 0.001,
                                  "Logo aspect ratio must be preserved")
                            check(abs(size.width - width) < 0.001 || abs(size.height - layout.titleAreaHeight) < 0.001,
                                  "Logo uses the maximum possible caption area")
                        }
                    }
                    check(layout.fittedLogoSize(imageSize: .zero, availableWidth: 95) == .zero, "Invalid logo dimensions fail safely")
                }
            }
        }
        check(CatalogCaptionLayout.metadataText(year: "2026", genre: "Драма") == "2026, Драма", "Year and genre")
        check(CatalogCaptionLayout.metadataText(year: nil, genre: "Драма") == "Драма", "Missing year")
        check(CatalogCaptionLayout.metadataText(year: "2026", genre: nil) == "2026", "Missing genre")
        check(CatalogCaptionLayout.metadataText(year: " ", genre: nil) == nil, "Empty metadata creates no accessibility text")

        let typographyChecks = CatalogFallbackTitleTests.run()
        print("PASS: \(typographyChecks) bundled-font/scope/actual rendered-title checks")
        let base = MoviesApi.activeImagesBaseURL
        let tv = CatalogArtworkIdentity(id: "tv_100088", type: nil)!
        let film = CatalogArtworkIdentity(id: "movie_100088", type: nil)!
        check(tv != film, "Same number must not share movie/TV cache identity")
        check(tv.requestId == "tv_100088" && tv.mediaType == "tv", "TV prefix retained")
        check(CatalogArtworkIdentity(id: "100088", type: "tv") == tv, "Typed numeric TV ID is canonical")
        check(CatalogArtworkIdentity(id: "tmdb_100088", type: "tv") == tv, "TMDB plus type retains TV namespace")
        check(CatalogArtworkIdentity(id: "tv_100088", type: "movie") == tv, "Explicit prefix is authoritative")
        check(CatalogArtworkIdentity(id: "100088", type: nil) == nil, "Never guess a movie from an untyped ID")
        check(CatalogArtworkIdentity(id: "tv_bad", type: "tv") == nil, "Reject malformed IDs")
        check(CatalogArtworkIdentity(id: "tv_0", type: "tv") == nil, "Reject zero IDs")
        check(CatalogArtworkIdentity(id: "kp_123", type: nil)?.requestId == "kp_123", "KP namespace retained")
        check(!tv.matchesOverride(MediaArtworkOverride(mediaId: "movie_100088", tmdbId: 100088), kpId: nil), "Movie override must not leak into TV")
        check(!tv.matchesOverride(MediaArtworkOverride(mediaId: "100088", tmdbId: 100088), kpId: nil), "Untyped numeric alias is ambiguous")
        check(tv.matchesOverride(MediaArtworkOverride(mediaId: "tv_100088"), kpId: nil), "Exact typed override accepted")
        check(tv.matchesOverride(MediaArtworkOverride(mediaId: "kp_464963", kpId: 464963), kpId: 464963), "Explicit matching external KP identity accepted")
        check(!tv.acceptsLogoURL("\(base)/api/v1/images/logos/100088/small"), "Reject ambiguous logo URLs from old caches too")
        check(tv.acceptsLogoURL("\(base)/api/v1/images/tmdb/w300/tlou.png"), "Explicit artwork path accepted")

        // Exercise the actual DTO accessors and URL normalizers.
        let poster = "\(base)/api/v1/images/tmdb/w500/standard.jpg"
        let card = MediaDto(originalId: .string("tv_100088"), title: "Одни из нас", poster: poster, type: "tv")
        check(card.displayLogoUrl() == nil, "Missing TV logo must not synthesize an untyped numeric proxy")
        let sameNumberMovie = MediaDto(originalId: .string("42"), type: "movie")
        let sameNumberTV = MediaDto(originalId: .string("42"), type: "tv")
        check(sameNumberMovie.artworkIdentifier != sameNumberTV.artworkIdentifier, "SwiftUI cell IDs cannot collide between film and series")
        check(sameNumberMovie.id == "42" && sameNumberTV.id == "42", "Keep business/API/playback IDs unchanged")
        let savedQuality = UserDefaults.standard.object(forKey: "posterQuality")
        defer {
            if let savedQuality { UserDefaults.standard.set(savedQuality, forKey: "posterQuality") }
            else { UserDefaults.standard.removeObject(forKey: "posterQuality") }
        }
        for (quality, size) in [("high", "w500"), ("low", "w185")] {
            UserDefaults.standard.set(quality, forKey: "posterQuality")
            for id in ["tv_100088", "movie_100088", "tmdb_100088", "kp_100088", "100088"] {
                let model = MediaDto(originalId: .string(id), poster: poster, type: "tv")
                check(model.displayPosterUrl(forLogoMode: true)?.contains("/standard.jpg") == true,
                      "Until typed textless artwork resolves, retain this title's known poster: \(id), \(quality)")
                check(model.displayPosterUrl(forLogoMode: false)?.contains("/standard.jpg") == true,
                      "Logos-off mode still uses the standard poster")
                check(model.displayLogoUrl() == nil, "Restoring poster fallback must not restore ambiguous logo fallback")
            }
        }
        UserDefaults.standard.set("high", forKey: "posterQuality")
        let noId = MediaDto(poster: poster)
        check(noId.displayPosterUrl(forLogoMode: true) == poster, "Without an ID retain the supplied poster")
        let stale = MediaDto(originalId: .string("tv_100088"), type: "tv", logo: "\(base)/api/v1/images/logos/100088/small")
        check(stale.displayLogoUrl() == nil, "Reject a stale proxy stored in the DTO")
        let explicit = MediaDto(originalId: .string("tv_100088"), type: "tv", logo: "https://image.tmdb.org/t/p/original/tlou.png")
        check(explicit.displayLogoUrl() == "\(base)/api/v1/images/tmdb/w300/tlou.png", "Production logo resizing/routing retained")
        check(explicit.displayLogoUrl(isCompact: false) != nil, "Noncompact explicit logo still available")
        let textless = MediaDto(originalId: .string("tv_100088"), poster: poster, type: "tv", textlessPoster: "/textless.jpg")
        check(textless.displayPosterUrl(forLogoMode: true)?.contains("textless.jpg") == true, "Explicit textless poster retained")
        MediaOverridesRepository.shared.items = [MediaArtworkOverride(mediaId: "tv_100088", textlessPosterUrl: "https://example.com/curated-textless.jpg")]
        check(card.displayPosterUrl(forLogoMode: true)?.hasPrefix("https://example.com/curated-textless.jpg?") == true, "Curated textless artwork wins and is versioned")
        MediaOverridesRepository.shared.items = []
        MediaOverridesRepository.shared.items = [MediaArtworkOverride(mediaId: "movie_100088", logoUrl: "/wrong.png")]
        check(card.displayLogoUrl() == nil, "Cross-type curated logo is not used")
        MediaOverridesRepository.shared.items = [MediaArtworkOverride(mediaId: "tv_100088", logoUrl: "\(base)/api/v1/images/tmdb/original/curated.png")]
        check(card.displayLogoUrl()?.contains("/w300/curated.png") == true, "Correct curated logo wins")
        MediaOverridesRepository.shared.items = []
        check(adjustLogoUrl(urlStr: "\(base)/api/v1/images/logos/550/original", targetSize: "w300") == "\(base)/api/v1/images/logos/550/small", "Legacy sizing helper unchanged for other callers")

        func image(_ path: String, language: String?) throws -> MediaImageItemDto {
            let data = try JSONSerialization.data(withJSONObject: ["url": path, "iso_639_1": language as Any? ?? NSNull()])
            return try JSONDecoder().decode(MediaImageItemDto.self, from: data)
        }
        MoviesApi.shared.responses["tv|tv_100088"] = MediaImagesResponseDto(logos: [
            try image("\(base)/api/v1/images/tmdb/original/english.png", language: "en"),
            try image("\(base)/api/v1/images/tmdb/original/tlou.png", language: "ru")
        ], posters: [
            try image("\(base)/api/v1/images/tmdb/w500/tv-standard.jpg", language: "ru"),
            try image("\(base)/api/v1/images/tmdb/w500/tv-textless.jpg", language: nil)
        ])
        MoviesApi.shared.responses["movie|movie_100088"] = MediaImagesResponseDto(logos: [
            try image("\(base)/api/v1/images/tmdb/original/different-film.png", language: "en")
        ])
        async let first = CatalogLogoRepository.shared.logo(for: tv)
        async let duplicate = CatalogLogoRepository.shared.logo(for: tv)
        let (a, b) = await (first, duplicate)
        check(a == b && a?.hasSuffix("/tlou.png") == true, "Russian logo from typed TV response wins")
        check(MoviesApi.shared.requests.filter { $0 == "tv|tv_100088" }.count == 1, "Requests across shelves coalesce")
        let artwork = await CatalogLogoRepository.shared.artwork(for: tv)
        check(artwork.textlessPoster?.hasSuffix("/tv-textless.jpg") == true, "Textless comes from typed TV response, never a numeric guess")
        check(artwork.poster?.hasSuffix("/tv-standard.jpg") == true, "Favorite refresh has a typed regular poster candidate")
        let cached = await CatalogLogoRepository.shared.logo(for: tv)
        check(cached == a && MoviesApi.shared.requests.count == 1, "Successful result is cached")
        let different = await CatalogLogoRepository.shared.logo(for: film)
        check(different?.hasSuffix("/different-film.png") == true && different != a, "Same-number film uses a separate request/cache")
        let untyped = MediaDto(originalId: .string("42"), poster: "\(base)/api/v1/images/posters/42/w500/textless", type: "tv")
        check(untyped.displayPosterUrl(forLogoMode: true) == nil, "Reject ambiguous poster URLs stored in old favorite/list caches")
        check(normalizeImageUrl(path: "invalid", id: "42") == nil, "Malformed image path must not reinterpret a TMDB ID as KP")
        MediaOverridesRepository.shared.items = [MediaArtworkOverride(mediaId: "tv_100088", posterUrl: "https://example.com/manual.jpg", updatedAt: 50)]
        check(card.displayPosterUrl(forLogoMode: true)?.hasPrefix("https://example.com/manual.jpg?") == true, "Regular curator choice is respected in logo mode when no textless choice exists")
        MediaOverridesRepository.shared.items = []
        let missing = CatalogArtworkIdentity(id: "tv_123", type: nil)!
        let absent = await CatalogLogoRepository.shared.logo(for: missing)
        let absentAgain = await CatalogLogoRepository.shared.logo(for: missing)
        check(absent == nil && absentAgain == nil, "Missing artwork has no guessed fallback")
        check(MoviesApi.shared.requests.filter { $0 == "tv|tv_123" }.count == 1, "Brief negative cache avoids request storms")
        MoviesApi.shared.responses["tv|tv_100088"] = MediaImagesResponseDto(logos: [try image("https://example.com/updated.png", language: "ru")])
        CatalogLogoRepository.shared.invalidate()
        let updated = await CatalogLogoRepository.shared.logo(for: tv)
        check(updated == "https://example.com/updated.png", "Artwork mutation invalidates the catalog response cache")
        let consistencyChecks = try ArtworkConsistencyTests.run()
        print("PASS: \(consistencyChecks) production artwork consistency checks")
        print("Catalog artwork identity, production model/resizing and repository tests passed: \(count) assertions.")
    }
}
