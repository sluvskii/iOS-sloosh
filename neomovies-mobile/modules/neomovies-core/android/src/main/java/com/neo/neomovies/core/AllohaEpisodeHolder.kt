package com.neo.neomovies.core

/**
 * Static holder for Alloha episode data.
 * Stores episode iframe URLs and current state for in-player episode switching.
 */
object AllohaEpisodeHolder {
    /** Episode iframe URLs (to be resolved via AllohaRuntimeResolver) */
    @Volatile
    var episodeIframeUrls: List<String> = emptyList()
    
    /** Episode display names (e.g., "S01E01", "S01E02") */
    @Volatile
    var episodeNames: List<String> = emptyList()
    
    /** Current episode index */
    @Volatile
    var currentEpisodeIndex: Int = 0
    
    /** Headers for stream requests */
    @Volatile
    var headers: Map<String, String> = emptyMap()
    
    /** Base title (show name) */
    @Volatile
    var baseTitle: String = ""
    
    /** Current audio variants for the active episode */
    @Volatile
    var currentAudioVariants: List<Map<String, Any>> = emptyList()
    
    /** Current quality variants for the active episode */
    @Volatile
    var currentQualityVariants: List<Map<String, Any>> = emptyList()
    
    fun setEpisodes(
        iframeUrls: List<String>,
        names: List<String>,
        startIndex: Int,
        headers: Map<String, String>,
        title: String
    ) {
        episodeIframeUrls = iframeUrls
        episodeNames = names
        currentEpisodeIndex = startIndex.coerceIn(0, (iframeUrls.size - 1).coerceAtLeast(0))
        this.headers = headers
        baseTitle = title
    }
    
    fun hasPreviousEpisode(): Boolean = currentEpisodeIndex > 0
    
    fun hasNextEpisode(): Boolean = currentEpisodeIndex < episodeIframeUrls.size - 1
    
    fun previousEpisodeIframeUrl(): String? {
        if (!hasPreviousEpisode()) return null
        return episodeIframeUrls.getOrNull(currentEpisodeIndex - 1)
    }
    
    fun nextEpisodeIframeUrl(): String? {
        if (!hasNextEpisode()) return null
        return episodeIframeUrls.getOrNull(currentEpisodeIndex + 1)
    }
    
    fun currentEpisodeName(): String {
        return episodeNames.getOrNull(currentEpisodeIndex) ?: "Episode ${currentEpisodeIndex + 1}"
    }
    
    fun clear() {
        episodeIframeUrls = emptyList()
        episodeNames = emptyList()
        currentEpisodeIndex = 0
        headers = emptyMap()
        baseTitle = ""
        currentAudioVariants = emptyList()
        currentQualityVariants = emptyList()
    }
}
