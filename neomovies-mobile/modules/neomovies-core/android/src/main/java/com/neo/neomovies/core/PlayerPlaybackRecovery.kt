package com.neo.neomovies.core

import androidx.media3.common.PlaybackException

internal object PlayerPlaybackRecovery {
    internal fun shouldFallbackToSoftwareDecoder(
        error: PlaybackException,
        preferSoftwareDecoder: Boolean,
        useExo: Boolean
    ): Boolean {
        if (preferSoftwareDecoder || !useExo) return false
        return when (error.errorCode) {
            PlaybackException.ERROR_CODE_DECODING_FAILED,
            PlaybackException.ERROR_CODE_DECODER_INIT_FAILED,
            PlaybackException.ERROR_CODE_DECODER_QUERY_FAILED,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
            PlaybackException.ERROR_CODE_VIDEO_FRAME_PROCESSING_FAILED,
            -> true
            else -> false
        }
    }
}

