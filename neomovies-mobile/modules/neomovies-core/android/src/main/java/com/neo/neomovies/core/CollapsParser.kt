package com.neo.neomovies.core

import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

object CollapsParser {
    private const val TAG = "CollapsParser"

    fun parseCollapsCatalog(embedHtml: String): Map<String, Any> {
        if (embedHtml.isBlank()) {
            Log.e(TAG, "Empty HTML")
            return emptyMap()
        }

        Log.d(TAG, "HTML length: ${embedHtml.length}")

        // Try to parse as series
        val seasonsJson = extractSeasonsJson(embedHtml)
        if (seasonsJson != null) {
            Log.d(TAG, "Found seasons JSON, length: ${seasonsJson.length}")
            return parseSeries(seasonsJson)
        }

        Log.d(TAG, "No seasons JSON found, trying as movie")

        // Try to parse as movie
        val movieData = extractMovieData(embedHtml)
        if (movieData != null) {
            Log.d(TAG, "Found movie data")
            return parseMovie(movieData)
        }

        Log.e(TAG, "No movie data found")
        return emptyMap()
    }

    private fun extractSeasonsJson(html: String): String? {
        val idx = html.indexOf("seasons:", ignoreCase = true)
        if (idx < 0) return null

        val start = idx + "seasons:".length
        var end = start
        while (end < html.length) {
            val c = html[end]
            if (c == '\n' || c == '\r') break
            end++
        }

        return html.substring(start, end).trim().takeIf { it.startsWith("[") }
    }

    private fun extractMovieData(html: String): Map<String, String>? {
        val data = mutableMapOf<String, String>()
        val scopedHtml = extractMakePlayerSourceBlock(html) ?: html

        // Extract DASH URLs separately and prefer dasha over dash.
        val dashaPattern = Regex("""(?is)\bdasha\s*:\s*['"]([^'"]+\.mpd[^'"]*)['"]""")
        dashaPattern.find(scopedHtml)?.let {
            data["dasha"] = it.groupValues[1]
        }
        val dashPattern = Regex("""(?is)\bdash\s*:\s*['"]([^'"]+\.mpd[^'"]*)['"]""")
        dashPattern.find(scopedHtml)?.let {
            data["dash"] = it.groupValues[1]
        }

        // Extract HLS URL (hls with .m3u8 suffix)
        val hlsPattern = Regex("""(?is)\bhls\s*:\s*['"]([^'"]+\.m3u8[^'"]*)['"]""")
        hlsPattern.find(scopedHtml)?.let {
            data["hls"] = it.groupValues[1]
        }
        
        val voices = extractStringArrayFromObject(scopedHtml, "audio", "names")
            .ifEmpty { extractVoiceNamesFromSourceBlock(scopedHtml) }
            .ifEmpty { extractVoiceNamesFromAudioNamesRegex(scopedHtml) }
            .ifEmpty { extractVoiceNamesFromAudioSnippet(scopedHtml) }
            .ifEmpty { extractVoiceNamesFromTranslations(scopedHtml) }
            .ifEmpty { extractVoiceNamesFromInlineAudio(scopedHtml) }
        if (voices.isEmpty()) {
            val audioSnippet = Regex("(?is)\\baudio\\s*:[\\s\\S]{0,240}")
                .find(scopedHtml)
                ?.value
                ?.replace("\n", " ")
                ?.replace("\r", " ")
                ?.take(240)
            Log.d(TAG, "extractMovieData: voices empty, audioSnippet=$audioSnippet")
        }
        Log.d(TAG, "extractMovieData: voicesCount=${voices.size}, voices=${voices.take(6)}")
        if (voices.isNotEmpty()) {
            data["voices"] = voices.joinToString("|||")
        }
        
        val subtitles = extractSubtitlesArray(scopedHtml)
        if (subtitles.isNotEmpty()) {
            // Encode subtitles as JSON string to pass it
            val arr = JSONArray()
            subtitles.forEach { sub ->
                val obj = JSONObject()
                obj.put("url", sub["url"])
                obj.put("label", sub["label"])
                obj.put("language", sub["language"])
                arr.put(obj)
            }
            data["subtitles"] = arr.toString()
        }

        return if (data.isEmpty() && voices.isEmpty() && subtitles.isEmpty()) null else data
    }

