package com.neo.neomovies.core

import android.content.res.ColorStateList
import android.app.AppOpsManager
import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.graphics.Rect
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.util.Log
import android.util.Rational
import android.view.SurfaceView
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.Space
import android.widget.TextView
import android.widget.Toast
import androidx.activity.OnBackPressedCallback
import androidx.activity.viewModels
import androidx.core.view.isVisible
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.media3.common.C
import androidx.media3.ui.AspectRatioFrameLayout
import androidx.media3.ui.DefaultTimeBar
import androidx.media3.ui.PlayerControlView
import androidx.media3.ui.PlayerView
import com.neo.neomovies.core.R
import com.neo.neomovies.core.databinding.ActivityPlayerBinding
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

var isControlsLocked: Boolean = false

class PlayerActivity : BasePlayerActivity() {

    lateinit var binding: ActivityPlayerBinding

    private val handler = Handler(Looper.getMainLooper())
    private var playerClosedFired = false

    override val viewModel: PlayerViewModel by viewModels()

    private val isPipSupported by lazy {
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) {
            return@lazy false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val appOps = getSystemService(APP_OPS_SERVICE) as AppOpsManager?
            @Suppress("DEPRECATION")
            appOps?.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_PICTURE_IN_PICTURE,
                Process.myUid(),
                packageName,
            ) == AppOpsManager.MODE_ALLOWED
        } else {
            true
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE

        val url = intent.getStringExtra(EXTRA_URL) ?: ""
        val urls = intent.getStringArrayListExtra(EXTRA_URLS)
        val names = intent.getStringArrayListExtra(EXTRA_NAMES)
        val voiceNames = intent.getStringArrayListExtra(EXTRA_VOICE_NAMES)
        val startIndex = intent.getIntExtra(EXTRA_START_INDEX, 0)
        val title = intent.getStringExtra(EXTRA_TITLE)
        val startFromBeginning = intent.getBooleanExtra(EXTRA_START_FROM_BEGINNING, false)
        val useExo = intent.getBooleanExtra(EXTRA_USE_EXO, false)
        val kinopoiskId = intent.getIntExtra(EXTRA_KINOPOISK_ID, -1).takeIf { it > 0 }
        
        // Extract headers from Intent (passed as HEADER_* extras)
        val headers = mutableMapOf<String, String>()
        intent.extras?.keySet()?.forEach { key ->
            if (key.startsWith("HEADER_")) {
                val headerName = key.substring("HEADER_".length)
                val headerValue = intent.getStringExtra(key)
                if (headerValue != null) {
                    headers[headerName] = headerValue
                }
            }
        }
        
        // Log AllohaEpisodeHolder state at activity start
        Log.d("PlayerActivity", "onCreate: AllohaEpisodeHolder.episodeIframeUrls.size=${AllohaEpisodeHolder.episodeIframeUrls.size}, currentIndex=${AllohaEpisodeHolder.currentEpisodeIndex}")
        
        // Extract Alloha variants from intent or pending static variables
        val audioVariants: List<Map<String, Any>> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            @Suppress("UNCHECKED_CAST")
            intent.getSerializableExtra(EXTRA_ALLOHA_AUDIO_VARIANTS, ArrayList::class.java) as? ArrayList<Map<String, Any>>
        } else {
            @Suppress("UNCHECKED_CAST", "DEPRECATION")
            intent.getSerializableExtra(EXTRA_ALLOHA_AUDIO_VARIANTS) as? ArrayList<Map<String, Any>>
        } ?: pendingAllohaAudioVariants ?: emptyList()

        val qualityVariants: List<Map<String, Any>> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            @Suppress("UNCHECKED_CAST")
            intent.getSerializableExtra(EXTRA_ALLOHA_QUALITY_VARIANTS, ArrayList::class.java) as? ArrayList<Map<String, Any>>
        } else {
            @Suppress("UNCHECKED_CAST", "DEPRECATION")
            intent.getSerializableExtra(EXTRA_ALLOHA_QUALITY_VARIANTS) as? ArrayList<Map<String, Any>>
        } ?: pendingAllohaQualityVariants ?: emptyList()
        
        // Clear pending variants after use
        pendingAllohaAudioVariants = null
        pendingAllohaQualityVariants = null

        binding = ActivityPlayerBinding.inflate(layoutInflater)
        setContentView(binding.root)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        viewModel.setEngine(useExo)
        if (kinopoiskId != null) {
            viewModel.setKinopoiskId(kinopoiskId)
        }
        
        // Set Alloha variants if present
        if (audioVariants.isNotEmpty() || qualityVariants.isNotEmpty()) {
            viewModel.setAllohaVariants(audioVariants, qualityVariants)
        }
        
        binding.playerView.player = viewModel.player
        binding.playerView.setControllerVisibilityListener(
            PlayerView.ControllerVisibilityListener { visibility ->
                if (visibility == View.GONE) {
                    hideSystemUI()
                }
            }
        )

        val playerControls = binding.playerView.findViewById<View>(R.id.player_controls)
        val lockedControls = binding.playerView.findViewById<View>(R.id.locked_player_view)

        val overlay = binding.playerView.findViewById<FrameLayout?>(androidx.media3.ui.R.id.exo_overlay)

        val playPauseButton = binding.playerView.findViewById<ImageButton>(R.id.exo_play_pause)
        playPauseButton.imageTintList = ColorStateList.valueOf(Color.BLACK)

        val rippleFfwd = binding.imageFfwdAnimationRipple
        val rippleRewind = binding.imageRewindAnimationRipple
        val ripplePlayback = binding.imagePlaybackAnimationRipple
        val doubleTapDetector = GestureDetector(
            this,
            object : GestureDetector.SimpleOnGestureListener() {
                override fun onDown(e: MotionEvent): Boolean {
                    return true
                }

                override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                    if (isControlsLocked || viewModel.isInPictureInPictureMode) return false
                    if (binding.playerView.isControllerFullyVisible) {
                        binding.playerView.hideController()
                    } else {
                        binding.playerView.showController()
                    }
                    return true
                }

                override fun onDoubleTap(e: MotionEvent): Boolean {
                    if (isControlsLocked || viewModel.isInPictureInPictureMode) return false
                    val w = overlay?.width?.takeIf { it > 0 } ?: return false

                    val areaWidth = w / 5
                    val leftBoundary = areaWidth * 2
                    val rightBoundary = areaWidth * 3

                    val seekMs = 5_000L
                    when (e.x.toInt()) {
                        in 0 until leftBoundary -> {
                            val player = viewModel.player
                            val newPos = (player.currentPosition - seekMs).coerceAtLeast(0L)
                            player.seekTo(newPos)
                            animateRipple(rippleRewind)
                        }
                        in leftBoundary until rightBoundary -> {
                            val player = viewModel.player
                            if (player.isPlaying) player.pause() else player.play()
                            animateRipple(ripplePlayback)
                        }
                        else -> {
                            val player = viewModel.player
                            val dur = player.duration.takeIf { it > 0 } ?: Long.MAX_VALUE
                            val newPos = (player.currentPosition + seekMs).coerceAtMost(dur)
                            player.seekTo(newPos)
                            animateRipple(rippleFfwd)
                        }
                    }
                    return true
                }
            },
        )

        overlay?.setOnTouchListener { _, event -> doubleTapDetector.onTouchEvent(event) }

        isControlsLocked = false

        configureInsets(playerControls)
        configureInsets(lockedControls)

        binding.playerView.findViewById<View>(R.id.back_button).setOnClickListener {
            finishPlayback()
        }

        val useCollapsHeaders = intent.getBooleanExtra(EXTRA_USE_COLLAPS_HEADERS, false)

        val videoNameTextView = binding.playerView.findViewById<TextView>(R.id.video_name)
        val audioButton = binding.playerView.findViewById<ImageButton>(R.id.btn_audio_track)
        val subtitleButton = binding.playerView.findViewById<ImageButton>(R.id.btn_subtitle)
        val speedButton = binding.playerView.findViewById<ImageButton>(R.id.btn_speed)
        val qualityButton = binding.playerView.findViewById<ImageButton>(R.id.btn_quality)
        val aspectRatioButton = binding.playerView.findViewById<ImageButton>(R.id.btn_aspect_ratio)

        audioButton.isEnabled = false
        audioButton.imageAlpha = 75
        subtitleButton.isEnabled = false
        subtitleButton.imageAlpha = 75

        speedButton.isEnabled = false
        speedButton.imageAlpha = 75

        qualityButton.isEnabled = false
        qualityButton.imageAlpha = 75

        // Quality button visibility based on Collaps headers or Alloha variants
        qualityButton.isVisible = useCollapsHeaders || audioVariants.isNotEmpty() || qualityVariants.isNotEmpty()
                || viewModel.getAllohaAudioVariants().isNotEmpty() || viewModel.getAllohaQualityVariants().size > 1
        
        audioButton.setOnClickListener {
            val hasAllohaVariants = viewModel.getAllohaAudioVariants().isNotEmpty()
            if (hasAllohaVariants) {
                AllohaVariantSelectionDialogFragment
                    .newInstance(AllohaVariantSelectionDialogFragment.TYPE_AUDIO)
                    .show(supportFragmentManager, "allohavariantdialog")
            } else {
                TrackSelectionDialogFragment
                    .newInstance(C.TRACK_TYPE_AUDIO)
                    .show(supportFragmentManager, "trackselectiondialog")
            }
        }

        subtitleButton.setOnClickListener {
            TrackSelectionDialogFragment
                .newInstance(C.TRACK_TYPE_TEXT)
                .show(supportFragmentManager, "trackselectiondialog")
        }

        qualityButton.setOnClickListener {
            val hasAllohaQuality = viewModel.getAllohaAudioVariants().isNotEmpty() || viewModel.getAllohaQualityVariants().size > 1
            if (hasAllohaQuality) {
                AllohaVariantSelectionDialogFragment
                    .newInstance(AllohaVariantSelectionDialogFragment.TYPE_QUALITY)
                    .show(supportFragmentManager, "allohavariantdialog")
            } else {
                TrackSelectionDialogFragment
                    .newInstance(C.TRACK_TYPE_VIDEO)
                    .show(supportFragmentManager, "trackselectiondialog")
            }
        }

        speedButton.setOnClickListener {
            SpeedSelectionDialogFragment
                .newInstance()
                .show(supportFragmentManager, "speedselectiondialog")
        }

        aspectRatioButton.setOnClickListener {
            binding.playerView.resizeMode =
                if (binding.playerView.resizeMode == AspectRatioFrameLayout.RESIZE_MODE_FIT) {
                    AspectRatioFrameLayout.RESIZE_MODE_FILL
                } else {
                    AspectRatioFrameLayout.RESIZE_MODE_FIT
                }
        }

        val pipButton = binding.playerView.findViewById<ImageButton>(R.id.btn_pip)
        pipButton.setOnClickListener {
            pictureInPicture()
        }

        // Episode navigation buttons for Alloha playlist
        val prevButton = binding.playerView.findViewById<ImageButton>(R.id.btn_prev_episode)
        val nextButton = binding.playerView.findViewById<ImageButton>(R.id.btn_next_episode)

        // Set initial state based on AllohaEpisodeHolder
        val initCanPrev = if (AllohaEpisodeHolder.episodeIframeUrls.isNotEmpty()) AllohaEpisodeHolder.hasPreviousEpisode() else false
        val initCanNext = if (AllohaEpisodeHolder.episodeIframeUrls.isNotEmpty()) AllohaEpisodeHolder.hasNextEpisode() else false
        prevButton.isEnabled = initCanPrev
        prevButton.imageAlpha = if (initCanPrev) 255 else 75
        nextButton.isEnabled = initCanNext
        nextButton.imageAlpha = if (initCanNext) 255 else 75
        
        prevButton.setOnClickListener {
            // Check at click time if this is Alloha episode playlist
            if (AllohaEpisodeHolder.episodeIframeUrls.isNotEmpty()) {
                switchAllohaEpisode(-1)
            } else {
                viewModel.previousEpisode()
            }
        }
        
        nextButton.setOnClickListener {
            // Check at click time if this is Alloha episode playlist
            if (AllohaEpisodeHolder.episodeIframeUrls.isNotEmpty()) {
                switchAllohaEpisode(+1)
            } else {
                viewModel.nextEpisode()
            }
        }

        playPauseButton.setOnClickListener {
            if (viewModel.player.playWhenReady) {
                viewModel.playWhenReady = false
                viewModel.player.pause()
            } else {
                viewModel.playWhenReady = true
                viewModel.player.play()
            }
        }

        // Set marker color
        val timeBar = binding.playerView.findViewById<DefaultTimeBar>(R.id.exo_progress)
        timeBar.setAdMarkerColor(Color.WHITE)

        // Set episode info for navigation
        val totalEpisodes = urls?.size ?: if (url.isNotEmpty()) 1 else 0
        viewModel.setEpisodeInfo(startIndex, totalEpisodes)

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                launch {
                    viewModel.uiState.collect { uiState ->
                        videoNameTextView.text = uiState.currentItemTitle
                        
                        // Use AllohaEpisodeHolder for Alloha sources
                        val allohaEpisodeCount = AllohaEpisodeHolder.episodeIframeUrls.size
                        val allohaCurrentIdx = AllohaEpisodeHolder.currentEpisodeIndex

                        val canPrev = if (allohaEpisodeCount > 0) {
                            AllohaEpisodeHolder.hasPreviousEpisode()
                        } else {
                            viewModel.canGoPreviousEpisode()
                        }
                        val canNext = if (allohaEpisodeCount > 0) {
                            AllohaEpisodeHolder.hasNextEpisode()
                        } else {
                            viewModel.canGoNextEpisode()
                        }

                        Log.d("PlayerActivity", "Episode buttons: allohaEpisodes=$allohaEpisodeCount, currentIdx=$allohaCurrentIdx, canPrev=$canPrev, canNext=$canNext")

                        val prevButton = binding.playerView.findViewById<ImageButton>(R.id.btn_prev_episode)
                        val nextButton = binding.playerView.findViewById<ImageButton>(R.id.btn_next_episode)
                        prevButton.isEnabled = canPrev
                        prevButton.imageAlpha = if (canPrev) 255 else 75
                        nextButton.isEnabled = canNext
                        nextButton.imageAlpha = if (canNext) 255 else 75

                        if (uiState.fileLoaded) {
                            audioButton.isEnabled = true
                            audioButton.imageAlpha = 255
                            subtitleButton.isEnabled = true
                            subtitleButton.imageAlpha = 255
                            speedButton.isEnabled = true
                            speedButton.imageAlpha = 255
                            val hasAllohaVariants = viewModel.getAllohaAudioVariants().isNotEmpty() || viewModel.getAllohaQualityVariants().size > 1
                            if (useCollapsHeaders || hasAllohaVariants) {
                                qualityButton.isEnabled = true
                                qualityButton.imageAlpha = 255
                            }
                            // Show PiP button if supported
                            val pipButton = binding.playerView.findViewById<ImageButton>(R.id.btn_pip)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isPipSupported) {
                                pipButton.visibility = View.VISIBLE
                                pipButton.isEnabled = true
                                pipButton.imageAlpha = 255
                            }
                        }
                    }
                }

                launch {
                    viewModel.playerEpoch.collect {
                        binding.playerView.player = viewModel.player
                    }
                }

                launch {
                    viewModel.eventsChannelFlow.collect { event ->
                        when (event) {
                            is PlayerEvents.NavigateBack -> finishPlayback()
                            is PlayerEvents.IsPlayingChanged -> {
                                val shouldShowPause = viewModel.player.playWhenReady
                                playPauseButton.setImageResource(
                                    if (shouldShowPause) R.drawable.ic_pause else R.drawable.ic_play
                                )
                                playPauseButton.imageTintList = ColorStateList.valueOf(Color.BLACK)

                                if (shouldShowPause) {
                                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                                } else {
                                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                                }

                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    runCatching { setPictureInPictureParams(pipParams(shouldShowPause)) }
                                }
                            }

                            is PlayerEvents.PlayWhenReadyChanged -> {
                                playPauseButton.setImageResource(
                                    if (event.playWhenReady) R.drawable.ic_pause else R.drawable.ic_play
                                )
                                playPauseButton.imageTintList = ColorStateList.valueOf(Color.BLACK)

                                if (event.playWhenReady) {
                                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                                } else {
                                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                                }

                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                    runCatching { setPictureInPictureParams(pipParams(event.playWhenReady)) }
                                }
                            }
                        }
                    }
                }

                launch {
                    while (true) {
                        viewModel.updatePlaybackProgress()
                        delay(5000L)
                    }
                }
            }
        }

        // Use PlayerControlView to connect next/prev to chapters if needed later.
        findViewById<PlayerControlView>(R.id.exo_controller)

        val finalUrls = urls ?: arrayListOf(url)
        android.util.Log.d("PlayerActivity", "Calling initializePlayer with urls: $finalUrls")

        val allohaIframeUrl = intent.getStringExtra(EXTRA_ALLOHA_IFRAME_URL)
        if (!allohaIframeUrl.isNullOrBlank()) {
            lifecycleScope.launch {
                try {
                    val resolver = AllohaRuntimeResolver(this@PlayerActivity)
                    val resolved = resolver.resolve(allohaIframeUrl)
                    @Suppress("UNCHECKED_CAST")
                    val av = (resolved["audioVariants"] as? List<Map<String, Any>>) ?: emptyList()
                    @Suppress("UNCHECKED_CAST")
                    val qv = (resolved["qualityVariants"] as? List<Map<String, Any>>) ?: emptyList()
                    if (av.isNotEmpty() || qv.isNotEmpty()) {
                        viewModel.setAllohaVariants(av, qv)
                    }
                    val resolvedUrl = viewModel.getBestAllohaUrl()
                        ?: resolved["url"] as? String
                        ?: throw Exception("No URL from resolver")
                    android.util.Log.d("PlayerActivity", "allohaIframe resolved: url=$resolvedUrl av=${av.size} qv=${qv.size}")
                    viewModel.initializePlayer(
                        urls = arrayListOf(resolvedUrl),
                        names = names,
                        voiceNames = voiceNames,
                        startIndex = 0,
                        title = title,
                        startFromBeginning = startFromBeginning,
                        kinopoiskId = kinopoiskId,
                    )
                } catch (e: Exception) {
                    android.util.Log.e("PlayerActivity", "allohaIframe resolve failed", e)
                    Toast.makeText(this@PlayerActivity, "Failed to load: ${e.message}", Toast.LENGTH_SHORT).show()
                    finishPlayback()
                }
            }
        } else {
            // If Alloha variants were pre-loaded via exoPlayerSetAllohaVariants, use best quality URL
            val bestAllohaUrl = viewModel.getBestAllohaUrl()
            val launchUrls = if (bestAllohaUrl != null && finalUrls.size == 1) arrayListOf(bestAllohaUrl) else finalUrls
            viewModel.initializePlayer(
                urls = launchUrls,
                names = names,
                voiceNames = voiceNames,
                startIndex = startIndex,
                title = title,
                startFromBeginning = startFromBeginning,
                kinopoiskId = kinopoiskId,
            )
        }
        hideSystemUI()

        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                finishPlayback()
            }
        })
    }

    private fun animateRipple(image: ImageView) {
        image.animate().cancel()
        image.alpha = 0f
        image.scaleX = 1f
        image.scaleY = 1f

        val rippleImageHeight = image.height.takeIf { it > 0 } ?: return
        val playerViewHeight = binding.playerView.height.toFloat().takeIf { it > 0f } ?: return
        val playerViewWidth = binding.playerView.width.toFloat().takeIf { it > 0f } ?: return
        val scaleDifference = playerViewHeight / rippleImageHeight
        val playerViewAspectRatio = playerViewWidth / playerViewHeight
        val scaleValue = scaleDifference * playerViewAspectRatio

        image
            .animate()
            .alpha(1f)
            .scaleX(scaleValue)
            .scaleY(scaleValue)
            .setDuration(180)
            .setInterpolator(DecelerateInterpolator())
            .withEndAction {
                image
                    .animate()
                    .alpha(0f)
                    .setDuration(150)
                    .setInterpolator(AccelerateInterpolator())
                    .withEndAction {
                        image.scaleX = 1f
                        image.scaleY = 1f
                    }
                    .start()
            }
            .start()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)

        val url = intent.getStringExtra(EXTRA_URL) ?: ""
        val urls = intent.getStringArrayListExtra(EXTRA_URLS)
        val names = intent.getStringArrayListExtra(EXTRA_NAMES)
        val voiceNames = intent.getStringArrayListExtra(EXTRA_VOICE_NAMES)
        val startIndex = intent.getIntExtra(EXTRA_START_INDEX, 0)
        val title = intent.getStringExtra(EXTRA_TITLE)
        val startFromBeginning = intent.getBooleanExtra(EXTRA_START_FROM_BEGINNING, false)
        val useExo = intent.getBooleanExtra(EXTRA_USE_EXO, false)
        val kinopoiskId = intent.getIntExtra(EXTRA_KINOPOISK_ID, -1).takeIf { it > 0 }

        viewModel.setEngine(useExo)
        binding.playerView.player = viewModel.player
        viewModel.initializePlayer(
            urls = urls ?: listOf(url),
            names = names,
            voiceNames = voiceNames,
            startIndex = startIndex,
            title = title,
            startFromBeginning = startFromBeginning,
            kinopoiskId = kinopoiskId,
            episodeProgressCallback = null, // Will be implemented with proper callback mechanism
        )
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            viewModel.player.isPlaying &&
            !isControlsLocked &&
            isPipSupported
        ) {
            pictureInPicture()
        }
    }

    override fun onPause() {
        super.onPause()
        viewModel.updatePlaybackProgress()
    }

    override fun onStop() {
        super.onStop()
        viewModel.updatePlaybackProgress()
    }

    private fun finishPlayback() {
        viewModel.updatePlaybackProgress()
        runCatching {
            viewModel.player.clearVideoSurfaceView(binding.playerView.videoSurfaceView as SurfaceView)
        }
        handler.removeCallbacksAndMessages(null)
        AllohaEpisodeHolder.clear()
        if (!playerClosedFired) {
            playerClosedFired = true
            onPlayerClosed?.invoke()
        }
        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        if (!playerClosedFired) {
            playerClosedFired = true
            onPlayerClosed?.invoke()
        }
    }

    private fun pipParams(
        enableAutoEnter: Boolean = viewModel.player.isPlaying
    ): PictureInPictureParams {
        val viewW = binding.playerView.width
        val viewH = binding.playerView.height
        val displayAspectRatio =
            if (viewW > 0 && viewH > 0) {
                Rational(viewW, viewH)
            } else {
                Rational(16, 9)
            }

        val aspectRatio =
            binding.playerView.player?.videoSize?.let {
                if (it.width > 0 && it.height > 0) {
                    Rational(
                        it.width.coerceAtMost((it.height * 2.39f).toInt()),
                        it.height.coerceAtMost((it.width * 2.39f).toInt()),
                    )
                } else {
                    null
                }
            } ?: Rational(16, 9)

        val sourceRectHint =
            if (viewW <= 0 || viewH <= 0) {
                null
            } else if (displayAspectRatio < aspectRatio) {
                val space = ((viewH - (viewW.toFloat() / aspectRatio.toFloat())) / 2).toInt()
                Rect(
                    0,
                    space,
                    viewW,
                    (viewW.toFloat() / aspectRatio.toFloat()).toInt() + space,
                )
            } else {
                val space = ((viewW - (viewH.toFloat() * aspectRatio.toFloat())) / 2).toInt()
                Rect(
                    space,
                    0,
                    (viewH.toFloat() * aspectRatio.toFloat()).toInt() + space,
                    viewH,
                )
            }

        val builder =
            PictureInPictureParams.Builder()
                .setAspectRatio(aspectRatio)

        sourceRectHint?.let { builder.setSourceRectHint(it) }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(enableAutoEnter)
        }

        return builder.build()
    }

    private fun pictureInPicture() {
        if (!isPipSupported || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val entered = runCatching { enterPictureInPictureMode(pipParams()) }
            .onFailure { t ->
                Log.e("PlayerActivity", "Failed to enter Picture-in-Picture", t)
            }
            .getOrDefault(false)
        isEnteringPip = entered
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        isEnteringPip = false
        viewModel.isInPictureInPictureMode = isInPictureInPictureMode

        binding.playerView.useController = !isInPictureInPictureMode
        if (isInPictureInPictureMode) {
            binding.playerView.hideController()
        }
    }

    private fun switchAllohaEpisode(delta: Int) {
        val holder = AllohaEpisodeHolder
        Log.d("PlayerActivity", "switchAllohaEpisode: delta=$delta, currentIndex=${holder.currentEpisodeIndex}, totalEpisodes=${holder.episodeIframeUrls.size}")
        
        val newIndex = holder.currentEpisodeIndex + delta
        if (newIndex < 0 || newIndex >= holder.episodeIframeUrls.size) {
            Log.d("PlayerActivity", "switchAllohaEpisode: newIndex=$newIndex out of bounds")
            return
        }
        
        val iframeUrl = holder.episodeIframeUrls.getOrNull(newIndex)
        if (iframeUrl.isNullOrBlank()) {
            Log.e("PlayerActivity", "switchAllohaEpisode: no iframe URL at index $newIndex")
            return
        }
        
        val episodeName = holder.episodeNames.getOrNull(newIndex) ?: "Episode ${newIndex + 1}"
        Log.d("PlayerActivity", "switchAllohaEpisode: switching to episode '$episodeName' at $iframeUrl")

        // Save current progress before switching
        viewModel.updatePlaybackProgress()
        // Stop current playback immediately so user knows something is happening
        viewModel.player.stop()

        val videoNameTextView = binding.playerView.findViewById<TextView>(R.id.video_name)
        val displayTitle = if (holder.baseTitle.isNotBlank()) {
            "${holder.baseTitle} • $episodeName"
        } else {
            episodeName
        }

        videoNameTextView.text = displayTitle

        lifecycleScope.launch {
            try {
                // Resolve the new episode's iframe URL
                val resolver = AllohaRuntimeResolver(this@PlayerActivity)
                Log.d("PlayerActivity", "switchAllohaEpisode: resolving iframe...")
                val resolved = resolver.resolve(iframeUrl)
                Log.d("PlayerActivity", "switchAllohaEpisode: resolved=$resolved")
                
                val newUrl = resolved["url"] as? String
                if (newUrl.isNullOrBlank()) {
                    Log.e("PlayerActivity", "switchAllohaEpisode: no URL in resolved result")
                    Toast.makeText(this@PlayerActivity, "Failed to load episode", Toast.LENGTH_SHORT).show()
                    return@launch
                }

                // Update holder state
                holder.currentEpisodeIndex = newIndex

                // Update audio/quality variants
                @Suppress("UNCHECKED_CAST")
                val audioVariants = (resolved["audioVariants"] as? List<Map<String, Any>>) ?: emptyList()
                @Suppress("UNCHECKED_CAST")
                val qualityVariants = (resolved["qualityVariants"] as? List<Map<String, Any>>) ?: emptyList()
                holder.currentAudioVariants = audioVariants
                holder.currentQualityVariants = qualityVariants
                viewModel.setAllohaVariants(audioVariants, qualityVariants)

                // Restore saved progress for the new episode
                val kpId = intent.getIntExtra(EXTRA_KINOPOISK_ID, -1).takeIf { it > 0 }
                val savedPositionMs: Long = if (kpId != null) {
                    val match = Regex("[Ss](\\d{1,2})[Ee](\\d{1,3})").find(episodeName)
                    val season = match?.groupValues?.getOrNull(1)?.toIntOrNull()
                    val episode = match?.groupValues?.getOrNull(2)?.toIntOrNull()
                    if (season != null && episode != null) {
                        viewModel.readSavedEpisodePositionMs(kpId, season, episode)
                    } else 0L
                } else 0L

                // Use best quality URL based on restored/default selection
                val bestUrl = viewModel.getBestAllohaUrl() ?: newUrl
                Log.d("PlayerActivity", "switchAllohaEpisode: reloading player with URL=$bestUrl startPositionMs=$savedPositionMs")
                viewModel.reloadWithUrl(bestUrl, @Suppress("UNCHECKED_CAST") (resolved["headers"] as? Map<String, String>) ?: holder.headers, savedPositionMs)

                // Update button states
                val prevButton = binding.playerView.findViewById<ImageButton>(R.id.btn_prev_episode)
                val nextButton = binding.playerView.findViewById<ImageButton>(R.id.btn_next_episode)
                prevButton.isEnabled = holder.hasPreviousEpisode()
                prevButton.imageAlpha = if (holder.hasPreviousEpisode()) 255 else 75
                nextButton.isEnabled = holder.hasNextEpisode()
                nextButton.imageAlpha = if (holder.hasNextEpisode()) 255 else 75

                Log.d("PlayerActivity", "switchAllohaEpisode: success!")

            } catch (e: Exception) {
                Log.e("PlayerActivity", "switchAllohaEpisode: failed", e)
                Toast.makeText(this@PlayerActivity, "Error: ${e.message}", Toast.LENGTH_SHORT).show()
            }
        }
    }

    companion object {
        const val EXTRA_URL = "url"
        const val EXTRA_URLS = "urls"
        const val EXTRA_NAMES = "names"
        const val EXTRA_START_INDEX = "startIndex"
        const val EXTRA_TITLE = "title"
        const val EXTRA_VOICE_NAMES = "voice_names"
        const val EXTRA_USE_EXO = "use_exo"
        const val EXTRA_USE_COLLAPS_HEADERS = "use_collaps_headers"
        const val EXTRA_START_FROM_BEGINNING = "start_from_beginning"
        const val EXTRA_KINOPOISK_ID = "kinopoisk_id"
        const val EXTRA_ALLOHA_AUDIO_VARIANTS = "alloha_audio_variants"
        const val EXTRA_ALLOHA_QUALITY_VARIANTS = "alloha_quality_variants"
        const val EXTRA_ALLOHA_IFRAME_URL = "alloha_iframe_url"
        
        // Callback invoked when player activity is closed
        @Volatile
        var onPlayerClosed: (() -> Unit)? = null
        
        // Pending variants set before activity launch
        @Volatile
        var pendingAllohaAudioVariants: ArrayList<Map<String, Any>>? = null
        @Volatile
        var pendingAllohaQualityVariants: ArrayList<Map<String, Any>>? = null

        fun intent(context: android.content.Context, url: String, title: String? = null, startFromBeginning: Boolean = false): Intent {
            return Intent(context, PlayerActivity::class.java).apply {
                putExtra(EXTRA_URL, url)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_START_FROM_BEGINNING, startFromBeginning)
                putExtra(EXTRA_USE_EXO, false)
            }
        }

        fun intentExo(context: android.content.Context, url: String, title: String? = null, startFromBeginning: Boolean = false): Intent {
            return Intent(context, PlayerActivity::class.java).apply {
                putExtra(EXTRA_URL, url)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_START_FROM_BEGINNING, startFromBeginning)
                putExtra(EXTRA_USE_EXO, true)
            }
        }

        fun intent(
            context: android.content.Context,
            urls: List<String>,
            names: List<String>? = null,
            startIndex: Int = 0,
            title: String? = null,
            startFromBeginning: Boolean = false,
            useExo: Boolean = false,
            useCollapsHeaders: Boolean = false,
            kinopoiskId: Int? = null,
            episodeProgressCallback: ((Int, Int, Int, Long, Long) -> Unit)? = null,
        ): Intent {
            return Intent(context, PlayerActivity::class.java).apply {
                putExtra(EXTRA_URL, urls.firstOrNull().orEmpty())
                putStringArrayListExtra(EXTRA_URLS, ArrayList(urls))
                putStringArrayListExtra(EXTRA_NAMES, ArrayList(names.orEmpty()))
                putExtra(EXTRA_START_INDEX, startIndex)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_START_FROM_BEGINNING, startFromBeginning)
                putExtra(EXTRA_USE_EXO, useExo)
                putExtra(EXTRA_USE_COLLAPS_HEADERS, useCollapsHeaders)
                putExtra(EXTRA_KINOPOISK_ID, kinopoiskId)
            }
        }

        fun intentExo(
            context: android.content.Context,
            urls: List<String>,
            names: List<String>? = null,
            startIndex: Int = 0,
            title: String? = null,
            startFromBeginning: Boolean = false,
            useCollapsHeaders: Boolean = false,
            kinopoiskId: Int? = null,
            episodeProgressCallback: ((Int, Int, Int, Long, Long) -> Unit)? = null,
        ): Intent {
            return Intent(context, PlayerActivity::class.java).apply {
                putExtra(EXTRA_URL, urls.firstOrNull().orEmpty())
                putStringArrayListExtra(EXTRA_URLS, ArrayList(urls))
                putStringArrayListExtra(EXTRA_NAMES, ArrayList(names.orEmpty()))
                putExtra(EXTRA_START_INDEX, startIndex)
                putExtra(EXTRA_TITLE, title)
                putExtra(EXTRA_START_FROM_BEGINNING, startFromBeginning)
                putExtra(EXTRA_USE_EXO, true)
                putExtra(EXTRA_USE_COLLAPS_HEADERS, useCollapsHeaders)
                putExtra(EXTRA_KINOPOISK_ID, kinopoiskId)
            }
        }
    }
}
