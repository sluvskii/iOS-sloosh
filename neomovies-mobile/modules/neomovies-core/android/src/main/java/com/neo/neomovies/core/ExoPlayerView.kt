package com.neo.neomovies.core

import android.content.Context
import android.view.LayoutInflater
import android.widget.FrameLayout
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.okhttp.OkHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.ui.PlayerView
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.views.ExpoView
import okhttp3.OkHttpClient

@UnstableApi
class ExoPlayerView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
    private val playerView: PlayerView
    private var player: ExoPlayer? = null
    
    init {
        // Inflate the layout
        val view = LayoutInflater.from(context).inflate(R.layout.exo_player_view_simple, this, true)
        playerView = view.findViewById(R.id.player_view)
        
        setupPlayer()
    }
    
    private fun setupPlayer() {
        val okHttpClient = OkHttpClient.Builder().build()
        val dataSourceFactory = OkHttpDataSource.Factory(okHttpClient)
        val mediaSourceFactory = DefaultMediaSourceFactory(context)
            .setDataSourceFactory(dataSourceFactory)

        player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(mediaSourceFactory)
            .build()
            
        playerView.player = player
    }
    
    fun setSource(url: String) {
        val mediaItem = MediaItem.fromUri(url)
        player?.setMediaItem(mediaItem)
        player?.prepare()
    }
    
    fun play() {
        player?.play()
    }
    
    fun pause() {
        player?.pause()
    }
    
    fun stop() {
        player?.stop()
    }
    
    fun seekTo(positionMs: Long) {
        player?.seekTo(positionMs)
    }
    
    fun setPlaybackSpeed(speed: Float) {
        player?.setPlaybackSpeed(speed)
    }
    
    override fun onDetachedFromWindow() {
        super.onDetachedFromWindow()
        player?.release()
        player = null
    }
}
