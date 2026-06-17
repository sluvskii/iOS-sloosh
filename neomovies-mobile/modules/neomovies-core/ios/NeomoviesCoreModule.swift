import ExpoModulesCore
import Foundation

public class NeomoviesCoreModule: Module {
  private var didBindPlayerCallbacks = false

  private func clampedProgressPercent(positionMs: Int, durationMs: Int) -> Int {
    guard positionMs > 0, durationMs > 0 else { return 0 }
    let raw = Int((Double(positionMs) / Double(durationMs)) * 100.0)
    return min(max(raw, 0), 100)
  }

  public func definition() -> ModuleDefinition {
    Name("NeomoviesCore")
    Events("onAVPlayerStateChanged", "onAVPlayerProgress", "onAVPlayerEpisodeChanged", "onAVPlayerDismissed")

    View(EpisodesListView.self) {
      Events("onEpisodePress", "onContentHeight", "onDownloadPress")

      Prop("episodes") { (view: EpisodesListView, episodes: [[String: Any]]) in
        view.setEpisodes(episodes)
      }

      Prop("textColor") { (view: EpisodesListView, color: String?) in
        view.setTextColor(color)
      }

      Prop("secondaryTextColor") { (view: EpisodesListView, color: String?) in
        view.setSecondaryTextColor(color)
      }

      Prop("borderColor") { (view: EpisodesListView, color: String?) in
        view.setBorderColor(color)
      }

      Prop("backgroundColor") { (view: EpisodesListView, color: String?) in
        view.setBackgroundColorHex(color)
      }
    }

    Function("parseCollapsCatalog") { (embedHtml: String) -> [String: Any] in
      return CollapsParser.parseCollapsCatalog(embedHtml: embedHtml)
    }

    Function("parseAllohaRuntimePayload") { (payload: String, baseUrl: String, headers: [String: String]) -> [String: Any] in
      return AllohaRuntimeParser.parsePayload(payload, baseURL: baseUrl, headers: headers) ?? [:]
    }

    Function("rewriteCollapsHlsMaster") { (master: String, voices: [String], subtitles: [[String: String]], mediaId: String) -> String in
      let parsedSubtitles = subtitles.map { dict -> CollapsSubtitle in
        CollapsSubtitle(
          url: dict["url"] ?? "",
          label: dict["label"] ?? "",
          language: dict["language"] ?? ""
        )
      }
      return CollapsHlsRewriter.rewrite(
        master: master,
        voices: voices,
        subtitles: parsedSubtitles,
        mediaId: mediaId
      )
    }

    Function("rewriteCollapsDashManifest") { (manifest: String, voices: [String], subtitles: [[String: String]], mediaId: String) -> String in
      let parsedSubtitles = subtitles.map { dict -> CollapsSubtitle in
        CollapsSubtitle(
          url: dict["url"] ?? "",
          label: dict["label"] ?? "",
          language: dict["language"] ?? ""
        )
      }
      return CollapsDashRewriter.rewrite(
        manifest: manifest,
        voices: voices,
        subtitles: parsedSubtitles,
        mediaId: mediaId
      )
    }

    AsyncFunction("rewriteCollapsHlsFromUrl") { (hlsUrl: String, voices: [String], subtitles: [[String: String]], mediaId: String, referer: String?, origin: String?) -> String in
      let parsedSubtitles = subtitles.map { dict -> CollapsSubtitle in
        CollapsSubtitle(
          url: dict["url"] ?? "",
          label: dict["label"] ?? "",
          language: dict["language"] ?? ""
        )
      }
      
      let masterPlaylist = try await CollapsHTTPClient.fetch(
        url: hlsUrl,
        referer: referer,
        origin: origin
      )
      
      return CollapsHlsRewriter.rewrite(
        master: masterPlaylist,
        voices: voices,
        subtitles: parsedSubtitles,
        mediaId: mediaId
      )
    }

    AsyncFunction("rewriteCollapsDashFromUrl") { (dashUrl: String, voices: [String], subtitles: [[String: String]], mediaId: String, referer: String?, origin: String?) -> String in
      let parsedSubtitles = subtitles.map { dict -> CollapsSubtitle in
        CollapsSubtitle(
          url: dict["url"] ?? "",
          label: dict["label"] ?? "",
          language: dict["language"] ?? ""
        )
      }
      
      let manifest = try await CollapsHTTPClient.fetch(
        url: dashUrl,
        referer: referer,
        origin: origin
      )
      
      return CollapsDashRewriter.rewrite(
        manifest: manifest,
        voices: voices,
        subtitles: parsedSubtitles,
        mediaId: mediaId
      )
    }

    AsyncFunction("fetchUrlTextInsecure") { (url: String, referer: String?, origin: String?) -> String in
      return try await CollapsHTTPClient.fetch(
        url: url,
        referer: referer,
        origin: origin
      )
    }

    AsyncFunction("fetchAllohaSeriesCatalog") { (kpId: String, _token: String) -> [String: Any] in
      let encodedKp = kpId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? kpId
      let url = "https://api.neomovies.ru/api/v1/alloha/catalog/kp/\(encodedKp)"
      let body = try await CollapsHTTPClient.fetch(
        url: url,
        referer: "https://api.neomovies.ru/",
        origin: "https://api.neomovies.ru"
      )
      guard
        let data = body.data(using: .utf8),
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
        let payload = json["data"] as? [String: Any]
      else { return [:] }

      func castDict(_ value: Any?) -> [String: Any]? {
        if let d = value as? [String: Any] { return d }
        if let nd = value as? NSDictionary { return nd as? [String: Any] }
        return nil
      }

      func intFromAny(_ value: Any?, fallback: Int = 1) -> Int {
        if let n = value as? Int { return n }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String, let n = Int(s) { return n }
        return fallback
      }

      // --- Movie: category == 1 or has translation_iframe but no seasons ---
      let category = intFromAny(payload["category"], fallback: 0)
      let translationIframeAny = payload["translation_iframe"]
      let hasSeasons = castDict(payload["seasons"]) != nil
      if (category == 1 || translationIframeAny != nil) && !hasSeasons {
        guard let transObj = castDict(translationIframeAny) else {
          // Fallback to single iframe
          if let singleIframe = payload["iframe"] as? String, !singleIframe.isEmpty {
            return [
              "kind": "movie",
              "source": "alloha",
              "playlist": [
                "primaryUrl": singleIframe,
                "hlsUrl": NSNull(),
                "dashUrl": NSNull(),
                "voiceovers": [],
                "subtitles": []
              ],
              "allohaVariants": [[
                "id": "0-\(singleIframe)",
                "title": "Основной",
                "url": singleIframe
              ]]
            ]
          }
          return [:]
        }

        var variants: [[String: Any]] = []
        // Sort by key to get consistent ordering
        for key in transObj.keys.sorted() {
          guard let transMap = castDict(transObj[key]),
                let iframe = transMap["iframe"] as? String,
                !iframe.isEmpty else { continue }
          let name = (transMap["name"] as? String) ?? "Озвучка \(variants.count + 1)"
          variants.append([
            "id": "\(key)-\(iframe)",
            "title": name,
            "url": iframe
          ])
        }

        if variants.isEmpty {
          if let singleIframe = payload["iframe"] as? String, !singleIframe.isEmpty {
            variants.append(["id": "0-\(singleIframe)", "title": "Основной", "url": singleIframe])
          } else {
            return [:]
          }
        }

        let primaryIframe = (variants.first?["url"] as? String) ?? ""
        return [
          "kind": "movie",
          "source": "alloha",
          "playlist": [
            "primaryUrl": primaryIframe,
            "hlsUrl": NSNull(),
            "dashUrl": NSNull(),
            "voiceovers": [],
            "subtitles": []
          ],
          "allohaVariants": variants
        ]
      }

      // --- Series: parse seasons/episodes ---
      guard let seasonsObj = castDict(payload["seasons"]), !seasonsObj.isEmpty else { return [:] }

      func firstIframe(from translationAny: Any?) -> String? {
        guard let transObj = castDict(translationAny) else { return nil }
        for (_, transRaw) in transObj {
          if let transMap = castDict(transRaw),
             let iframe = transMap["iframe"] as? String,
             !iframe.isEmpty {
            return iframe
          }
        }
        return nil
      }

      var seasons: [[String: Any]] = []
      for (seasonKey, seasonRaw) in seasonsObj {
        guard let seasonMap = castDict(seasonRaw), !seasonMap.isEmpty else { continue }

        let seasonNum = intFromAny(seasonMap["season"] ?? seasonKey, fallback: Int(seasonKey) ?? 1)
        let episodesObj = castDict(seasonMap["episodes"]) ?? [:]

        var episodes: [[String: Any]] = []
        for (episodeKey, episodeRaw) in episodesObj {
          guard let episodeMap = castDict(episodeRaw), !episodeMap.isEmpty else { continue }

          let episodeNum = intFromAny(episodeMap["episode"] ?? episodeKey, fallback: Int(episodeKey) ?? 1)
          let iframe = firstIframe(from: episodeMap["translation"])
            ?? (episodeMap["iframe"] as? String)
          guard let iframe, !iframe.isEmpty else { continue }

          episodes.append([
            "season": seasonNum,
            "episode": episodeNum,
            "title": "Episode \(episodeNum)",
            "playlist": [
              "primaryUrl": iframe,
              "hlsUrl": NSNull(),
              "dashUrl": NSNull(),
              "voiceovers": [],
              "subtitles": []
            ]
          ])
        }

        if episodes.isEmpty, let seasonIframe = seasonMap["iframe"] as? String, !seasonIframe.isEmpty {
          episodes.append([
            "season": seasonNum,
            "episode": 1,
            "title": "Episode 1",
            "playlist": [
              "primaryUrl": seasonIframe,
              "hlsUrl": NSNull(),
              "dashUrl": NSNull(),
              "voiceovers": [],
              "subtitles": []
            ]
          ])
        }

        let sorted = episodes.sorted { (($0["episode"] as? Int) ?? 0) < (($1["episode"] as? Int) ?? 0) }
        if !sorted.isEmpty {
          seasons.append([
            "season": seasonNum,
            "title": "Season \(seasonNum)",
            "episodes": sorted
          ])
        }
      }
      let sortedSeasons = seasons.sorted { (($0["season"] as? Int) ?? 0) < (($1["season"] as? Int) ?? 0) }
      if sortedSeasons.isEmpty { return [:] }
      return ["kind": "series", "source": "alloha", "seasons": sortedSeasons]
    }

    AsyncFunction("resolveAllohaPlayableFromIframe") { (iframeUrl: String) -> [String: Any] in
      var lastError: Error?
      for _ in 0..<3 {
        do {
          let resolver = await MainActor.run { AllohaRuntimeResolver() }
          return try await resolver.resolve(iframeUrl: iframeUrl)
        } catch {
          lastError = error
        }
      }
      throw lastError ?? NSError(
        domain: "NeomoviesCore",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Alloha runtime parser did not return playable URL (retry exhausted)"]
      )
    }

    OnCreate {
      self.bindPlayerCallbacksIfNeeded()
    }

    AsyncFunction("avPlayerLoad") { (url: String, headers: [String: String], autoplay: Bool, startPositionSec: Double?) async throws -> [String: Any] in
      let item = CollapsAVPlaylistItem(
        mediaId: url,
        title: "",
        url: url,
        headers: headers,
        season: nil,
        episode: nil,
        voiceovers: [],
        subtitles: [],
        audioVariants: []
      )
      _ = try await CollapsAVPlayerController.shared.configurePlaylist(items: [item], startIndex: 0, autoplay: autoplay)
      if let startPositionSec {
        _ = CollapsAVPlayerController.shared.seek(to: startPositionSec)
      }
      return CollapsAVPlayerController.shared.snapshot().asDictionary()
    }

    AsyncFunction("avPlayerConfigurePlaylist") { (items: [[String: Any]], startIndex: Int, autoplay: Bool, kpId: Int?) async throws -> [String: Any] in
      print("[NeomoviesCore] avPlayerConfigurePlaylist called with kpId: \(kpId ?? -1), items: \(items.count), startIndex: \(startIndex)")
      if let kpId = kpId {
        print("[NeomoviesCore] Setting kpId: \(kpId)")
        CollapsAVPlayerController.shared.setKinopoiskId(kpId)
      } else {
        print("[NeomoviesCore] WARNING: kpId is nil!")
      }
      let playlist = items.compactMap { dict -> CollapsAVPlaylistItem? in
        guard let url = dict["url"] as? String, !url.isEmpty else { return nil }
        let mediaId = (dict["mediaId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CollapsAVPlaylistItem(
          mediaId: (mediaId?.isEmpty == false) ? mediaId! : url,
          title: dict["title"] as? String ?? "",
          url: url,
          headers: dict["headers"] as? [String: String] ?? [:],
          season: dict["season"] as? Int,
          episode: dict["episode"] as? Int,
          voiceovers: dict["voiceovers"] as? [String] ?? [],
          subtitles: (dict["subtitles"] as? [[String: String]] ?? []).map {
            CollapsSubtitle(
              url: $0["url"] ?? "",
              label: $0["label"] ?? "",
              language: $0["language"] ?? ""
            )
          },
          audioVariants: (dict["audioVariants"] as? [[String: Any]] ?? []).compactMap { variant in
            guard let vurl = variant["url"] as? String, !vurl.isEmpty else { return nil }
            let title = (variant["title"] as? String) ?? ""
            let qualityVariants = (variant["qualityVariants"] as? [[String: Any]] ?? []).compactMap { quality -> CollapsAVQualityOption? in
              guard let qurl = quality["url"] as? String, !qurl.isEmpty else { return nil }
              let label = (quality["label"] as? String) ?? "Stream"
              let bitrate = quality["bitrate"] as? Double ?? quality["bandwidth"] as? Double ?? 0
              let height = quality["height"] as? Int
              return CollapsAVQualityOption(index: 0, bitrate: bitrate, height: height, label: label, isAuto: false, url: qurl)
            }
            return CollapsAVAudioVariant(title: title, url: vurl, qualityVariants: qualityVariants)
          },
          qualityVariants: (dict["qualityVariants"] as? [[String: Any]] ?? []).compactMap { quality -> CollapsAVQualityOption? in
            guard let qurl = quality["url"] as? String, !qurl.isEmpty else { return nil }
            let label = (quality["label"] as? String) ?? "Stream"
            let bitrate = quality["bitrate"] as? Double ?? quality["bandwidth"] as? Double ?? 0
            let height = quality["height"] as? Int
            return CollapsAVQualityOption(index: 0, bitrate: bitrate, height: height, label: label, isAuto: false, url: qurl)
          },
          voiceoverLabel: dict["voiceoverLabel"] as? String
        )
      }
      let state = try await CollapsAVPlayerController.shared.configurePlaylist(items: playlist, startIndex: startIndex, autoplay: autoplay)
      return state.asDictionary()
    }

    AsyncFunction("avPlayerPresentNativeUI") { () async in
      await MainActor.run {
        CollapsAVPlayerController.shared.presentNativePlayer()
      }
    }

    AsyncFunction("avPlayerDismissNativeUI") { () async in
      await MainActor.run {
        CollapsAVPlayerController.shared.dismissNativePlayer()
      }
    }

    AsyncFunction("avPlayerSelectEpisode") { (index: Int, autoplay: Bool) async throws -> [String: Any] in
      let state = try await CollapsAVPlayerController.shared.selectEpisodeAsync(index: index, autoplay: autoplay)
      return state.asDictionary()
    }

    AsyncFunction("avPlayerNextEpisode") { (autoplay: Bool) async throws -> [String: Any] in
      let state = try await CollapsAVPlayerController.shared.nextEpisodeAsync(autoplay: autoplay)
      return state.asDictionary()
    }

    AsyncFunction("avPlayerPreviousEpisode") { (autoplay: Bool) async throws -> [String: Any] in
      let state = try await CollapsAVPlayerController.shared.previousEpisodeAsync(autoplay: autoplay)
      return state.asDictionary()
    }

    Function("avPlayerPlay") { () -> [String: Any] in
      CollapsAVPlayerController.shared.play().asDictionary()
    }

    Function("avPlayerPause") { () -> [String: Any] in
      CollapsAVPlayerController.shared.pause().asDictionary()
    }

    Function("avPlayerStop") { () in
      CollapsAVPlayerController.shared.stop()
    }

    Function("avPlayerSeek") { (positionSec: Double) -> [String: Any] in
      CollapsAVPlayerController.shared.seek(to: positionSec).asDictionary()
    }

    Function("avPlayerSetRate") { (rate: Double) -> [String: Any] in
      CollapsAVPlayerController.shared.setRate(Float(rate)).asDictionary()
    }

    Function("avPlayerSetPreferredPeakBitRate") { (bitrate: Double) in
      CollapsAVPlayerController.shared.setPreferredPeakBitRate(bitrate)
    }

    AsyncFunction("avPlayerRefreshQualityOptions") { () async -> [[String: Any]] in
      await CollapsAVPlayerController.shared.refreshQualityOptions()
    }

    Function("avPlayerListQualityOptions") { () -> [[String: Any]] in
      CollapsAVPlayerController.shared.listQualityOptions()
    }

    Function("avPlayerSelectQuality") { (index: Int?) in
      CollapsAVPlayerController.shared.selectQuality(index: index)
    }

    Function("avPlayerSnapshot") { () -> [String: Any] in
      CollapsAVPlayerController.shared.snapshot().asDictionary()
    }

    Function("avPlayerListAudioTracks") { () -> [[String: Any]] in
      return CollapsAVPlayerController.shared.listAudioTracks()
    }

    Function("avPlayerSelectAudioTrack") { (index: Int?) in
      CollapsAVPlayerController.shared.selectAudioTrack(index: index)
    }

    Function("avPlayerListSubtitleTracks") { () -> [[String: Any]] in
      return CollapsAVPlayerController.shared.listSubtitleTracks()
    }

    Function("avPlayerSelectSubtitleTrack") { (index: Int?) in
      CollapsAVPlayerController.shared.selectSubtitleTrack(index: index)
    }

    Function("getCollapsWatchProgress") { (kpId: Int, season: Int?, episode: Int?) -> [String: Any] in
      let store = CollapsPlaybackProgressStore.shared

      let lastSeason = store.loadLastSeason(kpId: kpId)
      let lastEpisode = store.loadLastEpisode(kpId: kpId)

      let resolvedSeason = season ?? lastSeason
      let resolvedEpisode = episode ?? lastEpisode

      let mediaId: String
      if let s = resolvedSeason, let e = resolvedEpisode {
        mediaId = "kp_\(kpId)_s\(s)_e\(e)"
      } else {
        mediaId = "kp_\(kpId)"
      }

      let positionMs = Int(store.load(mediaId: mediaId) * 1000)
      let durationMs = Int(store.loadDuration(mediaId: mediaId) * 1000)
      let watched = store.loadWatched(mediaId: mediaId)
      let updatedAtMs = store.loadUpdatedAtMs(mediaId: mediaId)
      let progressPercent = clampedProgressPercent(positionMs: positionMs, durationMs: durationMs)

      let lastMediaId: String
      if let ls = lastSeason, let le = lastEpisode {
        lastMediaId = "kp_\(kpId)_s\(ls)_e\(le)"
      } else {
        lastMediaId = "kp_\(kpId)"
      }
      let lastPositionMs = Int(store.load(mediaId: lastMediaId) * 1000)
      let lastDurationMs = Int(store.loadDuration(mediaId: lastMediaId) * 1000)
      let lastUpdatedAtMs = store.loadUpdatedAtMs(mediaId: lastMediaId)

      func opt(_ v: Int?) -> Any { v.map { $0 as Any } ?? NSNull() }

      return [
        "schemaVersion": 1,
        "source": "collaps",
        "mediaId": mediaId,
        "kpId": kpId,
        "season": opt(resolvedSeason),
        "episode": opt(resolvedEpisode),
        "kind": (resolvedSeason != nil && resolvedEpisode != nil) ? "episode" : "movie_or_generic",
        "positionMs": positionMs,
        "durationMs": durationMs,
        "progressPercent": progressPercent,
        "watched": watched,
        "updatedAtMs": updatedAtMs,
        "lastSeason": opt(lastSeason),
        "lastEpisode": opt(lastEpisode),
        "lastPositionMs": lastPositionMs,
        "lastDurationMs": lastDurationMs,
        "lastUpdatedAtMs": lastUpdatedAtMs,
      ]
    }

    Function("listCollapsWatchProgressRecords") { (kpId: Int?) -> [[String: Any]] in
      let store = CollapsPlaybackProgressStore.shared
      let allDefaults = UserDefaults.standard.dictionaryRepresentation()
      let prefix = store.positionKeyPrefix
      guard
        let episodeRegex = try? NSRegularExpression(pattern: "^kp_(\\d+)_s(\\d+)_e(\\d+)$"),
        let movieRegex = try? NSRegularExpression(pattern: "^kp_(\\d+)$")
      else { return [] }

      var records: [[String: Any]] = []
      var seriesKpIds = Set<Int>()
      for key in allDefaults.keys {
        guard key.hasPrefix(prefix) else { continue }
        let mediaId = String(key.dropFirst(prefix.count))
        let range = NSRange(mediaId.startIndex..., in: mediaId)
        guard let match = episodeRegex.firstMatch(in: mediaId, range: range) else { continue }
        guard
          let kidRange = Range(match.range(at: 1), in: mediaId),
          let sRange   = Range(match.range(at: 2), in: mediaId),
          let eRange   = Range(match.range(at: 3), in: mediaId),
          let itemKpId = Int(mediaId[kidRange]),
          let season   = Int(mediaId[sRange]),
          let episode  = Int(mediaId[eRange])
        else { continue }

        if let kpId = kpId, itemKpId != kpId { continue }
        seriesKpIds.insert(itemKpId)

        let positionMs   = Int(store.load(mediaId: mediaId) * 1000)
        let durationMs   = Int(store.loadDuration(mediaId: mediaId) * 1000)
        let watched      = store.loadWatched(mediaId: mediaId)
        let updatedAtMs  = store.loadUpdatedAtMs(mediaId: mediaId)
        let progressPercent = clampedProgressPercent(positionMs: positionMs, durationMs: durationMs)

        records.append([
          "schemaVersion": 1,
          "source": "collaps",
          "mediaId": mediaId,
          "kpId": itemKpId,
          "season": season,
          "episode": episode,
          "kind": "episode",
          "positionMs": positionMs,
          "durationMs": durationMs,
          "progressPercent": progressPercent,
          "watched": watched,
          "updatedAtMs": updatedAtMs,
        ])
      }

      for key in allDefaults.keys {
        guard key.hasPrefix(prefix) else { continue }
        let mediaId = String(key.dropFirst(prefix.count))
        let range = NSRange(mediaId.startIndex..., in: mediaId)
        guard let match = movieRegex.firstMatch(in: mediaId, range: range) else { continue }
        guard
          let kidRange = Range(match.range(at: 1), in: mediaId),
          let itemKpId = Int(mediaId[kidRange])
        else { continue }

        if let kpId = kpId, itemKpId != kpId { continue }
        if seriesKpIds.contains(itemKpId) { continue }

        let positionMs = Int(store.load(mediaId: mediaId) * 1000)
        let durationMs = Int(store.loadDuration(mediaId: mediaId) * 1000)
        let watched = store.loadWatched(mediaId: mediaId)
        let updatedAtMs = store.loadUpdatedAtMs(mediaId: mediaId)
        let progressPercent = clampedProgressPercent(positionMs: positionMs, durationMs: durationMs)

        records.append([
          "schemaVersion": 1,
          "source": "collaps",
          "mediaId": mediaId,
          "kpId": itemKpId,
          "season": NSNull(),
          "episode": NSNull(),
          "kind": "movie_or_generic",
          "positionMs": positionMs,
          "durationMs": durationMs,
          "progressPercent": progressPercent,
          "watched": watched,
          "updatedAtMs": updatedAtMs,
        ])
      }

      return records.sorted { ($0["updatedAtMs"] as? Int ?? 0) > ($1["updatedAtMs"] as? Int ?? 0) }
    }
  }

  private func bindPlayerCallbacksIfNeeded() {
    if didBindPlayerCallbacks { return }
    didBindPlayerCallbacks = true

    CollapsAVPlayerController.shared.onStateChanged = { [weak self] state in
      self?.sendEvent("onAVPlayerStateChanged", state.asDictionary())
    }
    CollapsAVPlayerController.shared.onProgress = { [weak self] state in
      self?.sendEvent("onAVPlayerProgress", state.asDictionary())
    }
    CollapsAVPlayerController.shared.onEpisodeChanged = { [weak self] state in
      self?.sendEvent("onAVPlayerEpisodeChanged", state.asDictionary())
    }
    CollapsAVPlayerController.shared.onPlayerDismissed = { [weak self] in
      self?.sendEvent("onAVPlayerDismissed", [:])
    }
  }
}
