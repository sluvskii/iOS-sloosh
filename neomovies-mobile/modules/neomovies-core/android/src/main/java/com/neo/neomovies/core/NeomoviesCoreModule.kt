package com.neo.neomovies.core

import android.media.MediaCodecList
import androidx.media3.common.util.UnstableApi
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition
import java.net.URL
import kotlin.math.roundToInt
import org.json.JSONObject
import java.net.URI

@UnstableApi
class NeomoviesCoreModule : Module() {
  private fun extractIframeSrc(html: String): String? {
    val match = Regex("""<iframe[^>]+src=["']([^"']+)["']""", RegexOption.IGNORE_CASE).find(html)
    return match?.groupValues?.getOrNull(1)
  }

  private fun extractDirectStreamUrl(html: String, baseUrl: String): String? {
    val patterns = listOf(
      Regex("""https?:\\\/\\\/[^"'\s>]+?\.(m3u8|mpd)[^"'\s>]*""", RegexOption.IGNORE_CASE),
      Regex("""https?://[^"'\s>]+?\.(m3u8|mpd)[^"'\s>]*""", RegexOption.IGNORE_CASE),
    )
    for (pattern in patterns) {
      val raw = pattern.find(html)?.value?.replace("\\/", "/") ?: continue
      return runCatching { URI(baseUrl).resolve(raw).toString() }.getOrDefault(raw)
    }
    return null
  }

  private fun toProgressPercent(positionMs: Long, durationMs: Long): Int {
    if (positionMs <= 0L || durationMs <= 0L) return 0
    return ((positionMs.toDouble() / durationMs.toDouble()) * 100.0)
      .roundToInt()
      .coerceIn(0, 100)
  }

  private fun buildWatchProgressPayload(
    kpId: Int,
    season: Int?,
    episode: Int?,
    positionMs: Long,
    durationMs: Long,
    watched: Boolean,
    updatedAtMs: Long,
  ): Map<String, Any?> {
    val mediaId = "kp_$kpId"
    return mapOf(
      "schemaVersion" to 1,
      "source" to "collaps",
      "mediaId" to mediaId,
      "kpId" to kpId,
      "season" to season,
      "episode" to episode,
      "kind" to if (season != null && episode != null) "episode" else "movie_or_generic",
      "positionMs" to positionMs,
      "durationMs" to durationMs,
      "progressPercent" to toProgressPercent(positionMs, durationMs),
      "watched" to watched,
      "updatedAtMs" to updatedAtMs,
    )
  }

