package com.neo.neomovies.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException

object CollapsHTTPClient {
    private const val DEFAULT_USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

    private val client = OkHttpClient.Builder()
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    suspend fun fetch(url: String, referer: String? = null, origin: String? = null): String {
        return withContext(Dispatchers.IO) {
            val requestBuilder = Request.Builder().url(url)

            requestBuilder.addHeader("User-Agent", DEFAULT_USER_AGENT)
            referer?.let { requestBuilder.addHeader("Referer", it) }
            origin?.let { requestBuilder.addHeader("Origin", it) }

            val request = requestBuilder.build()

            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw IOException("HTTP ${response.code}: ${response.message}")
                }
                response.body?.string() ?: throw IOException("Empty response body")
            }
        }
    }
}
