package com.neo.neomovies.core

import android.content.Context
import android.content.SharedPreferences

internal class PlayerProgressStore(context: Context) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("player_progress", Context.MODE_PRIVATE)
    private val watchedPrefs: SharedPreferences =
        context.getSharedPreferences("collaps_watched", Context.MODE_PRIVATE)
    private val durationPrefix = "duration_"

    internal fun readStartPosition(progressKey: String, startFromBeginning: Boolean): Long {
        if (startFromBeginning) return 0L
        
        // For kp_ keys (series), check watched status in watchedPrefs
        if (progressKey.startsWith("kp_")) {
            val watched = watchedPrefs.getBoolean("${progressKey}_watched", false)
            if (watched) return 0L
            return watchedPrefs.getLong(progressKey, 0L)
        }
        
        // For other keys, use regular prefs
        if (isWatched(progressKey)) return 0L
        return prefs.getLong(progressKey, 0L)
    }

    internal fun readSavedDuration(progressKey: String): Long {
        if (progressKey.isBlank()) return 0L
        
        // For kp_ keys (series), read from watchedPrefs
        if (progressKey.startsWith("kp_")) {
            return watchedPrefs.getLong("${progressKey}_duration", 0L)
        }
        
        return prefs.getLong(durationPrefix + progressKey, 0L)
    }

    internal fun buildProgressKey(
        mediaId: String,
        displayName: String,
        displayTitle: String,
        kpId: Int?
    ): String {
        val parsed = PlayerMetadataResolver.parseSeasonEpisode(displayName)
            ?: PlayerMetadataResolver.parseSeasonEpisode(displayTitle)
        
        // Extract season and episode numbers if available
        if (kpId != null && parsed != null) {
            val match = Regex("[Ss](\\d{1,2})[Ee](\\d{1,3})").find(parsed)
            if (match != null) {
                val season = match.groupValues[1].toIntOrNull()
                val episode = match.groupValues[2].toIntOrNull()
                if (season != null && episode != null) {
                    // Use same format as persistEpisodeProgress for consistency
                    return "kp_${kpId}_s${season}_e${episode}"
                }
            }
        }
        return "pos_$mediaId"
    }

    internal fun savePosition(progressKey: String, positionMs: Long, durationMs: Long? = null) {
        // For kp_ keys (series), save to watchedPrefs to match persistEpisodeProgress
        if (progressKey.startsWith("kp_")) {
            val editor = watchedPrefs.edit().putLong(progressKey, positionMs)
            if (durationMs != null && durationMs > 0L) {
                editor.putLong("${progressKey}_duration", durationMs)
            }
            editor.apply()
            return
        }
        
        // For other keys, use regular prefs
        val editor = prefs.edit().putLong(progressKey, positionMs)
        if (durationMs != null && durationMs > 0L) {
            editor.putLong(durationPrefix + progressKey, durationMs)
        }
        editor.apply()
    }

    internal fun clearPosition(progressKey: String) {
        prefs.edit().remove(progressKey).remove(durationPrefix + progressKey).apply()
    }

    internal fun clearAllohaEpisodeProgress(kpId: Int, episodeIndex: Int) {
        prefs.edit().remove("pos_alloha_${kpId}_ep$episodeIndex").apply()
    }

    internal fun persistEpisodeProgress(kpId: Int, season: Int, episode: Int, positionMs: Long, durationMs: Long) {
        if (season <= 0 || episode <= 0) return
        val watchedKey = "kp_${kpId}_s${season}_e${episode}"
        val now = System.currentTimeMillis()
        val watchedThresholdMs = if (durationMs > 0) {
            val percentThreshold = (durationMs * 0.85f).toLong()
            val creditsThreshold = durationMs - 180_000L
            maxOf(percentThreshold, creditsThreshold)
        } else {
            Long.MAX_VALUE
        }
        val watched = durationMs > 0 && positionMs >= watchedThresholdMs
        watchedPrefs.edit()
            .putLong(watchedKey, positionMs)
            .putBoolean("${watchedKey}_watched", watched)
            .putLong("${watchedKey}_duration", durationMs)
            .putLong("${watchedKey}_updated_at", now)
            .putInt("kp_${kpId}_last_season", season)
            .putInt("kp_${kpId}_last_episode", episode)
            .putLong("kp_${kpId}_last_position", positionMs)
            .putLong("kp_${kpId}_last_duration", durationMs)
            .putLong("kp_${kpId}_last_updated_at", now)
            .apply()
    }

    internal fun persistGenericKpProgress(kpId: Int, positionMs: Long, durationMs: Long) {
        watchedPrefs.edit()
            .putLong("kp_${kpId}_last_position", positionMs)
            .putLong("kp_${kpId}_last_duration", durationMs)
            .putLong("kp_${kpId}_last_updated_at", System.currentTimeMillis())
            .apply()
    }

    internal fun resetIfNearEnd(progressKey: String?, restoredPositionMs: Long, durationMs: Long): Long? {
        if (durationMs <= 0L) return null
        val restartThresholdMs = minOf(60_000L, durationMs / 50)
        val shouldRestartFromBeginning =
            restoredPositionMs >= durationMs || restoredPositionMs >= (durationMs - restartThresholdMs)

        if (!shouldRestartFromBeginning) return null

        if (!progressKey.isNullOrBlank()) {
            prefs.edit().putLong(progressKey, 0L).apply()
        }
        return 0L
    }

    internal fun markAsWatched(progressKey: String) {
        if (progressKey.isBlank()) return
        if (progressKey.startsWith("kp_")) {
            watchedPrefs.edit().putBoolean("${progressKey}_watched", true).apply()
        } else {
            prefs.edit().putBoolean("${progressKey}_watched", true).apply()
        }
    }

    internal fun isWatched(progressKey: String): Boolean {
        if (progressKey.isBlank()) return false
        return prefs.getBoolean("${progressKey}_watched", false)
    }
}
