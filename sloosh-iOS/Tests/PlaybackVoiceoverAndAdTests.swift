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
        check(!filteredMedia.contains("preroll.ts") && !filteredMedia.contains("distribrey.com"), "Spliced SCTE35 and external ad discontinuity segments are stripped")
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

        print("PASS: \(count) playback voiceover and ad-filtering tests")
    }
}
