package com.neo.neomovies.core

internal object PlayerMetadataResolver {
    private val seasonEpisodePatterns = listOf(
        "(?i)S(\\d{1,2})\\s*[._-]?\\s*E(\\d{1,3})",
        "(?i)\\b(\\d{1,2})\\s*[xX]\\s*(\\d{1,3})\\b",
        "(?i)season\\s*(\\d{1,2}).*episode\\s*(\\d{1,3})",
        "(?i)kp_\\d+_(\\d{1,2})_(\\d{1,3})"
    ).map { Regex(it) }

    private val audioIndexPatterns = listOf(
        "(?:^|[^a-z0-9])(?:rus|ru|eng|en|ukr|ua)(\\d+)(?:$|[^a-z0-9])",
        "(?:^|[^a-z0-9])a(?:udio)?[_-]?(\\d+)(?:$|[^a-z0-9])",
        "(?:^|[^a-z0-9])track[_-]?(\\d+)(?:$|[^a-z0-9])"
    ).map { Regex(it, RegexOption.IGNORE_CASE) }

    internal fun parseSeasonEpisode(rawName: String): String? {
        for (regex in seasonEpisodePatterns) {
            val match = regex.find(rawName) ?: continue
            val season = match.groupValues.getOrNull(1)?.toIntOrNull() ?: continue
            val episode = match.groupValues.getOrNull(2)?.toIntOrNull() ?: continue
            val useXFormat = regex.pattern.contains("\\s*[xX]\\s*")
            return if (useXFormat) "%dx%02d".format(season, episode) else "S%02dE%02d".format(season, episode)
        }
        return null
    }

    internal fun resolveAudioLabel(
        formatId: String?,
        fallbackLabel: String?,
        episodeVoiceNames: List<String>
    ): String {
        val raw = fallbackLabel?.trim().orEmpty()
        val index = extractAudioIndex(formatId) ?: extractAudioIndex(raw)
        val mapped = index?.let { episodeVoiceNames.getOrNull(it) }?.trim().orEmpty()
        if (mapped.isNotEmpty()) return mapped
        if (raw.isNotEmpty() && !raw.equals("audio", ignoreCase = true)) return raw
        val fromId = formatId
            ?.substringAfterLast('/')
            ?.substringAfterLast('_')
            ?.substringBefore('?')
            ?.trim()
            .orEmpty()
        return fromId.ifEmpty { "Audio" }
    }

    private fun extractAudioIndex(raw: String?): Int? {
        if (raw.isNullOrBlank()) return null
        for (regex in audioIndexPatterns) {
            val parsed = regex.find(raw)?.groupValues?.getOrNull(1)?.toIntOrNull()
            if (parsed != null) return parsed
        }
        return null
    }
}

