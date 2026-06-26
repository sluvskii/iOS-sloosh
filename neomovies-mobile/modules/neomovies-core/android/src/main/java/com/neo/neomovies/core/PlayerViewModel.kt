package com.neo.neomovies.core

import android.app.Application
import android.content.Context
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.SavedStateHandle
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.TrackGroup
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.database.DatabaseProvider
import androidx.media3.database.StandaloneDatabaseProvider
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.NoOpCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector
import androidx.media3.exoplayer.mediacodec.MediaCodecUtil
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.TsExtractor
import java.io.File
import java.net.URLDecoder
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.flow.update

class PlayerViewModel(
    application: Application,
    private val savedStateHandle: SavedStateHandle,
) : AndroidViewModel(application), Player.Listener {

    private data class LastInitArgs(
        val urls: List<String>,
        val names: List<String>?,
        val voiceNames: List<String>?,
        val title: String?,
        val kinopoiskId: Int?,
    )

    var player: Player
        private set

    private var useExo: Boolean = false
    var playbackSpeed: Float = 1f
    var isInPictureInPictureMode: Boolean = false
    var playWhenReady: Boolean = true
    private var baseTitle: String = ""

    private var kpId: Int? = null
    private var onEpisodeProgressUpdate: ((Int, Int, Int, Long, Long) -> Unit)? = null

    fun setKinopoiskId(id: Int) {
        kpId = id
    }
    private var pendingStartPositionMs: Long? = null
    private var pendingStartDurationMs: Long? = null
    private var pendingProgressKey: String? = null
    private var episodeVoiceNames: List<String> = emptyList()
    private var lastInitArgs: LastInitArgs? = null
    private var preferSoftwareDecoder: Boolean = false
    private val forceAv1SoftwareDecoder: Boolean = false

    private val useCollapsHeaders: Boolean by lazy {
        savedStateHandle.get<Boolean>(PlayerActivity.EXTRA_USE_COLLAPS_HEADERS) ?: false
    }

    private val forceFirstAudioTrack: Boolean by lazy { useCollapsHeaders }
    private var appliedFirstAudioOverride: Boolean = false
    private var preferredAudioLabel: String? = null
    private var preferredVideoHeight: Int? = null
    private var prefersAutoVideoQuality: Boolean = true
    
    // Alloha audio variants and quality variants support
    private var allohaAudioVariants: List<Map<String, Any>> = emptyList()
    private var allohaQualityVariants: List<Map<String, Any>> = emptyList()
    private var selectedAllohaAudioIndex: Int = 0
    private var selectedAllohaQualityIndex: Int = -1 // -1 means Auto
    private var currentEpisodeIndex: Int = 0
    private var totalEpisodes: Int = 0
    
    private val collapsHeaders: Map<String, String> by lazy {
        val prefixed = runCatching {
            savedStateHandle.keys()
                .filter { it.startsWith("HEADER_") }
                .associateWith { key -> savedStateHandle.get<String>(key).orEmpty() }
                .mapKeys { (key, _) -> key.removePrefix("HEADER_") }
                .filterValues { it.isNotBlank() }
        }.getOrDefault(emptyMap())

        if (prefixed.isNotEmpty()) {
            prefixed
        } else {
            mapOf(
                "Referer" to "https://kinokrad.my/",
                "Origin" to "https://kinokrad.my",
            )
        }
    }

    private var resolvedExtraHeaders: Map<String, String> = emptyMap()

    private val _uiState = MutableStateFlow(UiState(currentItemTitle = "", fileLoaded = false))
    val uiState = _uiState.asStateFlow()

    private val _tracksVersion = MutableStateFlow(0)
    val tracksVersion = _tracksVersion.asStateFlow()

    private val _playerEpoch = MutableStateFlow(0)
    val playerEpoch = _playerEpoch.asStateFlow()

    private val eventsChannel = Channel<PlayerEvents>(capacity = Channel.BUFFERED)
    val eventsChannelFlow = eventsChannel.receiveAsFlow()

    data class UiState(
        val currentItemTitle: String,
        val fileLoaded: Boolean,
    )

    private val progressStore by lazy { PlayerProgressStore(application.applicationContext) }

    // Shared AudioAttributes to avoid duplication
    private val audioAttributes = AudioAttributes.Builder()
        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
        .setUsage(C.USAGE_MEDIA)
        .build()

    init {
        useExo = savedStateHandle.get<Boolean>(PlayerActivity.EXTRA_USE_EXO) ?: true

        Log.d("PlayerVM", "init useExo=$useExo")
        player = createPlayer(useExo, preferSoftwareDecoder)
        player.addListener(this)
    }

    fun setEngine(useExo: Boolean) {
        if (this.useExo == useExo) return
        this.useExo = useExo

        player.removeListener(this)
        player.release()

        player = createPlayer(useExo, preferSoftwareDecoder)
        player.addListener(this)
        _playerEpoch.update { it + 1 }
        
        // Note: You might need to re-initialize the playlist here 
        // if engine is switched during playback.
    }

    private fun createPlayer(useExo: Boolean, preferSoftwareDecoder: Boolean): Player {
        val trackSelector = DefaultTrackSelector(getApplication()).apply {
            parameters = buildUponParameters()
                .setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
                .build()
        }

        val extractorsFactory = DefaultExtractorsFactory()
            .setTsExtractorFlags(DefaultTsPayloadReaderFactory.FLAG_ENABLE_HDMV_DTS_AUDIO_STREAMS)
            .setTsExtractorTimestampSearchBytes(1500 * TsExtractor.TS_PACKET_SIZE)

        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
        if (useCollapsHeaders) {
            httpDataSourceFactory.setUserAgent("Mozilla/5.0 (Windows NT 10.0; Win64; x64)")
            val requestHeaders = mapOf(
                "Referer" to "https://kinokrad.my/",
                "Origin" to "https://kinokrad.my",
            ) + collapsHeaders
            Log.d("PlayerVM", "Using Collaps headers: $requestHeaders")
            httpDataSourceFactory.setDefaultRequestProperties(requestHeaders)
        }

        val upstreamFactory = LoggingDataSourceFactory(
            delegate = DefaultDataSource.Factory(getApplication(), httpDataSourceFactory),
            headers = if (useCollapsHeaders) {
                mapOf(
                    "Referer" to "https://kinokrad.my/",
                    "Origin" to "https://kinokrad.my",
                    "User-Agent" to "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
                ) + collapsHeaders
            } else {
                emptyMap()
            }
        )
        val dataSourceFactory = CacheDataSource.Factory()
            .setCache(PlayerCacheStore.getDownloadCache(getApplication()))
            .setUpstreamDataSourceFactory(upstreamFactory)
            .setCacheWriteDataSinkFactory(null)
        val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory, extractorsFactory)

        val extensionMode = if (isEmulator()) {
            DefaultRenderersFactory.EXTENSION_RENDERER_MODE_OFF
        } else if (preferSoftwareDecoder) {
            DefaultRenderersFactory.EXTENSION_RENDERER_MODE_PREFER
        } else {
            DefaultRenderersFactory.EXTENSION_RENDERER_MODE_ON
        }

        val av1PreferringSelector = MediaCodecSelector { mimeType, requiresSecureDecoder, requiresTunnelingDecoder ->
            if ((preferSoftwareDecoder || forceAv1SoftwareDecoder) && mimeType.equals(MimeTypes.VIDEO_AV1, ignoreCase = true)) {
                Log.w("PlayerVM", "MediaCodecSelector: blocking MediaCodec for AV1 mime=$mimeType")
                emptyList()
            } else {
                MediaCodecUtil.getDecoderInfos(mimeType, requiresSecureDecoder, requiresTunnelingDecoder)
            }
        }

        val renderersFactory = DefaultRenderersFactory(getApplication())
            .setExtensionRendererMode(extensionMode)
            .setEnableDecoderFallback(true)
            .setMediaCodecSelector(av1PreferringSelector)

        return ExoPlayer.Builder(getApplication(), renderersFactory)
            .setTrackSelector(trackSelector)
            .setMediaSourceFactory(mediaSourceFactory)
            .build().apply {
                setAudioAttributes(this@PlayerViewModel.audioAttributes, true)
                setPauseAtEndOfMediaItems(false)
                addAnalyticsListener(createAnalyticsListener())
            }
    }

    private fun isEmulator(): Boolean {
        return Build.FINGERPRINT.contains("generic") ||
                Build.MODEL.contains("emulator") ||
                Build.MODEL.contains("sdk_gphone") ||
                Build.MANUFACTURER.contains("genymotion")
    }

    private fun createAnalyticsListener() = object : AnalyticsListener {
        override fun onVideoDecoderInitialized(eventTime: AnalyticsListener.EventTime, decoderName: String, initializedTimestampMs: Long, initializationDurationMs: Long) {
            Log.d("PlayerVM", "VideoDecoder: $decoderName")
        }
        override fun onPlayerError(eventTime: AnalyticsListener.EventTime, error: PlaybackException) {
            Log.e("PlayerVM", "Error: ${error.errorCodeName}", error)
        }
    }

    fun initializePlayer(
        urls: List<String>,
        names: List<String>?,
        voiceNames: List<String>? = null,
        startIndex: Int,
        title: String?,
        startFromBeginning: Boolean,
        kinopoiskId: Int? = null,
        episodeProgressCallback: ((Int, Int, Int, Long, Long) -> Unit)? = null,
        extraHeaders: Map<String, String> = emptyMap(),
    ) {
        Log.d("PlayerVM", "initializePlayer: urls=$urls, startIndex=$startIndex, title=$title")
        
        baseTitle = title?.takeIf { it.isNotBlank() } ?: ""
        episodeVoiceNames = voiceNames.orEmpty()
        kpId = kinopoiskId
        lastInitArgs = LastInitArgs(
            urls = urls,
            names = names,
            voiceNames = voiceNames,
            title = title,
            kinopoiskId = kinopoiskId,
        )
        onEpisodeProgressUpdate = episodeProgressCallback
        val initialTitle = if (AllohaEpisodeHolder.episodeIframeUrls.isNotEmpty() && baseTitle.isNotBlank()) {
            val epName = AllohaEpisodeHolder.currentEpisodeName()
            if (epName.isNotBlank()) "$baseTitle • $epName" else baseTitle
        } else baseTitle
        _uiState.update { it.copy(currentItemTitle = initialTitle, fileLoaded = false) }
        appliedFirstAudioOverride = false

        val resolvedUrls = urls

        val mediaItems = PlayerMediaItemFactory.create(resolvedUrls, names, baseTitle)

        val currentUrl = resolvedUrls.getOrNull(startIndex) ?: resolvedUrls.firstOrNull().orEmpty()
        val initialItem = mediaItems.getOrNull(startIndex)
        if (initialItem != null) {
            _uiState.update { it.copy(currentItemTitle = buildDisplayTitle(initialItem)) }
        }

        // Try to get episode name from names array or AllohaEpisodeHolder
        val initialDisplayName = names?.getOrNull(startIndex)
            ?: AllohaEpisodeHolder.currentEpisodeName().takeIf { AllohaEpisodeHolder.episodeIframeUrls.isNotEmpty() }
            ?: ""
        
        // Parse season/episode from display name (format: S01E01 or similar)
        val parsedSeasonEpisode = parseSeasonEpisodeNumbers(initialDisplayName)
        
        val progressKey = if (kinopoiskId != null && parsedSeasonEpisode != null) {
            // Use same format as PlayerProgressStore.buildProgressKey: kp_{id}_s{season}_e{episode}
            "kp_${kinopoiskId}_s${parsedSeasonEpisode.first}_e${parsedSeasonEpisode.second}"
        } else if (AllohaEpisodeHolder.episodeIframeUrls.isNotEmpty() && kinopoiskId != null) {
            // Fallback for Alloha: parse from AllohaEpisodeHolder episode name
            val episodeName = AllohaEpisodeHolder.currentEpisodeName()
            val parsed = parseSeasonEpisodeNumbers(episodeName)
            if (parsed != null) {
                "kp_${kinopoiskId}_s${parsed.first}_e${parsed.second}"
            } else {
                "kp_${kinopoiskId}_e${AllohaEpisodeHolder.currentEpisodeIndex}"
            }
        } else {
            "pos_$currentUrl"
        }
        Log.d("PlayerVM", "Progress key: $progressKey (displayName=$initialDisplayName)")
        val startPosition = progressStore.readStartPosition(progressKey, startFromBeginning)
        val savedDuration = progressStore.readSavedDuration(progressKey)
        pendingStartPositionMs = if (startPosition > 0L) startPosition else null
        pendingStartDurationMs = if (savedDuration > 0L) savedDuration else null
        pendingProgressKey = progressKey
        Log.d("PlayerVM", "Restored progress: key=$progressKey position=$startPosition savedDuration=$savedDuration")

        Log.d("PlayerVM", "Setting media items: count=${mediaItems.size}, startIndex=$startIndex, startPosition=$startPosition")
        player.setMediaItems(mediaItems, startIndex, startPosition)
        player.prepare()
        player.playWhenReady = true
        Log.d("PlayerVM", "Player prepared and playWhenReady set to true")
    }


    override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
        _uiState.update { it.copy(currentItemTitle = buildDisplayTitle(mediaItem)) }
        appliedFirstAudioOverride = false
        currentEpisodeIndex = player.currentMediaItemIndex
    }

    override fun onTracksChanged(tracks: Tracks) {
        _tracksVersion.update { it + 1 }
        if (!useExo) return

        PlayerTrackSelectorDelegate.logVideoTracks(tracks)

        val appliedPreferredAudio = applyPreferredAudioTrackIfAny()
        val appliedPreferredVideo = applyPreferredVideoQualityIfAny()
        if (appliedPreferredAudio || appliedPreferredVideo) {
            return
        }

        if (!forceFirstAudioTrack || appliedFirstAudioOverride || preferredAudioLabel != null) return

        val audioGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_AUDIO }
        val group = audioGroups.firstOrNull() ?: return
        val trackGroup = group.mediaTrackGroup
        if (trackGroup.length > 0) {
            player.trackSelectionParameters = player.trackSelectionParameters
                .buildUpon()
                .clearOverridesOfType(C.TRACK_TYPE_AUDIO)
                .setOverrideForType(TrackSelectionOverride(trackGroup, listOf(0)))
                .setTrackTypeDisabled(C.TRACK_TYPE_AUDIO, false)
                .build()
            appliedFirstAudioOverride = true
        }
    }

    private fun applyPreferredAudioTrackIfAny(): Boolean {
        val preferredLabel = preferredAudioLabel?.trim()?.takeIf { it.isNotEmpty() } ?: return false
        val audioTracks = getSelectableTracks(C.TRACK_TYPE_AUDIO)
        if (audioTracks.isEmpty()) return false

        val targetIndex = audioTracks.indexOfFirst { track ->
            track.isSupported && track.label.equals(preferredLabel, ignoreCase = true)
        }
        if (targetIndex < 0) return false

        switchToTrack(C.TRACK_TYPE_AUDIO, targetIndex)
        return true
    }

    private fun applyPreferredVideoQualityIfAny(): Boolean {
        if (prefersAutoVideoQuality) return false

        val preferredHeight = preferredVideoHeight ?: return false
        val videoTracks = getSelectableTracks(C.TRACK_TYPE_VIDEO)
        if (videoTracks.isEmpty()) return false

        val targetIndex = videoTracks.indexOfFirst { track ->
            track.isSupported && track.height == preferredHeight
        }
        if (targetIndex < 0) return false

        switchToTrack(C.TRACK_TYPE_VIDEO, targetIndex)
        return true
    }

    private fun buildDisplayTitle(mediaItem: MediaItem?): String {
        val displayName = mediaItem?.mediaMetadata?.extras?.getString("display_name").orEmpty()
        val rawName = displayName.ifBlank {
            val url = mediaItem?.localConfiguration?.uri?.toString().orEmpty()
            url.substringAfterLast('/').substringAfterLast('\\')
        }
        val fileName = runCatching { URLDecoder.decode(rawName, "UTF-8") }.getOrDefault(rawName)
        val se = parseSeasonEpisode(fileName)

        return when {
            se != null && baseTitle.isNotBlank() -> "$baseTitle • $se"
            baseTitle.isNotBlank() -> baseTitle
            else -> fileName
        }
    }

    private fun parseSeasonEpisode(name: String): String? = PlayerMetadataResolver.parseSeasonEpisode(name)
    
    private fun parseSeasonEpisodeNumbers(name: String): Pair<Int, Int>? {
        val match = Regex("[Ss](\\d{1,2})[Ee](\\d{1,3})").find(name) ?: return null
        val season = match.groupValues[1].toIntOrNull() ?: return null
        val episode = match.groupValues[2].toIntOrNull() ?: return null
        return Pair(season, episode)
    }

    private fun progressKey(): String {
        val mediaItem = player.currentMediaItem
        val mediaId = mediaItem?.mediaId ?: return ""
        val allohaEpisodeName = if (AllohaEpisodeHolder.episodeIframeUrls.isNotEmpty())
            AllohaEpisodeHolder.currentEpisodeName() else null
        return progressStore.buildProgressKey(
            mediaId = mediaId,
            displayName = allohaEpisodeName ?: mediaItem.mediaMetadata.extras?.getString("display_name").orEmpty(),
            displayTitle = allohaEpisodeName ?: buildDisplayTitle(mediaItem),
            kpId = kpId
        )
    }

    fun clearCurrentProgress() {
        val key = progressKey().takeIf { it.isNotBlank() } ?: return
        progressStore.clearPosition(key)
    }

    fun clearEpisodeProgress(episodeIndex: Int) {
        val id = kpId ?: return
        progressStore.clearAllohaEpisodeProgress(id, episodeIndex)
    }

    fun updatePlaybackProgress() {
        val key = progressKey().takeIf { it.isNotBlank() } ?: return
        val position = player.currentPosition
        progressStore.savePosition(key, position, player.duration.takeIf { it > 0L })
        savedStateHandle["position"] = position

        // For Alloha, use episode name from holder for season/episode tracking
        val allohaEpisodeName = if (AllohaEpisodeHolder.episodeIframeUrls.isNotEmpty())
            AllohaEpisodeHolder.currentEpisodeName() else null

        val displayName = allohaEpisodeName
            ?: player.currentMediaItem?.mediaMetadata?.extras?.getString("display_name").orEmpty()
        val displayTitle = allohaEpisodeName
            ?: buildDisplayTitle(player.currentMediaItem)
        val se = parseSeasonEpisode(displayName)
            ?: parseSeasonEpisode(displayTitle)
        val currentKpId = kpId
        val duration = player.duration
        if (se != null && baseTitle.isNotBlank()) {
            // Extract season and episode from SxxEyy format
            val match = Regex("S(\\d{1,2})E(\\d{1,3})").find(se)
            if (match != null) {
                val season = match.groupValues[1].toIntOrNull()
                val episode = match.groupValues[2].toIntOrNull()
                if (currentKpId != null && season != null && episode != null) {
                    val cb = onEpisodeProgressUpdate
                    if (cb != null) {
                        cb(currentKpId, season, episode, position, duration)
                        return
                    }
                    progressStore.persistEpisodeProgress(currentKpId, season, episode, position, duration)
                    return
                }
            }
        }

        val cb = onEpisodeProgressUpdate
        if (currentKpId != null && cb != null) {
            cb(currentKpId, 0, 0, position, duration)
            return
        }

        // Persist generic (movie/non-episodic) progress by Kinopoisk ID so DetailsScreen can show resume.
        if (currentKpId != null) {
            progressStore.persistGenericKpProgress(currentKpId, position, duration)
        }
    }

    fun getSelectableTracks(trackType: @C.TrackType Int): List<SelectableTrack> {
        return PlayerTrackSelectorDelegate.getSelectableTracks(player, trackType, episodeVoiceNames)
    }

    fun switchToTrack(trackType: @C.TrackType Int, index: Int) {
        when (trackType) {
            C.TRACK_TYPE_AUDIO -> {
                if (index >= 0) {
                    val selected = getSelectableTracks(C.TRACK_TYPE_AUDIO).getOrNull(index)
                    preferredAudioLabel = selected?.label
                }
            }
            C.TRACK_TYPE_VIDEO -> {
                if (index == -1) {
                    prefersAutoVideoQuality = true
                    preferredVideoHeight = null
                } else {
                    val selected = getSelectableTracks(C.TRACK_TYPE_VIDEO).getOrNull(index)
                    prefersAutoVideoQuality = false
                    preferredVideoHeight = selected?.height?.takeIf { it > 0 }
                }
            }
        }

        if (index == -1) {
            PlayerTrackSelectorDelegate.switchToTrack(player, trackType, null)
        } else {
            val track = getSelectableTracks(trackType).getOrNull(index) ?: return
            PlayerTrackSelectorDelegate.switchToTrack(player, trackType, track)
        }
    }

    fun isVideoQualityAutoPreferred(): Boolean = prefersAutoVideoQuality

    /** Reset audio track override so the next onTracksChanged selects first audio (Russian). */
    fun resetAudioOverride() {
        appliedFirstAudioOverride = false
    }

    fun selectSpeed(speed: Float) {
        player.setPlaybackSpeed(speed)
        playbackSpeed = speed
    }

    override fun onPlaybackStateChanged(state: Int) {
        if (state == Player.STATE_READY) {
            reconcilePendingStartPosition()
            _uiState.update { it.copy(fileLoaded = true) }
        }
        if (state == Player.STATE_ENDED) {
            updatePlaybackProgress()
            val key = progressKey().takeIf { it.isNotBlank() }
            if (key != null) {
                progressStore.markAsWatched(key)
            }

            // In Alloha episode mode, episode navigation is handled by PlayerActivity
            if (AllohaEpisodeHolder.episodeIframeUrls.isNotEmpty()) return

            val currentIndex = player.currentMediaItemIndex
            val hasNextItem = currentIndex + 1 < player.mediaItemCount
            if (hasNextItem) {
                player.seekToNextMediaItem()
                player.playWhenReady = true
            } else {
                eventsChannel.trySend(PlayerEvents.NavigateBack)
            }
        }
    }

    override fun onPlayerError(error: PlaybackException) {
        Log.e("PlayerVM", "Player error: ${error.errorCodeName}", error)
        if (PlayerPlaybackRecovery.shouldFallbackToSoftwareDecoder(error, preferSoftwareDecoder, useExo)) {
            fallbackToSoftwareDecoder()
        }
    }

    private fun fallbackToSoftwareDecoder() {
        val args = lastInitArgs ?: return
        preferSoftwareDecoder = true

        val currentIndex = player.currentMediaItemIndex.coerceAtLeast(0)
        val currentPosition = player.currentPosition.coerceAtLeast(0L)
        val shouldPlay = player.playWhenReady

        Log.w(
            "PlayerVM",
            "Falling back to software decoder: index=$currentIndex position=$currentPosition"
        )

        player.removeListener(this)
        player.release()

        player = createPlayer(useExo, preferSoftwareDecoder)
        player.addListener(this)
        _playerEpoch.update { it + 1 }

        baseTitle = args.title?.takeIf { it.isNotBlank() } ?: ""
        kpId = args.kinopoiskId
        episodeVoiceNames = args.voiceNames.orEmpty()
        _uiState.update { it.copy(fileLoaded = false) }

        val mediaItems = PlayerMediaItemFactory.create(args.urls, args.names, baseTitle)

        val safeIndex = currentIndex.coerceIn(0, (mediaItems.size - 1).coerceAtLeast(0))
        player.setMediaItems(mediaItems, safeIndex, currentPosition)
        player.prepare()
        player.playWhenReady = shouldPlay
    }

    override fun onIsPlayingChanged(isPlaying: Boolean) {
        eventsChannel.trySend(PlayerEvents.IsPlayingChanged(isPlaying))
    }

    override fun onCleared() {
        super.onCleared()
        player.removeListener(this)
        player.release()
    }

    private fun reconcilePendingStartPosition() {
        val restoredPosition = pendingStartPositionMs ?: return
        pendingStartPositionMs = null
        val savedDuration = pendingStartDurationMs
        pendingStartDurationMs = null

        val duration = player.duration
        if (duration <= 0L) return

        val progressKey = pendingProgressKey
        pendingProgressKey = null

        val resetTo = progressStore.resetIfNearEnd(progressKey, restoredPosition, duration)
        if (resetTo != null) {
            Log.d(
                "PlayerVM",
                "Resetting restored progress near the end: restored=$restoredPosition duration=$duration key=$progressKey"
            )
            player.seekTo(resetTo)
            return
        }

        if (savedDuration != null && savedDuration > 0L && restoredPosition > 0L) {
            val normalizedProgress = (restoredPosition.toDouble() / savedDuration.toDouble()).coerceIn(0.0, 0.999)
            val normalizedTarget = (duration.toDouble() * normalizedProgress).toLong().coerceIn(0L, duration)
            if (kotlin.math.abs(normalizedTarget - restoredPosition) > 2_000L) {
                Log.d(
                    "PlayerVM",
                    "Normalizing restored progress across duration change: restored=$restoredPosition savedDuration=$savedDuration actualDuration=$duration target=$normalizedTarget key=$progressKey"
                )
                player.seekTo(normalizedTarget)
            }
        }
    }

    // Alloha audio variants support
    fun setAllohaVariants(
        audioVariants: List<Map<String, Any>>,
        qualityVariants: List<Map<String, Any>>
    ) {
        // Try to preserve selected audio by title across episode switches
        val prevAudioTitle = allohaAudioVariants.getOrNull(selectedAllohaAudioIndex)?.get("title") as? String
        val prevQualityLabel = if (selectedAllohaQualityIndex >= 0) {
            val prevAudio = allohaAudioVariants.getOrNull(selectedAllohaAudioIndex)
            val prevQv = (prevAudio?.get("qualityVariants") as? List<*>)?.mapNotNull { it as? Map<*, *> }
                ?.takeIf { it.isNotEmpty() } ?: allohaQualityVariants.mapNotNull { it as? Map<*, *> }
            prevQv.getOrNull(selectedAllohaQualityIndex)?.get("label") as? String
        } else null

        allohaAudioVariants = audioVariants
        allohaQualityVariants = qualityVariants

        // Restore audio selection by title
        val restoredAudioIndex = if (prevAudioTitle != null) {
            audioVariants.indexOfFirst { (it["title"] as? String) == prevAudioTitle }.takeIf { it >= 0 }
        } else null
        selectedAllohaAudioIndex = restoredAudioIndex ?: 0

        // Restore quality selection by label
        if (prevQualityLabel != null) {
            val newAudio = audioVariants.getOrNull(selectedAllohaAudioIndex)
            val newQv = (newAudio?.get("qualityVariants") as? List<*>)?.mapNotNull { it as? Map<*, *> }
                ?.takeIf { it.isNotEmpty() } ?: qualityVariants.mapNotNull { it as? Map<*, *> }
            val restoredQualityIndex = newQv.indexOfFirst { (it["label"] as? String) == prevQualityLabel }.takeIf { it >= 0 }
            if (restoredQualityIndex != null) {
                selectedAllohaQualityIndex = restoredQualityIndex
                isAutoQuality = false
            } else {
                selectedAllohaQualityIndex = -1
                isAutoQuality = true
            }
        } else {
            selectedAllohaQualityIndex = -1
            isAutoQuality = true
        }
    }

    fun getAllohaAudioVariants(): List<Map<String, String>> {
        return allohaAudioVariants.mapIndexed { index, variant ->
            mapOf(
                "index" to index.toString(),
                "title" to (variant["title"] as? String ?: "Unknown"),
                "selected" to (index == selectedAllohaAudioIndex).toString()
            )
        }
    }

    fun getAllohaQualityVariants(): List<Map<String, String>> {
        val variants = if (selectedAllohaAudioIndex in allohaAudioVariants.indices) {
            val audioVariant = allohaAudioVariants[selectedAllohaAudioIndex]
            (audioVariant["qualityVariants"] as? List<*>)?.mapNotNull { it as? Map<*, *> }
                ?: allohaQualityVariants.mapNotNull { it as? Map<*, *> }
        } else {
            allohaQualityVariants.mapNotNull { it as? Map<*, *> }
        }
        
        // Build filtered and sorted list (high to low resolution)
        val filteredVariants = mutableListOf<Triple<Int, Int, Map<*, *>>>() // Triple(originalIndex, height, variant)

        variants.forEachIndexed { index, variant ->
            val height = getQualityHeight(variant)

            // Filter out anything above 1080p
            if (height > 1080) {
                Log.d("PlayerVM", "Filtering out ${height}p - max allowed: 1080p")
                return@forEachIndexed
            }

            filteredVariants.add(Triple(index, height, variant))
        }
        
        // Sort by height descending (high to low)
        filteredVariants.sortByDescending { it.second }
        
        val result = mutableListOf(
            mapOf(
                "index" to "-1",
                "label" to "Auto",
                "selected" to (selectedAllohaQualityIndex == -1).toString()
            )
        )
        
        filteredVariants.forEach { (originalIndex, height, variant) ->
            val label = (variant["label"] as? String ?: "${height}p")
            result.add(mapOf(
                "index" to originalIndex.toString(),
                "label" to label,
                "height" to height.toString(),
                "selected" to (originalIndex == selectedAllohaQualityIndex).toString()
            ))
        }
        
        return result
    }
    
    private fun getQualityHeight(variant: Map<*, *>): Int {
        // Try to get height from various possible keys and types
        var height: Int? = null
        
        // Try "height" key
        val heightVal = variant["height"]
        height = when (heightVal) {
            is Number -> heightVal.toInt()
            is String -> heightVal.toIntOrNull()
            else -> null
        }
        
        // Fallback to parsing from label
        if (height == null || height == 0) {
            val label = (variant["label"] as? String) ?: ""
            val match = Regex("(\\d+)p?", RegexOption.IGNORE_CASE).find(label)
            height = match?.groupValues?.get(1)?.toIntOrNull()
        }
        
        Log.d("PlayerVM", "getQualityHeight: variant=$variant -> height=$height")
        return height ?: 0
    }
    
    private var isAutoQuality = true

    fun isAllohaAutoQuality(): Boolean = isAutoQuality

    fun getBestAllohaUrl(): String? {
        val audioVariant = allohaAudioVariants.getOrNull(selectedAllohaAudioIndex) ?: return null
        val qualityVariants = ((audioVariant["qualityVariants"] as? List<*>)?.mapNotNull { it as? Map<*, *> }
            ?.takeIf { it.isNotEmpty() }
            ?: allohaQualityVariants.mapNotNull { it as? Map<*, *> })
        if (qualityVariants.isEmpty()) return audioVariant["url"] as? String
        return if (isAutoQuality || selectedAllohaQualityIndex < 0) {
            selectBestQualityUrl(qualityVariants)
        } else {
            val variant = qualityVariants.getOrNull(selectedAllohaQualityIndex)
            val height = variant?.let { getQualityHeight(it) } ?: 0
            if (height > 1080) selectBestQualityUrl(qualityVariants)
            else variant?.get("url") as? String ?: selectBestQualityUrl(qualityVariants)
        }
    }
    
    fun selectAllohaAutoQuality() {
        isAutoQuality = true
        selectedAllohaQualityIndex = -1
        // Reload with auto-selected quality
        reloadAllohaVariant()
    }

    fun selectAllohaAudioVariant(index: Int) {
        if (index !in allohaAudioVariants.indices) return
        selectedAllohaAudioIndex = index
        selectedAllohaQualityIndex = -1
        isAutoQuality = true
        reloadAllohaVariant()
    }

    fun selectAllohaQualityVariant(index: Int) {
        isAutoQuality = false
        selectedAllohaQualityIndex = index
        reloadAllohaVariant()
    }
    
    private fun reloadAllohaVariant() {
        val audioVariant = allohaAudioVariants.getOrNull(selectedAllohaAudioIndex) ?: return
        val qualityVariants = ((audioVariant["qualityVariants"] as? List<*>)?.mapNotNull { it as? Map<*, *> }
            ?.takeIf { it.isNotEmpty() }
            ?: allohaQualityVariants.mapNotNull { it as? Map<*, *> })
            .takeIf { it.isNotEmpty() } ?: run {
            // No quality variants — just reload with the audio variant's direct URL
            val directUrl = audioVariant["url"] as? String ?: return
            val currentPosition = player.currentPosition
            player.stop()
            player.clearMediaItems()
            player.setMediaItem(androidx.media3.common.MediaItem.Builder().setUri(directUrl).build())
            player.prepare()
            player.seekTo(currentPosition)
            player.play()
            return
        }

        val url = if (isAutoQuality || selectedAllohaQualityIndex < 0) {
            selectBestQualityUrl(qualityVariants)
        } else {
            val variant = qualityVariants.getOrNull(selectedAllohaQualityIndex)
            val height = variant?.let { getQualityHeight(it) } ?: 0
            if (height > 1080) selectBestQualityUrl(qualityVariants)
            else variant?.get("url") as? String
        } ?: return
        
        // Reload player with new URL
        val currentPosition = player.currentPosition
        player.stop()
        player.clearMediaItems()
        
        val mediaItem = androidx.media3.common.MediaItem.Builder()
            .setUri(url)
            .build()
        
        player.setMediaItem(mediaItem)
        player.prepare()
        player.seekTo(currentPosition)
        player.play()
    }
    
    private fun selectBestQualityUrl(variants: List<Map<*, *>>): String? {
        val context = getApplication<android.app.Application>()
        
        try {
            val cm = context.getSystemService(android.content.Context.CONNECTIVITY_SERVICE) as? android.net.ConnectivityManager
            val caps = cm?.getNetworkCapabilities(cm.activeNetwork)
            val isWifi = caps?.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI) == true
            val downMbps = caps?.linkDownstreamBandwidthKbps?.div(1000) ?: 0
            
            val maxRes = when {
                downMbps >= 10 -> 1080
                downMbps >= 5 -> 720
                downMbps >= 2 -> 480
                else -> 360
            }

            Log.d("PlayerVM", "Auto quality: isWifi=$isWifi, downMbps=$downMbps, maxRes=${maxRes}p")
            
            // Build quality map - include all qualities up to 1080p for auto selection
            val qualityMap = mutableMapOf<Int, String>()
            variants.forEach { variant ->
                val height = getQualityHeight(variant)
                val url = variant["url"] as? String
                if (height > 0 && !url.isNullOrBlank() && height <= 1080) {
                    qualityMap[height] = url
                }
            }
            
            // Select best quality within maxRes limit
            val orderedKeys = listOf(1080, 720, 480, 360, 240).filter { it <= maxRes }
            val bestKey = orderedKeys.firstOrNull { qualityMap.containsKey(it) }
                ?: qualityMap.keys.filter { it <= maxRes }.maxOrNull()
                ?: qualityMap.keys.minOrNull()
            
            return qualityMap[bestKey] ?: variants.firstOrNull()?.get("url") as? String
        } catch (e: Exception) {
            Log.e("PlayerVM", "Error selecting quality", e)
            return variants.firstOrNull()?.get("url") as? String
        }
    }

    /**
     * Returns saved progress position for a given episode, 0 if none or already watched.
     */
    fun readSavedEpisodePositionMs(kpId: Int, season: Int, episode: Int): Long {
        val key = "kp_${kpId}_s${season}_e${episode}"
        return progressStore.readStartPosition(key, startFromBeginning = false)
    }

    // Episode navigation
    fun setEpisodeInfo(currentIndex: Int, total: Int) {
        currentEpisodeIndex = currentIndex
        totalEpisodes = total
    }

    fun canGoPreviousEpisode(): Boolean = currentEpisodeIndex > 0

    fun canGoNextEpisode(): Boolean = currentEpisodeIndex + 1 < totalEpisodes

    fun previousEpisode() {
        if (canGoPreviousEpisode()) {
            player.seekToPrevious()
        }
    }

    fun nextEpisode() {
        if (canGoNextEpisode()) {
            player.seekToNext()
        }
    }
    
    /**
     * Reload the player with a new URL (used for Alloha episode switching)
     */
    fun reloadWithUrl(url: String, headers: Map<String, String> = emptyMap(), startPositionMs: Long = 0L) {
        player.stop()
        player.clearMediaItems()

        val mediaItem = MediaItem.Builder()
            .setUri(url)
            .build()

        player.setMediaItem(mediaItem)
        player.prepare()
        if (startPositionMs > 0L) {
            player.seekTo(startPositionMs)
        }
        player.play()

        // Reset audio override for new episode
        appliedFirstAudioOverride = false
    }
}

