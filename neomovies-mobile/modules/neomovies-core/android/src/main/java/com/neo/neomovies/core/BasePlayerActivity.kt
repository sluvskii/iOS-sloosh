package com.neo.neomovies.core

import android.os.Bundle
import android.view.View
import android.view.WindowManager
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.core.view.updatePadding
import androidx.media3.session.MediaSession

abstract class BasePlayerActivity : AppCompatActivity() {

    abstract val viewModel: PlayerViewModel

    protected open val managePlayerLifecycle: Boolean = true
    protected open val manageMediaSession: Boolean = true

    private var mediaSession: MediaSession? = null
    private var wasPip: Boolean = false
    protected var isEnteringPip: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun onStart() {
        super.onStart()
        if (manageMediaSession && mediaSession == null) {
            val sessionId = "player-${System.identityHashCode(this)}-${System.currentTimeMillis()}"
            mediaSession = MediaSession.Builder(this, viewModel.player)
                .setId(sessionId)
                .build()
        }
    }

    override fun onResume() {
        super.onResume()

        if (managePlayerLifecycle) {
            if (wasPip) {
                wasPip = false
            } else {
                viewModel.player.playWhenReady = viewModel.playWhenReady
            }
        }
        isEnteringPip = false
        hideSystemUI()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onPause() {
        super.onPause()

        if (managePlayerLifecycle) {
            if (isInPictureInPictureMode || isEnteringPip) {
                wasPip = true
            } else {
                viewModel.player.playWhenReady = false
                viewModel.updatePlaybackProgress()
            }
        }
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onStop() {
        super.onStop()
        if (manageMediaSession) {
            mediaSession?.release()
            mediaSession = null
        }
    }

    protected fun hideSystemUI() {
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }

        window.attributes.layoutInDisplayCutoutMode =
            WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
    }

    protected fun configureInsets(playerControls: View) {
        ViewCompat.setOnApplyWindowInsetsListener(playerControls) { view, insets ->
            val cutout = insets.getInsets(WindowInsetsCompat.Type.displayCutout())
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            view.updatePadding(
                left = maxOf(cutout.left, bars.left),
                top = maxOf(cutout.top, bars.top),
                right = maxOf(cutout.right, bars.right),
                bottom = maxOf(cutout.bottom, bars.bottom),
            )
            insets
        }
    }
}
