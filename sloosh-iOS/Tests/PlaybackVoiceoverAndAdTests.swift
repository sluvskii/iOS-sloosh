import Foundation

@main
struct PlaybackVoiceoverAndAdTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }

        // 1. Studio aliases and false-positive separation
        check(allohaTranslationNamesMatch("Red Head Sound", "RHS", exactOnly: false), "Studio aliases RHS and Red Head Sound must match")
        check(allohaTranslationNamesMatch("LostFilm", "Лостфильм", exactOnly: false), "LostFilm and Лостфильм must match")
        check(!allohaTranslationNamesMatch("Novamedia", "Amedia", exactOnly: false), "Novamedia must never match Amedia via substring")
        check(!allohaTranslationNamesMatch("UATeam", "НеЗупиняйПродакшн (укр)", exactOnly: true), "Exact match must distinguish two Ukrainian studios")
        check(!allohaTranslationNamesMatch("UATeam", "НеЗупиняйПродакшн (укр)", exactOnly: false), "Fuzzy match must distinguish two distinct Ukrainian studios")
        check(!allohaTranslationNamesMatch("Eng.Original", "Eng Commentary", exactOnly: true), "Exact match must distinguish distinct English tracks")

        // 2. Collaps sparse track suffix ("eng7" on 7-track manifest) + single DEFAULT=YES
        let collapsMaster = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio0",NAME="rus0",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="ru",URI="https://cdn.interkh.com/v/index-a1.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio0",NAME="rus1",DEFAULT=NO,AUTOSELECT=NO,LANGUAGE="ru",URI="https://cdn.interkh.com/v/index-a2.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio0",NAME="ukr2",DEFAULT=NO,AUTOSELECT=NO,LANGUAGE="uk",URI="https://cdn.interkh.com/v/index-a3.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio0",NAME="eng4",DEFAULT=NO,AUTOSELECT=NO,LANGUAGE="en",URI="https://cdn.interkh.com/v/index-a4.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720,AUDIO="audio0"
        https://cdn.interkh.com/v/index-v1.m3u8
        """
        let collapsVoices = ["Кравец-Рекордз", "LostFilm", "UATeam", "Eng.Original"]
        let rewrittenCollaps = PlaybackHlsRewriter.rewrite(
            master: collapsMaster,
            voices: collapsVoices,
            mediaId: "kp_464963",
            preferredVoiceName: "Eng.Original",
            isCollaps: true
        )
        check(rewrittenCollaps.contains("#EXT-X-START:TIME-OFFSET=4.0,PRECISE=YES"), "Collaps master includes 4.0s start offset")
        check(rewrittenCollaps.contains("NAME=\"Eng.Original\""), "Sparse suffix eng4 still maps cleanly to ordinal track Eng.Original")
        let defaultYesMatches = rewrittenCollaps.components(separatedBy: "DEFAULT=YES").count - 1
        check(defaultYesMatches == 1, "Only one track may be marked DEFAULT=YES")
        check(rewrittenCollaps.contains("NAME=\"Eng.Original\",DEFAULT=YES,AUTOSELECT=YES") || rewrittenCollaps.contains("NAME=\"Eng.Original\"") && rewrittenCollaps.components(separatedBy: "\n").first(where: { $0.contains("NAME=\"Eng.Original\"") })?.contains("DEFAULT=YES") == true, "Eng.Original must receive DEFAULT=YES")
        check(rewrittenCollaps.components(separatedBy: "\n").first(where: { $0.contains("NAME=\"Кравец-Рекордз\"") })?.contains("DEFAULT=NO") == true, "Original CDN default rus0 must be cleared to DEFAULT=NO")

        // 3. Non-generic CDN track names must still update DEFAULT/AUTOSELECT
        let namedMaster = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio0",NAME="English",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="en",URI="a0.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio0",NAME="Дубляж",DEFAULT=NO,AUTOSELECT=NO,LANGUAGE="ru",URI="a1.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio0",NAME="Дубляж (Пифагор)",DEFAULT=NO,AUTOSELECT=NO,LANGUAGE="ru",URI="a2.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,AUDIO="audio0"
        v1.m3u8
        """
        let rewrittenNamed = PlaybackHlsRewriter.rewrite(
            master: namedMaster,
            voices: [],
            mediaId: "kp_123",
            preferredVoiceName: "Дубляж"
        )
        let namedLines = rewrittenNamed.components(separatedBy: "\n")
        check(namedLines.filter { $0.contains("DEFAULT=YES") }.count == 1, "Exact preference picks only one DEFAULT=YES among Дубляж and Дубляж (Пифагор)")
        check(namedLines.first(where: { $0.contains("NAME=\"Дубляж\"") })?.contains("DEFAULT=YES") == true, "Exact track Дубляж becomes DEFAULT=YES")
        check(namedLines.first(where: { $0.contains("NAME=\"English\"") })?.contains("DEFAULT=NO") == true, "Previous default English becomes DEFAULT=NO")

        // 4. Dedicated single-track variant preserves selected preferredVoiceName
        let singleTrackMaster = """
        #EXTM3U
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio0",NAME="rus0",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="ru",URI="a0.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,AUDIO="audio0"
        v1.m3u8
        """
        let singleRewritten = PlaybackHlsRewriter.rewrite(
            master: singleTrackMaster,
            voices: ["Original", "Дубляж", "Red Head Sound"],
            mediaId: "kp_99",
            preferredVoiceName: "Red Head Sound"
        )
        check(singleRewritten.contains("NAME=\"Red Head Sound\""), "Dedicated single-track stream adopts matched preferredVoiceName instead of voices[0]")

        // 5. Ad block stripping & Collaps media offset
        let mediaWithAds = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXTINF:10.0,
        seg-1-v1.ts
        #EXT-X-CUE-OUT:DURATION=15
        #EXTINF:15.0,
        https://ads.example.com/preroll.ts
        #EXT-X-CUE-IN
        #EXT-X-DISCONTINUITY
        #EXTINF:5.0,
        https://distribrey.com/ad/banner.ts
        #EXT-X-DISCONTINUITY
        #EXT-X-CUE-OUT:DURATION=5
        #EXTINF:5.0,
        https://liftapp.ink/promo.ts
        #EXT-X-CUE-IN
        #EXTINF:10.0,
        seg-2-v1.ts
        #EXT-X-ENDLIST
        """
        let filteredMedia = PlaybackHlsRewriter.rewriteMediaPlaylist(
            content: mediaWithAds,
            baseUrl: URL(string: "https://cdn.collaps-mirror.example/v/index-v1.m3u8")!,
            isCollaps: true
        ) { "proxy/\($0)" }
        check(filteredMedia.contains("#EXT-X-START:TIME-OFFSET=4.0,PRECISE=YES"), "Explicit isCollaps flag adds 4.0s offset on mirror domains too")
        check(!filteredMedia.contains("preroll.ts") && !filteredMedia.contains("distribrey.com") && !filteredMedia.contains("liftapp.ink"), "Spliced SCTE35 and external ad discontinuity segments are stripped")
        check(filteredMedia.contains("proxy/seg-1-v1.ts") && filteredMedia.contains("proxy/seg-2-v1.ts"), "Genuine content segments are preserved and rewritten")

        let multiCdnMedia = """
        #EXTM3U
        #EXT-X-VERSION:3
        #EXT-X-TARGETDURATION:10
        #EXTINF:10.0,
        https://cdn-edge-2.otherhost.example/movie/seg-1.ts
        #EXT-X-ENDLIST
        """
        let preservedMultiCdn = PlaybackHlsRewriter.rewriteMediaPlaylist(
            content: multiCdnMedia,
            baseUrl: URL(string: "https://cdn-edge-1.primaryhost.example/movie/index.m3u8")!,
            isCollaps: false
        ) { $0 }
        check(preservedMultiCdn.contains("https://cdn-edge-2.otherhost.example/movie/seg-1.ts"), "Regular cross-CDN segments outside discontinuity must not be stripped")

        // 6. CollapsParser preserves slot indices when audio.names contains empty strings
        let sparseHtml = """
        <html><script>
        makePlayer({hls: "https://cdn.example.com/master.m3u8", audio: {"names": ["", "LostFilm", "delete", "Eng.Original"]}});
        </script></html>
        """
        if let parsed = CollapsParser.parseCatalog(embedHtml: sparseHtml, defaultTitle: "Test") {
            let names = parsed.apiResult.movie?.translations.map(\.name) ?? []
            check(names == ["Дорожка 1", "LostFilm", "Дорожка 3", "Eng.Original"], "CollapsParser must keep 1:1 positional indices without dropping empty slots")
        } else {
            preconditionFailure("CollapsParser failed to parse valid sparse HTML")
        }

        // 7. findMatchingAudioVariant checks studio words before generic language tag fallback
        let variants: [[String: Any]] = [
            ["title": "Кравец (Русский)", "url": "https://cdn.test/kravec.m3u8"],
            ["title": "А. Гаврилов (Русский)", "url": "https://cdn.test/gavrilov.m3u8"]
        ]
        let matched = findMatchingAudioVariant(in: variants, for: "Гаврилов (Русский)")
        check((matched?["url"] as? String) == "https://cdn.test/gavrilov.m3u8", "Author token match wins over first generic Russian language tag")

        // 8. Large multi-season / multi-dub AllohaSourceAvailabilityIndex correctness & speed
        var seasonsFixture: [AllohaSeason] = []
        let baseDubs: [String] = [
            "Red Head Sound", "HDrezka Studio", "LostFilm", "Kubik v Kube (18+)",
            "TVShows", "NewStudio", "Jaskier", "AlexFilm", "RuDub", "ColdFilm",
            "LE-Production", "Dragon Money Studio", "Оригинал", "Український"
        ] + (1...26).map { "Озвучка Студия \($0) (Russian) AC3 5.1" }

        for s in 1...5 {
            var epsFixture: [AllohaEpisode] = []
            for e in 1...8 {
                var epTranslations: [AllohaTranslation] = baseDubs.enumerated().map { idx, name in
                    let effectiveName = (s == 5 && name == "Red Head Sound") ? "RHS" : name
                    return AllohaTranslation(
                        id: "\(s)_\(e)_\(idx)",
                        name: effectiveName,
                        iframeUrl: "https://example.test/e/\(s)/\(e)/\(idx)",
                        streamUrl: nil
                    )
                }
                if s <= 4 {
                    epTranslations.append(AllohaTranslation(
                        id: "\(s)_\(e)_exclusive",
                        name: "Пифагор Дубляж",
                        iframeUrl: "https://example.test/e/\(s)/\(e)/ex",
                        streamUrl: nil
                    ))
                }
                epTranslations.append(AllohaTranslation(
                    id: "\(s)_\(e)_sub",
                    name: "Русские субтитры",
                    iframeUrl: "https://example.test/e/\(s)/\(e)/sub",
                    streamUrl: nil
                ))
                epsFixture.append(AllohaEpisode(season: s, episode: e, translations: epTranslations))
            }
            seasonsFixture.append(AllohaSeason(season: s, episodes: epsFixture))
        }
        let heavySeries = AllohaApiResult(title: "The Boys Fixture", isSerial: true, movie: nil, seasons: seasonsFixture)
        let t0 = Date().timeIntervalSinceReferenceDate
        let index = AllohaSourceAvailabilityIndex(result: heavySeries, effectiveIsSerial: true)
        var availableChecks = 0
        for s in index.sortedSeasons {
            _ = index.seasonHasTranslation(season: s, name: "Пифагор Дубляж")
            _ = index.seasonHasTranslation(season: s, name: "Red Head Sound")
            for e in index.episodesBySeason[s] ?? [] {
                if index.episodeHasTranslation(season: s, episode: e, name: "LostFilm") {
                    availableChecks += 1
                }
            }
        }
        let elapsed = Date().timeIntervalSinceReferenceDate - t0
        check(index.sortedSeasons == [1, 2, 3, 4, 5], "Sorted seasons preserved")
        check(!index.sortedNames.contains("Русские субтитры"), "Subtitles must be excluded from voiceovers list")
        check(index.seasonHasTranslation(season: 1, name: "Пифагор Дубляж"), "Season 1 includes Пифагор Дубляж")
        check(!index.seasonHasTranslation(season: 5, name: "Пифагор Дубляж"), "Season 5 excludes missing Пифагор Дубляж")
        check(index.seasonHasTranslation(season: 5, name: "Red Head Sound"), "Season 5 fuzzy-matches RHS alias to Red Head Sound")
        check(index.episode(season: 3, episode: 5)?.episode == 5, "O(1) episode lookup returns matching episode")
        check(availableChecks == 40, "All 40 episodes report LostFilm available")
        check(elapsed < 1.0, "40-episode x 40-dub index build and queries must complete fast (took \(elapsed)s)")

        // 9. Collaps cinemascope 1272x530 maps to 720p and caps higher requested preference (1080p -> 720p) identically
        check(PlaybackHlsRewriter.normalizeResolutionLabel(width: 1272, height: 530) == "720p", "Cinemascope 1272x530 normalizes to 720p")
        let cinemascopeMaster = """
        #EXTM3U
        #EXT-X-VERSION:4
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio0",NAME="rus0",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="ru",URI="a0.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="failover-audio-0",NAME="rus0",DEFAULT=YES,AUTOSELECT=YES,LANGUAGE="ru",URI="a0_fail.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=2500000,RESOLUTION=1272x530,AUDIO="audio0"
        720.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=900000,RESOLUTION=640x360,AUDIO="audio0"
        360.m3u8
        """
        let cappedFrom1080 = PlaybackHlsRewriter.rewrite(
            master: cinemascopeMaster,
            voices: ["Red Head Sound"],
            mediaId: "kp_460586",
            targetQuality: "1080p",
            isCollaps: true
        )
        let exact720 = PlaybackHlsRewriter.rewrite(
            master: cinemascopeMaster,
            voices: ["Red Head Sound"],
            mediaId: "kp_460586",
            targetQuality: "720p",
            isCollaps: true
        )
        check(cappedFrom1080 == exact720, "1080p target on 720p max Collaps stream produces identical rewritten playlist as 720p")
        check(cappedFrom1080.contains("720.m3u8") && !cappedFrom1080.contains("360.m3u8"), "Highest tier kept and lower tier filtered")
        check(!cappedFrom1080.contains("failover-audio-0"), "Failover duplicate audio group must be stripped")

        // 10. HlsSegmentShield catches real 60fps liftapp.ink banner SPS and preserves failover metadata
        let bannerSpsData = hexToData(HlsSegmentShield.knownBannerSpsHex)
        let parsedBannerSps = HlsSegmentShield.parseH264Sps(bannerSpsData)
        check(parsedBannerSps?.profileIdc == 100, "Known banner SPS parses as High profile (100)")
        check(parsedBannerSps?.levelIdc == 32, "Known banner SPS parses as Level 3.2 (32)")
        check(parsedBannerSps?.width == 1280 && parsedBannerSps?.height == 720, "Known banner SPS parses 1280x720 dimensions")
        check(parsedBannerSps?.fps == 60.0, "Known banner SPS parses 60.0 fps")

        let movie720Sps = makeSyntheticH264Sps(
            profileIdc: 77,
            levelIdc: 31,
            widthMbsMinus1: 79,
            heightMbsMinus1: 44,
            numUnits: 1001,
            timeScale: 48_000
        )
        let parsedMovie720Sps = HlsSegmentShield.parseH264Sps(movie720Sps)
        check(parsedMovie720Sps?.profileIdc == 77 && parsedMovie720Sps?.levelIdc == 31, "Synthetic movie SPS parses Main@L3.1")
        check(parsedMovie720Sps?.width == 1280 && parsedMovie720Sps?.height == 720, "Synthetic movie SPS parses 1280x720")
        check(abs((parsedMovie720Sps?.fps ?? 0) - 23.976) < 0.01, "Synthetic movie SPS parses ~23.976 fps")

        let movie720Ts = makeSyntheticTsPrefix(sps: movie720Sps)
        let bannerTs = makeSyntheticTsPrefix(sps: bannerSpsData)

        let v1SegmentUrl = URL(string: "https://fzgbzcajzbbb.interkh.com/hls/seg-59-v1.ts")!
        let v2SegmentUrl = URL(string: "https://fzgbzcajzbbb.interkh.com/hls/seg-59-v2.ts")!
        let audioSegmentUrl = URL(string: "https://fzgbzcajzbbb.interkh.com/hls/seg-59-a1.ts")!
        check(HlsSegmentShield.isInspectableVideoSegment(url: v1SegmentUrl, isCollaps: true, rangeHeader: nil), "Collaps video TS is inspectable")
        check(!HlsSegmentShield.isInspectableVideoSegment(url: audioSegmentUrl, isCollaps: true, rangeHeader: nil), "Audio TS chunk skips video shield")
        check(!HlsSegmentShield.isInspectableVideoSegment(url: v1SegmentUrl, isCollaps: true, rangeHeader: "bytes=1880-3760"), "Non-zero byte range skips SPS shield")
        check(HlsSegmentShield.tierKey(for: v1SegmentUrl) == "v1" && HlsSegmentShield.tierKey(for: v2SegmentUrl) == "v2", "Quality tiers get separate SPS baselines")

        let cleanMovieVerdict = HlsSegmentShield.evaluateSegment(
            prefixData: movie720Ts,
            isComplete: false,
            expectedContentLength: 1_450_000,
            eTag: "\"69f-162008\"",
            baselineSps: nil,
            declaredMaxFps: 24.0
        )
        check(cleanMovieVerdict == .clean(baselineSpsToRecord: movie720Sps), "Clean movie segment records baseline SPS")

        // Cold-start seek hitting known 268088B / 60fps banner BEFORE any baseline exists
        let coldBannerVerdict = HlsSegmentShield.evaluateSegment(
            prefixData: bannerTs,
            isComplete: false,
            expectedContentLength: HlsSegmentShield.knownBannerByteLength,
            eTag: "\"6912-41738\"",
            baselineSps: nil,
            declaredMaxFps: 24.0
        )
        if case .suspectAdSwap = coldBannerVerdict {
            check(true, "Cold-start seek banner is caught without prior baseline")
        } else {
            check(false, "Expected cold-start banner catch, got \(String(describing: coldBannerVerdict))")
        }

        // Hypothetical re-encoded banner at different byte size & arbitrary 60fps SPS
        let altBannerSps = makeSyntheticH264Sps(
            profileIdc: 77,
            levelIdc: 32,
            widthMbsMinus1: 79,
            heightMbsMinus1: 44,
            numUnits: 1000,
            timeScale: 120_000
        )
        let altBannerTs = makeSyntheticTsPrefix(sps: altBannerSps)
        let reencodedVerdict = HlsSegmentShield.evaluateSegment(
            prefixData: altBannerTs,
            isComplete: false,
            expectedContentLength: 312_000,
            eTag: "\"abc-4c2c0\"",
            baselineSps: movie720Sps,
            declaredMaxFps: 24.0
        )
        if case .suspectAdSwap = reencodedVerdict {
            check(true, "Size-independent SPS mismatch catches re-encoded mid-stream banner")
        } else {
            check(false, "Expected size-independent SPS mismatch, got \(String(describing: reencodedVerdict))")
        }

        // ABR switch to v2 (different tier baseline = nil) must NOT trigger a false-positive mismatch
        let movie1080Sps = makeSyntheticH264Sps(
            profileIdc: 77,
            levelIdc: 40,
            widthMbsMinus1: 119,
            heightMbsMinus1: 67,
            numUnits: 1001,
            timeScale: 48_000
        )
        let movie1080Ts = makeSyntheticTsPrefix(sps: movie1080Sps)
        let abrCleanVerdict = HlsSegmentShield.evaluateSegment(
            prefixData: movie1080Ts,
            isComplete: false,
            expectedContentLength: 2_200_000,
            eTag: "\"700-2191c0\"",
            baselineSps: nil,
            declaredMaxFps: 24.0
        )
        check(abrCleanVerdict == .clean(baselineSpsToRecord: movie1080Sps), "ABR switch to new tier initializes its own baseline cleanly")

        // Master playlist failover host & frame-rate extraction (before failover duplicates are stripped)
        let collapsMasterWithFailover = """
        #EXTM3U
        #EXT-X-VERSION:4
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio0",NAME="rus0",DEFAULT=YES,URI="https://fzgbzcajzbbb.interkh.com/a0.m3u8"
        #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="failover-audio-0",NAME="rus0",DEFAULT=YES,URI="https://x-bc.interkh.com/a0.m3u8"
        #EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1280x534,FRAME-RATE=23.976,AUDIO="audio0"
        https://fzgbzcajzbbb.interkh.com/v1.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=3500000,RESOLUTION=1280x534,FRAME-RATE=23.976,AUDIO="failover-audio-0"
        https://x-bc.interkh.com/v1.m3u8
        """
        let extractedHosts = PlaybackHlsRewriter.extractFailoverHosts(from: collapsMasterWithFailover, primaryHost: "fzgbzcajzbbb.interkh.com")
        check(extractedHosts == ["x-bc.interkh.com"], "Extracts failover CDN host from raw Collaps master")
        check(abs((PlaybackHlsRewriter.extractMaxFrameRate(from: collapsMasterWithFailover) ?? 0) - 23.976) < 0.001, "Extracts FRAME-RATE from master playlist")

        var origReq = URLRequest(url: v1SegmentUrl)
        origReq.setValue("https://api.example.com/", forHTTPHeaderField: "Referer")
        origReq.setValue("https://api.example.com", forHTTPHeaderField: "Origin")
        let switchedReq = HlsSegmentShield.buildFailoverRequest(from: origReq, failoverHost: "x-bc.interkh.com", stripRefererOrigin: false)
        check(switchedReq?.url?.absoluteString == "https://x-bc.interkh.com/hls/seg-59-v1.ts", "Failover request swaps host preserving path")
        check(switchedReq?.value(forHTTPHeaderField: "Referer") == "https://api.example.com/", "Failover request preserves Referer by default")
        let strippedReq = HlsSegmentShield.buildFailoverRequest(from: origReq, failoverHost: nil, stripRefererOrigin: true)
        check(strippedReq?.value(forHTTPHeaderField: "Referer") == nil && strippedReq?.value(forHTTPHeaderField: "Origin") == nil, "Stripped fallback clears Referer and Origin")

        print("PASS: \(count) playback voiceover and ad-filtering tests")
    }

    private static func hexToData(_ hex: String) -> Data {
        var data = Data()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            if let byte = UInt8(hex[idx..<next], radix: 16) {
                data.append(byte)
            }
            idx = next
        }
        return data
    }

    private static func makeSyntheticH264Sps(
        profileIdc: Int,
        levelIdc: Int,
        widthMbsMinus1: Int,
        heightMbsMinus1: Int,
        numUnits: UInt32,
        timeScale: UInt32
    ) -> Data {
        var bits: [UInt8] = []
        func pushBit(_ b: Int) { bits.append(UInt8(b & 1)) }
        func pushBits(_ v: UInt32, _ count: Int) {
            for shift in stride(from: count - 1, through: 0, by: -1) {
                pushBit(Int((v >> shift) & 1))
            }
        }
        func pushUE(_ value: Int) {
            let code = value + 1
            let bitLen = Int.bitWidth - code.leadingZeroBitCount
            for _ in 0..<(bitLen - 1) { pushBit(0) }
            pushBits(UInt32(code), bitLen)
        }

        pushBits(UInt32(profileIdc), 8)
        pushBits(0x40, 8) // constraint flags
        pushBits(UInt32(levelIdc), 8)
        pushUE(0) // seq_parameter_set_id
        pushUE(0) // log2_max_frame_num_minus4
        pushUE(0) // pic_order_cnt_type
        pushUE(0) // log2_max_pic_order_cnt_lsb_minus4
        pushUE(4) // max_num_ref_frames
        pushBit(0) // gaps_in_frame_num_value_allowed_flag
        pushUE(widthMbsMinus1)
        pushUE(heightMbsMinus1)
        pushBit(1) // frame_mbs_only_flag
        pushBit(1) // direct_8x8_inference_flag
        pushBit(0) // frame_cropping_flag
        pushBit(1) // vui_parameters_present_flag
        pushBit(0) // aspect_ratio_info_present_flag
        pushBit(0) // overscan_info_present_flag
        pushBit(0) // video_signal_type_present_flag
        pushBit(0) // chroma_loc_info_present_flag
        pushBit(1) // timing_info_present_flag
        pushBits(numUnits, 32)
        pushBits(timeScale, 32)
        pushBit(1) // fixed_frame_rate_flag
        pushBit(1) // rbsp_stop_one_bit
        while bits.count % 8 != 0 { pushBit(0) }

        var rbsp = Data()
        for idx in stride(from: 0, to: bits.count, by: 8) {
            var byte: UInt8 = 0
            for b in 0..<8 {
                byte = (byte << 1) | bits[idx + b]
            }
            rbsp.append(byte)
        }

        // Insert H.264 emulation prevention byte 0x03 where needed so parseH264Sps recovers exact RBSP
        var nal = Data([0x67])
        var zeroRun = 0
        for byte in rbsp {
            if zeroRun >= 2 && byte <= 0x03 {
                nal.append(0x03)
                zeroRun = 0
            }
            nal.append(byte)
            zeroRun = (byte == 0) ? (zeroRun + 1) : 0
        }
        return nal
    }

    private static func makeSyntheticTsPrefix(sps: Data) -> Data {
        func padPacket(_ bytes: [UInt8]) -> Data {
            var pkt = bytes
            if pkt.count < 188 {
                pkt.append(contentsOf: repeatElement(UInt8(0xFF), count: 188 - pkt.count))
            } else if pkt.count > 188 {
                pkt = Array(pkt.prefix(188))
            }
            return Data(pkt)
        }

        // Packet 0: PAT -> PMT on PID 0x1000
        let pat = padPacket([
            0x47, 0x40, 0x00, 0x10,
            0x00, // pointer_field
            0x00, 0xB0, 0x0D, // PAT table_id=0x00, section_length=13
            0x00, 0x01, 0xC1, 0x00, 0x00,
            0x00, 0x01, 0xF0, 0x00, // program 1 -> PID 0x1000
            0x00, 0x00, 0x00, 0x00
        ])

        // Packet 1: PMT on PID 0x1000 -> H.264 video (0x1B) on PID 0x0100
        let pmt = padPacket([
            0x47, 0x50, 0x00, 0x10,
            0x00, // pointer_field
            0x02, 0xB0, 0x12, // PMT table_id=0x02, section_length=18
            0x00, 0x01, 0xC1, 0x00, 0x00,
            0xE1, 0x00, // PCR PID
            0xF0, 0x00, // program_info_length = 0
            0x1B, 0xE1, 0x00, 0xF0, 0x00, // H.264 elementary PID 0x0100
            0x00, 0x00, 0x00, 0x00
        ])

        // Packet 2: Video PES containing complete Annex-B SPS followed by PPS start code
        var vid: [UInt8] = [
            0x47, 0x41, 0x00, 0x10,
            0x00, 0x00, 0x01, 0xE0, 0x00, 0x00, 0x80, 0x00, 0x00, // PES header
            0x00, 0x00, 0x00, 0x01 // SPS start code
        ]
        vid.append(contentsOf: sps)
        vid.append(contentsOf: [0x00, 0x00, 0x00, 0x01, 0x68, 0xEE, 0x3C, 0x80]) // terminating PPS NAL

        var stream = Data()
        stream.append(pat)
        stream.append(pmt)
        stream.append(padPacket(vid))
        return stream
    }
}