private object PlayerCacheStore {
    @Volatile private var downloadCache: SimpleCache? = null
    @Volatile private var databaseProvider: DatabaseProvider? = null

    fun getDatabaseProvider(context: Context): DatabaseProvider {
        val current = databaseProvider
        if (current != null) return current
        return synchronized(this) {
            databaseProvider ?: StandaloneDatabaseProvider(context.applicationContext).also {
                databaseProvider = it
            }
        }
    }

    fun getDownloadCache(context: Context): SimpleCache {
        val current = downloadCache
        if (current != null) return current
        return synchronized(this) {
            downloadCache ?: run {
                val cacheDir = File(context.applicationContext.filesDir, "downloads/cache")
                SimpleCache(
                    cacheDir,
                    NoOpCacheEvictor(),
                    getDatabaseProvider(context)
                ).also { downloadCache = it }
            }
        }
    }
}

private class LoggingDataSourceFactory(
    private val delegate: DataSource.Factory,
    private val headers: Map<String, String>,
) : DataSource.Factory {
    override fun createDataSource(): DataSource {
        return LoggingDataSource(delegate.createDataSource(), headers)
    }
}

private class LoggingDataSource(
    private val delegate: DataSource,
    private val headers: Map<String, String>,
) : DataSource by delegate {
    override fun open(dataSpec: DataSpec): Long {
        val uri = dataSpec.uri.toString()
        if (uri.startsWith("http://") || uri.startsWith("https://")) {
            Log.d(
                "PlayerVM",
                "Opening HTTP dataSpec: uri=$uri headers=$headers"
            )
        } else {
            Log.d("PlayerVM", "Opening local dataSpec: uri=$uri")
        }
        return delegate.open(dataSpec)
    }
}

sealed interface PlayerEvents {
    data object NavigateBack : PlayerEvents
    data class IsPlayingChanged(val isPlaying: Boolean) : PlayerEvents
    data class PlayWhenReadyChanged(val playWhenReady: Boolean, val reason: Int) : PlayerEvents
}

data class SelectableTrack(
    val label: String,
    val formatId: String?,
    val trackGroup: TrackGroup,
    val trackIndex: Int,
    val isSelected: Boolean,
    val isSupported: Boolean,
    val height: Int = 0 // Added for easier sorting
)