  override fun definition() = ModuleDefinition {
    Name("NeomoviesCore")
    
    Events("onExoPlayerClosed")
    
    OnCreate {
      PlayerActivity.onPlayerClosed = {
        sendEvent("onExoPlayerClosed", mapOf<String, Any>())
      }
    }
    
    // Launch native ExoPlayer activity
    AsyncFunction("exoPlayerLaunch") { url: String, headers: Map<String, String>?, title: String?, kpId: Int? ->
      val activity = appContext.currentActivity ?: throw Exception("No current activity")
      val intent = android.content.Intent(activity, PlayerActivity::class.java).apply {
        putExtra(PlayerActivity.EXTRA_URL, url)
        putExtra(PlayerActivity.EXTRA_TITLE, title)
        putExtra(PlayerActivity.EXTRA_USE_EXO, true)
        putExtra(PlayerActivity.EXTRA_USE_COLLAPS_HEADERS, headers != null && headers.isNotEmpty())
        if (kpId != null) {
          putExtra(PlayerActivity.EXTRA_KINOPOISK_ID, kpId)
        }
        headers?.forEach { (key, value) ->
          putExtra("HEADER_$key", value)
        }
      }
      activity.startActivity(intent)
    }

    AsyncFunction("exoPlayerLaunchPlaylist") { 
      urls: List<String>, 
      startIndex: Int, 
      headers: Map<String, String>?, 
      names: List<String>?, 
      title: String?, 
      voiceNames: List<String>?, 
      kpId: Int? ->
      val activity = appContext.currentActivity ?: throw Exception("No current activity")
      val intent = android.content.Intent(activity, PlayerActivity::class.java).apply {
        putStringArrayListExtra(PlayerActivity.EXTRA_URLS, ArrayList(urls))
        if (!names.isNullOrEmpty()) {
          putStringArrayListExtra(PlayerActivity.EXTRA_NAMES, ArrayList(names))
        }
        if (!voiceNames.isNullOrEmpty()) {
          putStringArrayListExtra(PlayerActivity.EXTRA_VOICE_NAMES, ArrayList(voiceNames))
        }
        putExtra(PlayerActivity.EXTRA_START_INDEX, startIndex)
        putExtra(PlayerActivity.EXTRA_TITLE, title)
        putExtra(PlayerActivity.EXTRA_USE_EXO, true)
        if (kpId != null) {
          putExtra(PlayerActivity.EXTRA_KINOPOISK_ID, kpId)
        }
        putExtra(PlayerActivity.EXTRA_USE_COLLAPS_HEADERS, headers != null && headers.isNotEmpty())
        headers?.forEach { (key, value) ->
          putExtra("HEADER_$key", value)
        }
      }
      activity.startActivity(intent)
    }
    
    AsyncFunction("exoPlayerSetAllohaVariants") {
      audioVariantsJson: String?,
      qualityVariantsJson: String? ->
      // Parse JSON strings to avoid Expo Modules nested object conversion issues
      PlayerActivity.pendingAllohaAudioVariants = audioVariantsJson?.let { json ->
        try {
          val arr = org.json.JSONArray(json)
          ArrayList<Map<String, Any>>().apply {
            for (i in 0 until arr.length()) {
              val obj = arr.getJSONObject(i)
              val map = mutableMapOf<String, Any>()
              obj.keys().forEach { key ->
                when (val value = obj.get(key)) {
                  is org.json.JSONArray -> {
                    val list = mutableListOf<Map<String, Any>>()
                    for (j in 0 until value.length()) {
                      val inner = value.getJSONObject(j)
                      val innerMap = mutableMapOf<String, Any>()
                      inner.keys().forEach { k -> innerMap[k] = inner.get(k) }
                      list.add(innerMap)
                    }
                    map[key] = list
                  }
                  else -> map[key] = value
                }
              }
              add(map)
            }
          }
        } catch (e: Exception) { null }
      }
      PlayerActivity.pendingAllohaQualityVariants = qualityVariantsJson?.let { json ->
        try {
          val arr = org.json.JSONArray(json)
          ArrayList<Map<String, Any>>().apply {
            for (i in 0 until arr.length()) {
              val obj = arr.getJSONObject(i)
              val map = mutableMapOf<String, Any>()
              obj.keys().forEach { key -> map[key] = obj.get(key) }
              add(map)
            }
          }
        } catch (e: Exception) { null }
      }
    }
    
    AsyncFunction("exoPlayerSetAllohaEpisodes") {
      episodeIframeUrlsJson: String?,
      episodeNamesJson: String?,
      startIndex: Int,
      headersJson: String?,
      title: String? ->
      val iframeUrls = episodeIframeUrlsJson?.let { json ->
        try {
          val arr = org.json.JSONArray(json)
          (0 until arr.length()).map { arr.getString(it) }
        } catch (e: Exception) { 
          android.util.Log.e("NeomoviesCore", "Failed to parse episodeIframeUrlsJson", e)
          emptyList() 
        }
      } ?: emptyList()
      
      val names = episodeNamesJson?.let { json ->
        try {
          val arr = org.json.JSONArray(json)
          (0 until arr.length()).map { arr.getString(it) }
        } catch (e: Exception) { 
          android.util.Log.e("NeomoviesCore", "Failed to parse episodeNamesJson", e)
          emptyList() 
        }
      } ?: emptyList()
      
      val headers = headersJson?.let { json ->
        try {
          val obj = org.json.JSONObject(json)
          obj.keys().asSequence().associateWith { obj.getString(it) }
        } catch (e: Exception) { emptyMap() }
      } ?: emptyMap()
      
      android.util.Log.d("NeomoviesCore", "exoPlayerSetAllohaEpisodes: ${iframeUrls.size} episodes, startIndex=$startIndex, title=$title")
      AllohaEpisodeHolder.setEpisodes(iframeUrls, names, startIndex, headers, title ?: "")
    }

    AsyncFunction("exoPlayerLaunchAlloha") { iframeUrl: String, title: String?, kpId: Int? ->
      val activity = appContext.currentActivity ?: throw Exception("No current activity")
      val intent = android.content.Intent(activity, PlayerActivity::class.java).apply {
        putExtra(PlayerActivity.EXTRA_ALLOHA_IFRAME_URL, iframeUrl)
        putExtra(PlayerActivity.EXTRA_TITLE, title)
        putExtra(PlayerActivity.EXTRA_USE_EXO, true)
        putExtra(PlayerActivity.EXTRA_USE_COLLAPS_HEADERS, true)
        if (kpId != null) putExtra(PlayerActivity.EXTRA_KINOPOISK_ID, kpId)
      }
      activity.startActivity(intent)
    }
    
    Function("exoPlayerGetAllohaEpisodeState") {
      mapOf(
        "currentIndex" to AllohaEpisodeHolder.currentEpisodeIndex,
        "totalEpisodes" to AllohaEpisodeHolder.episodeIframeUrls.size,
        "hasPrevious" to AllohaEpisodeHolder.hasPreviousEpisode(),
        "hasNext" to AllohaEpisodeHolder.hasNextEpisode(),
        "currentName" to AllohaEpisodeHolder.currentEpisodeName()
      )
    }
    
    // Export ExoPlayerView component
    View(ExoPlayerView::class) {
      Events("onReady", "onError", "onProgress", "onPlaybackStateChanged")
      
      Prop("source") { view: ExoPlayerView, url: String ->
        view.setSource(url)
      }
      
      Prop("paused") { view: ExoPlayerView, paused: Boolean ->
        if (paused) view.pause() else view.play()
      }
      
      Prop("playbackSpeed") { view: ExoPlayerView, speed: Float ->
        view.setPlaybackSpeed(speed)
      }
      
      AsyncFunction("seekTo") { view: ExoPlayerView, positionMs: Long ->
        view.seekTo(positionMs)
      }
    }

    View(EpisodesListView::class) {
      Events("onEpisodePress", "onContentHeight", "onDownloadPress")

      Prop("episodes") { view: EpisodesListView, episodes: List<Map<String, Any?>> ->
        view.setEpisodes(episodes)
      }

      Prop("textColor") { view: EpisodesListView, color: String? ->
        view.setTextColor(color)
      }

      Prop("secondaryTextColor") { view: EpisodesListView, color: String? ->
        view.setSecondaryTextColor(color)
      }

      Prop("borderColor") { view: EpisodesListView, color: String? ->
        view.setBorderColor(color)
      }

      Prop("backgroundColor") { view: EpisodesListView, color: String? ->
        view.setBackgroundColorHex(color)
      }
    }

    Function("parseCollapsCatalog") { embedHtml: String ->
      CollapsParser.parseCollapsCatalog(embedHtml)
    }

    Function("parseAllohaRuntimePayload") { payload: String, baseUrl: String, headers: Map<String, String>? ->
      AllohaRuntimeParser.parsePayload(payload, baseUrl, headers ?: emptyMap())
    }

    Function("rewriteCollapsHlsMaster") { master: String, voices: List<String>, subtitles: List<Map<String, String>>, mediaId: String ->
      val parsedSubtitles = subtitles.map {
        CollapsSubtitle(
          url = it["url"] ?: "",
          label = it["label"] ?: "",
          language = it["language"] ?: ""
        )
      }
      CollapsHlsRewriter.rewrite(master, voices, parsedSubtitles, mediaId)
    }

    Function("rewriteCollapsDashManifest") { manifest: String, voices: List<String>, subtitles: List<Map<String, String>>, mediaId: String ->
      val parsedSubtitles = subtitles.map {
        CollapsSubtitle(
          url = it["url"] ?: "",
          label = it["label"] ?: "",
          language = it["language"] ?: ""
        )
      }
      CollapsDashRewriter.rewrite(manifest, voices, parsedSubtitles, mediaId)
    }

    AsyncFunction("rewriteCollapsHlsFromUrl") { hlsUrl: String, voices: List<String>, subtitles: List<Map<String, String>>, mediaId: String, referer: String?, origin: String? ->
      val parsedSubtitles = subtitles.map {
        CollapsSubtitle(
          url = it["url"] ?: "",
          label = it["label"] ?: "",
          language = it["language"] ?: ""
        )
      }
      
      val masterPlaylist = kotlinx.coroutines.runBlocking {
        CollapsHTTPClient.fetch(hlsUrl, referer, origin)
      }
      CollapsHlsRewriter.rewrite(masterPlaylist, voices, parsedSubtitles, mediaId)
    }

    AsyncFunction("rewriteCollapsDashFromUrl") { dashUrl: String, voices: List<String>, subtitles: List<Map<String, String>>, mediaId: String, referer: String?, origin: String? ->
      val parsedSubtitles = subtitles.map {
        CollapsSubtitle(
          url = it["url"] ?: "",
          label = it["label"] ?: "",
          language = it["language"] ?: ""
        )
      }
      
      val manifest = kotlinx.coroutines.runBlocking {
        CollapsHTTPClient.fetch(dashUrl, referer, origin)
      }
      CollapsDashRewriter.rewrite(manifest, voices, parsedSubtitles, mediaId)
    }

    AsyncFunction("collapsDashContainsAv1") { dashUrl: String, referer: String?, origin: String? ->
      val manifest = kotlinx.coroutines.runBlocking {
        CollapsHTTPClient.fetch(dashUrl, referer, origin)
      }
      manifest.contains("av01", ignoreCase = true)
    }

    AsyncFunction("fetchUrlTextInsecure") { url: String, referer: String?, origin: String? ->
      kotlinx.coroutines.runBlocking {
        CollapsHTTPClient.fetch(url, referer, origin)
      }
    }

    AsyncFunction("fetchAllohaSeriesCatalog") { kpId: String, _token: String ->
      val apiUrl = "https://api.neomovies.ru/api/v1/alloha/catalog/kp/${java.net.URLEncoder.encode(kpId, "UTF-8")}"
      val body = kotlinx.coroutines.runBlocking {
        CollapsHTTPClient.fetch(apiUrl, "https://api.neomovies.ru/", "https://api.neomovies.ru")
      }
      val root = JSONObject(body)
      val data = root.optJSONObject("data") ?: return@AsyncFunction emptyMap<String, Any>()

      val category = data.optInt("category", 0)
      val transIframeObj = data.optJSONObject("translation_iframe")
      val seasonsObj = data.optJSONObject("seasons")

      // --- Movie: category == 1 or has translation_iframe, and no seasons ---
      if ((category == 1 || transIframeObj != null) && seasonsObj == null) {
        val variants = mutableListOf<Map<String, Any>>()
        if (transIframeObj != null) {
          transIframeObj.keys().asSequence().sorted().forEach { key ->
            val trans = transIframeObj.optJSONObject(key) ?: return@forEach
            val iframe = trans.optString("iframe", "").takeIf { it.isNotBlank() } ?: return@forEach
            val name = trans.optString("name", "").takeIf { it.isNotBlank() } ?: "Озвучка ${variants.size + 1}"
            variants.add(mapOf("id" to "$key-$iframe", "title" to name, "url" to iframe))
          }
        }
        if (variants.isEmpty()) {
          val singleIframe = data.optString("iframe", "").takeIf { it.isNotBlank() }
            ?: return@AsyncFunction emptyMap<String, Any>()
          variants.add(mapOf("id" to "0-$singleIframe", "title" to "Основной", "url" to singleIframe))
        }
        val primaryIframe = variants.first()["url"] as? String ?: ""
        return@AsyncFunction mapOf(
          "kind" to "movie",
          "source" to "alloha",
          "playlist" to mapOf(
            "primaryUrl" to primaryIframe,
            "hlsUrl" to null,
            "dashUrl" to null,
            "voiceovers" to emptyList<String>(),
            "subtitles" to emptyList<Map<String, String>>()
          ),
          "allohaVariants" to variants
        )
      }

      // --- Series: parse seasons/episodes ---
      if (seasonsObj == null) return@AsyncFunction emptyMap<String, Any>()

      val seasons = mutableListOf<Map<String, Any>>()
      seasonsObj.keys().forEach { seasonKey ->
        val seasonObj = seasonsObj.optJSONObject(seasonKey) ?: return@forEach
        val episodesObj = seasonObj.optJSONObject("episodes") ?: return@forEach
        val episodes = mutableListOf<Map<String, Any>>()

        episodesObj.keys().forEach { episodeKey ->
          val episodeObj = episodesObj.optJSONObject(episodeKey) ?: return@forEach
          val transObj = episodeObj.optJSONObject("translation") ?: return@forEach
          var iframeUrl: String? = null
          transObj.keys().forEach { tKey ->
            if (iframeUrl != null) return@forEach
            iframeUrl = transObj.optJSONObject(tKey)?.optString("iframe")?.takeIf { it.isNotBlank() }
          }
          val season = seasonKey.toIntOrNull() ?: 1
          val episode = episodeKey.toIntOrNull() ?: 1
          val iframe = iframeUrl ?: return@forEach
          episodes.add(
            mapOf(
              "season" to season,
              "episode" to episode,
              "title" to "Episode $episode",
              "playlist" to mapOf(
                "primaryUrl" to iframe,
                "hlsUrl" to null,
                "dashUrl" to null,
                "voiceovers" to emptyList<String>(),
                "subtitles" to emptyList<Map<String, String>>(),
              )
            )
          )
        }

        val seasonNum = seasonKey.toIntOrNull() ?: 1
        val sortedEpisodes = episodes.sortedBy { (it["episode"] as? Int) ?: 0 }
        if (sortedEpisodes.isNotEmpty()) {
          seasons.add(
            mapOf(
              "season" to seasonNum,
              "title" to "Season $seasonNum",
              "episodes" to sortedEpisodes
            )
          )
        }
      }

      if (seasons.isEmpty()) return@AsyncFunction emptyMap<String, Any>()
      mapOf("kind" to "series", "source" to "alloha", "seasons" to seasons.sortedBy { (it["season"] as? Int) ?: 0 })
    }

    AsyncFunction("resolveAllohaPlayableFromIframe") { iframeUrl: String ->
      val context = appContext.reactContext ?: throw Exception("No react context")
      runCatching {
        val resolved = kotlinx.coroutines.runBlocking {
          AllohaRuntimeResolver(context).resolve(iframeUrl)
        }
        return@AsyncFunction resolved
      }

      val visited = mutableSetOf<String>()
      var currentUrl = iframeUrl
      var lastReason = "unknown"

      repeat(3) {
        if (!visited.add(currentUrl)) return@repeat
        val origin = runCatching { URL(currentUrl).let { "${it.protocol}://${it.host}" } }.getOrNull() ?: return@repeat
        val html = kotlinx.coroutines.runBlocking {
          CollapsHTTPClient.fetch(currentUrl, "$origin/", origin)
        }
        val parsed = AllohaRuntimeParser.parsePayload(html, origin, mapOf("Referer" to "$origin/", "Origin" to origin))
        val parsedAudioVariants: List<Map<String, Any?>> = (parsed?.get("audioVariants") as? List<*>)
          ?.mapNotNull { raw ->
            val item = raw as? Map<*, *> ?: return@mapNotNull null
            item.entries
              .filter { it.key is String }
              .associate { (k, v) -> k as String to v }
          }
          ?: emptyList()
        val parsedSubtitles: List<Map<String, String>> = (parsed?.get("subtitles") as? List<*>)
          ?.mapNotNull { raw ->
            val item = raw as? Map<*, *> ?: return@mapNotNull null
            val title = item["title"] as? String ?: return@mapNotNull null
            val url = item["url"] as? String ?: return@mapNotNull null
            mapOf("title" to title, "url" to url)
          }
          ?: emptyList()
        val parsedQualityVariants: List<Map<String, Any?>> = (parsed?.get("qualityVariants") as? List<*>)
          ?.mapNotNull { raw ->
            val item = raw as? Map<*, *> ?: return@mapNotNull null
            item.entries
              .filter { it.key is String }
              .associate { (k, v) -> k as String to v }
          }
          ?: emptyList()
        val parsedHeaders: Map<String, String> = (parsed?.get("httpHeaders") as? Map<*, *>)
          ?.entries
          ?.filter { it.key is String && it.value is String }
          ?.associate { (k, v) -> k as String to v as String }
          ?: emptyMap()
        val parsedUrl = parsedAudioVariants
          .firstOrNull { (it["url"] as? String).isNullOrBlank().not() }
          ?.get("url") as? String ?: (parsed?.get("videoURL") as? String ?: "")
        if (parsedUrl.isNotBlank()) {
          return@AsyncFunction mapOf(
            "url" to parsedUrl,
            "subtitles" to parsedSubtitles,
            "audioVariants" to parsedAudioVariants,
            "qualityVariants" to parsedQualityVariants,
            "headers" to parsedHeaders
          )
        }
        extractDirectStreamUrl(html, origin)?.let {
          return@AsyncFunction mapOf("url" to it, "subtitles" to parsedSubtitles)
        }
        val nested = extractIframeSrc(html)
        if (!nested.isNullOrBlank()) {
          currentUrl = runCatching { URI(currentUrl).resolve(nested).toString() }.getOrDefault(nested)
          lastReason = "nested_iframe_followed"
        } else {
          lastReason = "no_stream_no_iframe"
          return@repeat
        }
      }
      throw Exception("Alloha runtime parser did not return playable URL ($lastReason)")
    }

    Function("collapsDeviceSupportsAv1") {
      val codecs = MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos
      codecs.any { codecInfo ->
        !codecInfo.isEncoder && codecInfo.supportedTypes.any { type ->
          type.equals("video/av01", ignoreCase = true)
        }
      }
    }

    Function("getCollapsWatchProgress") { kpId: Int, season: Int?, episode: Int? ->
      val context = appContext.reactContext ?: throw Exception("No react context")
      val watchedPrefs = context.getSharedPreferences("collaps_watched", android.content.Context.MODE_PRIVATE)

      val lastSeason = watchedPrefs.getInt("kp_${kpId}_last_season", 0)
      val lastEpisode = watchedPrefs.getInt("kp_${kpId}_last_episode", 0)
      val lastPosition = watchedPrefs.getLong("kp_${kpId}_last_position", 0L)
      val lastDuration = watchedPrefs.getLong("kp_${kpId}_last_duration", 0L)
      val lastUpdatedAt = watchedPrefs.getLong("kp_${kpId}_last_updated_at", 0L)

      val resolvedSeason = season ?: if (lastSeason > 0) lastSeason else null
      val resolvedEpisode = episode ?: if (lastEpisode > 0) lastEpisode else null

      val episodeKey = if (resolvedSeason != null && resolvedEpisode != null) {
        "kp_${kpId}_s${resolvedSeason}_e${resolvedEpisode}"
      } else {
        null
      }

      val episodePosition = episodeKey?.let { watchedPrefs.getLong(it, 0L) } ?: 0L
      val episodeWatched = episodeKey?.let { watchedPrefs.getBoolean("${it}_watched", false) } ?: false
      val episodeDuration = episodeKey?.let { watchedPrefs.getLong("${it}_duration", 0L) } ?: 0L
      val episodeUpdatedAt = episodeKey?.let { watchedPrefs.getLong("${it}_updated_at", 0L) } ?: 0L

      // For movies (no episodeKey), fall back to generic kp progress
      val resolvedPosition = if (episodeKey == null) lastPosition else episodePosition
      val resolvedDuration = if (episodeKey == null) lastDuration else episodeDuration
      val resolvedWatched = if (episodeKey == null) {
        lastDuration > 0 && lastPosition >= maxOf((lastDuration * 0.85f).toLong(), lastDuration - 180_000L)
      } else episodeWatched
      val resolvedUpdatedAt = if (episodeKey == null) lastUpdatedAt else episodeUpdatedAt

      val payload = buildWatchProgressPayload(
        kpId = kpId,
        season = resolvedSeason,
        episode = resolvedEpisode,
        positionMs = resolvedPosition,
        durationMs = resolvedDuration,
        watched = resolvedWatched,
        updatedAtMs = resolvedUpdatedAt,
      )

      payload + mapOf(
        "lastSeason" to (if (lastSeason > 0) lastSeason else null),
        "lastEpisode" to (if (lastEpisode > 0) lastEpisode else null),
        "lastPositionMs" to lastPosition,
        "lastDurationMs" to lastDuration,
        "lastUpdatedAtMs" to lastUpdatedAt,
      )
    }

    Function("listCollapsWatchProgressRecords") { kpId: Int? ->
      val context = appContext.reactContext ?: throw Exception("No react context")
      val watchedPrefs = context.getSharedPreferences("collaps_watched", android.content.Context.MODE_PRIVATE)
      val entries = watchedPrefs.all
      val episodePattern = Regex("^kp_(\\d+)_s(\\d+)_e(\\d+)$")
      val moviePattern = Regex("^kp_(\\d+)_last_position$")

      val episodeRecords = entries.keys.mapNotNull { key ->
          val match = episodePattern.matchEntire(key) ?: return@mapNotNull null
          val itemKpId = match.groupValues[1].toIntOrNull() ?: return@mapNotNull null
          if (kpId != null && itemKpId != kpId) return@mapNotNull null
          val season = match.groupValues[2].toIntOrNull() ?: return@mapNotNull null
          val episode = match.groupValues[3].toIntOrNull() ?: return@mapNotNull null
          val positionMs = watchedPrefs.getLong(key, 0L)
          val durationMs = watchedPrefs.getLong("${key}_duration", 0L)
          val watched = watchedPrefs.getBoolean("${key}_watched", false)
          val updatedAtMs = watchedPrefs.getLong("${key}_updated_at", 0L)
          buildWatchProgressPayload(kpId = itemKpId, season = season, episode = episode,
            positionMs = positionMs, durationMs = durationMs, watched = watched, updatedAtMs = updatedAtMs)
        }

      val movieRecords = entries.keys.mapNotNull { key ->
          val match = moviePattern.matchEntire(key) ?: return@mapNotNull null
          val itemKpId = match.groupValues[1].toIntOrNull() ?: return@mapNotNull null
          if (kpId != null && itemKpId != kpId) return@mapNotNull null
          // Skip if this kpId has episode records (it's a series, not a movie)
          if (episodeRecords.any { (it["kpId"] as? Int) == itemKpId }) return@mapNotNull null
          val positionMs = watchedPrefs.getLong(key, 0L)
          val durationMs = watchedPrefs.getLong("kp_${itemKpId}_last_duration", 0L)
          val updatedAtMs = watchedPrefs.getLong("kp_${itemKpId}_last_updated_at", 0L)
          val watched = durationMs > 0 && positionMs >= maxOf((durationMs * 0.85f).toLong(), durationMs - 180_000L)
          buildWatchProgressPayload(kpId = itemKpId, season = null, episode = null,
            positionMs = positionMs, durationMs = durationMs, watched = watched, updatedAtMs = updatedAtMs)
        }

      (episodeRecords + movieRecords).sortedByDescending { (it["updatedAtMs"] as? Long) ?: 0L }
    }
  }
}
