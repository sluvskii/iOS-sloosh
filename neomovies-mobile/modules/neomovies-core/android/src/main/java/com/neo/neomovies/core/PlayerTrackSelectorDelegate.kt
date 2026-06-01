package com.neo.neomovies.core

import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks

internal object PlayerTrackSelectorDelegate {
    internal fun logVideoTracks(tracks: Tracks) {
        val videoGroups = tracks.groups.filter { it.type == C.TRACK_TYPE_VIDEO }
        if (videoGroups.isEmpty()) {
            Log.w("PlayerVM", "videoTrack: no video groups exposed")
            return
        }
        for (group in videoGroups) {
            val trackGroup = group.mediaTrackGroup
            for (i in 0 until trackGroup.length) {
                val format = trackGroup.getFormat(i)
                Log.d(
                    "PlayerVM",
                    "videoTrack: id=${format.id} mime=${format.sampleMimeType} codecs=${format.codecs} ${format.width}x${format.height} supported=${group.isTrackSupported(i)} selected=${group.isTrackSelected(i)}"
                )
            }
        }
    }

    internal fun getSelectableTracks(
        player: Player,
        trackType: @C.TrackType Int,
        episodeVoiceNames: List<String>
    ): List<SelectableTrack> {
        val groups = player.currentTracks.groups.filter { it.type == trackType }
        val result = ArrayList<SelectableTrack>()
        var displayIndex = 1
        val dedupeKeys = HashSet<String>()

        for (group in groups) {
            val trackGroup = group.mediaTrackGroup
            for (i in 0 until trackGroup.length) {
                val format = trackGroup.getFormat(i)
                val label = format.label
                val language = format.language

                val displayLabel = when {
                    trackType == C.TRACK_TYPE_VIDEO && format.height > 0 -> "${format.height}p"
                    trackType == C.TRACK_TYPE_AUDIO -> PlayerMetadataResolver.resolveAudioLabel(format.id, label, episodeVoiceNames)
                    !label.isNullOrBlank() -> label
                    !language.isNullOrBlank() && language != "und" -> language
                    else -> "Track ${displayIndex++}"
                }

                val dedupeKey = when (trackType) {
                    C.TRACK_TYPE_VIDEO -> "video:${format.height}:${displayLabel}"
                    C.TRACK_TYPE_AUDIO -> "audio:${displayLabel}:${language ?: ""}"
                    else -> "$trackType:${format.id}:${displayLabel}"
                }
                if (!dedupeKeys.add(dedupeKey)) continue

                if (trackType == C.TRACK_TYPE_AUDIO) {
                    Log.d(
                        "PlayerVM",
                        "audioTrack: id=${format.id} lang=${format.language} label=${format.label} display=$displayLabel supported=${group.isTrackSupported(i)} selected=${group.isTrackSelected(i)}"
                    )
                }

                result += SelectableTrack(
                    label = displayLabel,
                    formatId = format.id,
                    trackGroup = trackGroup,
                    trackIndex = i,
                    isSelected = group.isTrackSelected(i),
                    isSupported = group.isTrackSupported(i),
                    height = format.height
                )
            }
        }

        if (trackType == C.TRACK_TYPE_VIDEO) {
            result.sortByDescending { it.height }
        }
        return result
    }

    internal fun switchToTrack(player: Player, trackType: @C.TrackType Int, track: SelectableTrack?) {
        val builder = player.trackSelectionParameters.buildUpon()
        if (track == null) {
            builder.clearOverridesOfType(trackType)
                .setTrackTypeDisabled(trackType, trackType == C.TRACK_TYPE_TEXT)
        } else {
            builder.clearOverridesOfType(trackType)
                .setOverrideForType(TrackSelectionOverride(track.trackGroup, listOf(track.trackIndex)))
                .setTrackTypeDisabled(trackType, false)
        }
        player.trackSelectionParameters = builder.build()
    }
}

