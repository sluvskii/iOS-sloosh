package com.neo.neomovies.core

data class CollapsSubtitle(
    val url: String,
    val label: String,
    val language: String
)

data class CollapsEpisode(
    val season: Int,
    val episode: Int,
    val hlsUrl: String?,
    val mpdUrl: String?,
    val voices: List<String>,
    val subtitles: List<CollapsSubtitle>
)

data class CollapsSeason(
    val season: Int,
    val episodes: List<CollapsEpisode>
)

data class CollapsMovie(
    val hlsUrl: String?,
    val mpdUrl: String?,
    val voices: List<String>,
    val subtitles: List<CollapsSubtitle>
)
