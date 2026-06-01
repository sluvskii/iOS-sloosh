package com.neo.neomovies.core

import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata

internal object PlayerMediaItemFactory {
    internal fun create(urls: List<String>, names: List<String>?, baseTitle: String): List<MediaItem> {
        return urls.mapIndexed { index, url ->
            val displayName = names?.getOrNull(index).orEmpty()
            val extras = Bundle().apply { putString("display_name", displayName) }
            MediaItem.Builder()
                .setMediaId(url)
                .setUri(url)
                .setMediaMetadata(
                    MediaMetadata.Builder()
                        .setTitle(baseTitle)
                        .setExtras(extras)
                        .build()
                )
                .build()
        }
    }
}