    private fun extractStringArrayFromObject(html: String, objectKey: String, arrayKey: String): List<String> {
        val key1 = Regex.escape(objectKey)
        val key2 = Regex.escape(arrayKey)
        val patterns = listOf(
            Regex("(?is)[\"']?$key1[\"']?\\s*:\\s*\\{[\\s\\S]*?[\"']?$key2[\"']?\\s*:\\s*(\\[[\\s\\S]*?\\])"),
        )
        val raw = patterns.firstNotNullOfOrNull { it.find(html)?.groupValues?.getOrNull(1) }?.trim()
            ?: return emptyList()
        if (!raw.startsWith("[")) return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val v = arr.optString(i, "").trim()
                    if (v.isNotBlank()) add(v)
                }
            }
        }.getOrElse { parseJsStringArray(raw) }
    }

    private fun extractVoiceNamesFromTranslations(html: String): List<String> {
        val patterns = listOf(
            Regex("(?is)\\btranslations\\s*:\\s*(\\[[\\s\\S]*?\\])"),
            Regex("(?is)\\\"translations\\\"\\s*:\\s*(\\[[\\s\\S]*?\\])"),
        )
        val raw = patterns.firstNotNullOfOrNull { it.find(html)?.groupValues?.getOrNull(1) }?.trim()
            ?: return emptyList()
        if (!raw.startsWith("[")) return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.optJSONObject(i) ?: continue
                    val name = o.optString("name", "").trim().ifBlank { o.optString("title", "").trim() }
                    if (name.isNotBlank()) add(name)
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun extractVoiceNamesFromSourceBlock(html: String): List<String> {
        val patterns = listOf(
            Regex("(?is)\\bsource\\s*:\\s*\\{[\\s\\S]*?\\baudio\\s*:\\s*\\{[\\s\\S]*?\\bnames\\s*:\\s*(\\[[\\s\\S]*?\\])"),
            Regex("(?is)\\\"source\\\"\\s*:\\s*\\{[\\s\\S]*?\\\"audio\\\"\\s*:\\s*\\{[\\s\\S]*?\\\"names\\\"\\s*:\\s*(\\[[\\s\\S]*?\\])"),
        )

        val raw = patterns.firstNotNullOfOrNull { it.find(html)?.groupValues?.getOrNull(1) }?.trim()
            ?: return emptyList()
        if (!raw.startsWith("[")) return emptyList()

        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val v = arr.optString(i, "").trim()
                    if (v.isNotBlank()) add(v)
                }
            }
        }.getOrElse { parseJsStringArray(raw) }
    }

    private fun extractVoiceNamesFromInlineAudio(html: String): List<String> {
        val audioBody = Regex("(?is)\\baudio\\s*:\\s*\\{([\\s\\S]*?)\\}")
            .find(html)
            ?.groupValues
            ?.getOrNull(1)
            ?: return emptyList()

        val namesRaw = Regex("(?is)\\bnames\\s*:\\s*(\\[[\\s\\S]*?\\])")
            .find(audioBody)
            ?.groupValues
            ?.getOrNull(1)
            ?.trim()
            ?: return emptyList()

        return parseJsStringArray(namesRaw)
    }

    private fun extractVoiceNamesFromAudioNamesRegex(html: String): List<String> {
        val patterns = listOf(
            Regex("(?is)\\baudio\\s*:\\s*\\{[\\s\\S]*?\\bnames\\s*:\\s*(\\[[\\s\\S]*?\\])"),
            Regex("(?is)\\\"audio\\\"\\s*:\\s*\\{[\\s\\S]*?\\\"names\\\"\\s*:\\s*(\\[[\\s\\S]*?\\])"),
            Regex("(?is)\\baudio\\s*:\\s*\\\"\\{[\\s\\S]*?names\\\\?\"?\\s*:\\s*(\\[[\\s\\S]*?\\])"),
        )
        val raw = patterns.firstNotNullOfOrNull { it.find(html)?.groupValues?.getOrNull(1) }?.trim()
            ?: return emptyList()
        return parseJsStringArray(raw)
    }

    private fun extractVoiceNamesFromAudioSnippet(html: String): List<String> {
        val audioIdx = Regex("(?is)\\baudio\\s*:")
            .find(html)
            ?.range
            ?.first
            ?: return emptyList()

        val namesKeyMatch = Regex("(?is)\\bnames\\s*:")
            .find(html, startIndex = audioIdx)
            ?: return emptyList()

        val arrayStart = html.indexOf('[', startIndex = namesKeyMatch.range.last + 1)
        if (arrayStart < 0) return emptyList()
        val arrayEnd = findMatchingArrayEnd(html, arrayStart) ?: return emptyList()

        val raw = html.substring(arrayStart, arrayEnd + 1).trim()
        if (raw.isBlank()) return emptyList()

        val parsed = runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val value = arr.optString(i, "").trim()
                    if (value.isNotBlank()) add(value)
                }
            }
        }.getOrElse { parseJsStringArray(raw) }

        return parsed
    }

    private fun findMatchingArrayEnd(input: String, openBracketIndex: Int): Int? {
        var depth = 0
        var inString = false
        var quote = '\u0000'
        var escaped = false

        for (i in openBracketIndex until input.length) {
            val c = input[i]
            if (inString) {
                if (escaped) {
                    escaped = false
                    continue
                }
                if (c == '\\') {
                    escaped = true
                    continue
                }
                if (c == quote) {
                    inString = false
                }
                continue
            }

            if (c == '\'' || c == '"') {
                inString = true
                quote = c
                continue
            }

            if (c == '[') {
                depth++
            } else if (c == ']') {
                depth--
                if (depth == 0) return i
            }
        }

        return null
    }

    private fun extractMakePlayerSourceBlock(html: String): String? {
        val callRegex = Regex("(?is)makePlayer\\s*\\(")
        val callIndices = callRegex.findAll(html).map { it.range.first }.toList()
        if (callIndices.isEmpty()) return null

        for (callIdx in callIndices.asReversed()) {
            val optionsStart = html.indexOf('{', startIndex = callIdx)
            if (optionsStart < 0) continue
            val optionsEnd = findMatchingBraceEnd(html, optionsStart) ?: continue
            val optionsBlock = html.substring(optionsStart, optionsEnd + 1)

            val sourceKeyRegex = Regex("(?is)\\bsource\\s*:")
            val sourceKey = sourceKeyRegex.find(optionsBlock) ?: continue
            val sourceBraceStart = optionsBlock.indexOf('{', startIndex = sourceKey.range.last + 1)
            if (sourceBraceStart < 0) continue
            val sourceBraceEnd = findMatchingBraceEnd(optionsBlock, sourceBraceStart) ?: continue

            val sourceBlock = optionsBlock.substring(sourceBraceStart, sourceBraceEnd + 1)
            val score = listOf("audio", "names", "dash", "hls", "cc").count { sourceBlock.contains(it, ignoreCase = true) }
            if (score >= 3) {
                Log.d(TAG, "extractMakePlayerSourceBlock: success, sourceLen=${sourceBlock.length}, score=$score")
                return sourceBlock
            }
            Log.d(TAG, "extractMakePlayerSourceBlock: skip candidate, sourceLen=${sourceBlock.length}, score=$score")
        }

        Log.d(TAG, "extractMakePlayerSourceBlock: no source block found")
        return null
    }

    private fun findMatchingBraceEnd(input: String, openBraceIndex: Int): Int? {
        var depth = 0
        var inString = false
        var quote = '\u0000'
        var escaped = false

        for (i in openBraceIndex until input.length) {
            val c = input[i]
            if (inString) {
                if (escaped) {
                    escaped = false
                    continue
                }
                if (c == '\\') {
                    escaped = true
                    continue
                }
                if (c == quote) {
                    inString = false
                }
                continue
            }

            if (c == '\'' || c == '"') {
                inString = true
                quote = c
                continue
            }

            if (c == '{') {
                depth++
            } else if (c == '}') {
                depth--
                if (depth == 0) return i
            }
        }
        return null
    }

    private fun parseJsStringArray(raw: String): List<String> {
        return Regex("['\"]([^'\"]+)['\"]")
            .findAll(raw)
            .map { it.groupValues.getOrNull(1).orEmpty().trim() }
            .filter { it.isNotBlank() }
            .toList()
    }

    private fun extractSubtitlesArray(html: String): List<Map<String, String>> {
        val r = Regex("(?is)\\bcc\\s*:\\s*(\\[[^\\]]*\\])")
        val m = r.find(html) ?: return emptyList()
        val raw = m.groupValues.getOrNull(1).orEmpty().trim()
        if (!raw.startsWith("[")) return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val sObj = arr.optJSONObject(i) ?: continue
                    val url = (sObj.optString("url", "").ifBlank { sObj.optString("src", "") }).trim()
                    if (url.isBlank()) continue
                    val label = (sObj.optString("name", "").ifBlank { sObj.optString("label", "") }).trim().ifBlank { "Subtitle" }
                    val langRaw = sObj.optString("lang", "").trim()
                    val lang = when {
                        langRaw.isNotBlank() -> langRaw
                        label.contains("eng", ignoreCase = true) || label.contains("original", ignoreCase = true) -> "en"
                        else -> "ru"
                    }
                    add(mapOf("url" to url, "label" to label, "language" to lang))
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun parseSubtitlesString(jsonStr: String): List<Map<String, String>> {
        return runCatching {
            val arr = JSONArray(jsonStr)
            buildList {
                for (i in 0 until arr.length()) {
                    val obj = arr.optJSONObject(i) ?: continue
                    add(mapOf(
                        "url" to obj.optString("url", ""),
                        "label" to obj.optString("label", ""),
                        "language" to obj.optString("language", "")
                    ))
                }
            }
        }.getOrDefault(emptyList())
    }

    private fun parseSeries(seasonsJson: String): Map<String, Any> {
        val seasons = mutableListOf<Map<String, Any>>()

        try {
            val arr = JSONArray(seasonsJson)
            for (i in 0 until arr.length()) {
                val sObj = arr.getJSONObject(i)
                val seasonNum = sObj.optInt("season", -1)
                if (seasonNum <= 0) continue

                val epsArr = sObj.optJSONArray("episodes") ?: continue
                val episodes = mutableListOf<Map<String, Any>>()

                for (j in 0 until epsArr.length()) {
                    val eObj = epsArr.getJSONObject(j)
                    val epStr = eObj.optString("episode", "")
                    val epNum = epStr.toIntOrNull() ?: continue

                    val hls = eObj.optString("hls", "").takeIf { it.isNotBlank() }
                    val dasha = eObj.optString("dasha", "").takeIf { it.isNotBlank() }
                    val dash = eObj.optString("dash", "").takeIf { it.isNotBlank() }
                    val mpd = dasha ?: dash

                    val voices = extractSeriesEpisodeVoices(eObj)

                    val subtitles = mutableListOf<Map<String, String>>()
                    val cc = eObj.optJSONArray("cc")
                    if (cc != null) {
                        for (k in 0 until cc.length()) {
                            val sObj = cc.optJSONObject(k) ?: continue
                            val url = sObj.optString("url", "").ifBlank { sObj.optString("src", "") }
                            val label = sObj.optString("name", "").ifBlank { sObj.optString("label", "") }
                            val langRaw = sObj.optString("lang", "").trim()
                            val lang = when {
                                langRaw.isNotBlank() -> langRaw
                                label.contains("eng", ignoreCase = true) || label.contains("original", ignoreCase = true) -> "en"
                                else -> "ru"
                            }
                            if (url.isNotBlank()) {
                                subtitles.add(mapOf(
                                    "url" to url,
                                    "label" to label.ifBlank { "Subtitle" },
                                    "language" to lang
                                ))
                            }
                        }
                    }

                    val playlist = mutableMapOf<String, Any>(
                        "primaryUrl" to (hls ?: mpd ?: ""),
                        "voiceovers" to voices,
                        "subtitles" to subtitles
                    )
                    hls?.let { playlist["hlsUrl"] = it }
                    mpd?.let { playlist["dashUrl"] = it }
                    
                    episodes.add(mapOf(
                        "season" to seasonNum,
                        "episode" to epNum,
                        "title" to eObj.optString("title", "Episode $epNum"),
                        "playlist" to playlist
                    ))
                }

                if (episodes.isNotEmpty()) {
                    seasons.add(mapOf(
                        "season" to seasonNum,
                        "title" to sObj.optString("title", "Season $seasonNum"),
                        "episodes" to episodes
                    ))
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error parsing seasons JSON", e)
            return emptyMap()
        }

        return mapOf(
            "kind" to "series",
            "source" to "collaps",
            "seasons" to seasons
        )
    }

    private fun extractSeriesEpisodeVoices(eObj: JSONObject): List<String> {
        val out = linkedSetOf<String>()

        fun addAllFromArray(arr: JSONArray?) {
            if (arr == null) return
            for (i in 0 until arr.length()) {
                val v = arr.optString(i, "").trim()
                if (v.isNotBlank()) out.add(v)
            }
        }

        // 1) Standard shape: audio.names
        val audioObj = eObj.optJSONObject("audio")
        addAllFromArray(audioObj?.optJSONArray("names"))

        // 2) Some embeds keep audio as stringified JSON
        if (out.isEmpty()) {
            val audioRaw = eObj.optString("audio", "").trim()
            if (audioRaw.startsWith("{")) {
                runCatching {
                    val parsedAudio = JSONObject(audioRaw)
                    addAllFromArray(parsedAudio.optJSONArray("names"))
                }
            }
        }

        // 3) Fallback: scan episode JSON text for audio.names array with quoted/unquoted keys
        if (out.isEmpty()) {
            val episodeRaw = eObj.toString()
            val namesRaw = Regex("(?is)[\"']?audio[\"']?\\s*:\\s*\\{[\\s\\S]*?[\"']?names[\"']?\\s*:\\s*(\\[[\\s\\S]*?\\])")
                .find(episodeRaw)
                ?.groupValues
                ?.getOrNull(1)
                ?.trim()
            if (!namesRaw.isNullOrBlank()) {
                runCatching {
                    addAllFromArray(JSONArray(namesRaw))
                }.onFailure {
                    parseJsStringArray(namesRaw).forEach { out.add(it) }
                }
            }
        }

        return out.toList()
    }

    private fun parseMovie(movieData: Map<String, String>): Map<String, Any> {
        val mpd = movieData["dasha"] ?: movieData["dash"]
        val playlist = mutableMapOf<String, Any>(
            "primaryUrl" to (movieData["hls"] ?: mpd ?: ""),
            "voiceovers" to (movieData["voices"]?.let { it.split("|||") } ?: emptyList<String>()),
            "subtitles" to (movieData["subtitles"]?.let { parseSubtitlesString(it) } ?: emptyList<Map<String, String>>())
        )
        movieData["hls"]?.let { playlist["hlsUrl"] = it }
        mpd?.let { playlist["dashUrl"] = it }
        
        return mapOf(
            "kind" to "movie",
            "source" to "collaps",
            "playlist" to playlist
        )
    }
}
