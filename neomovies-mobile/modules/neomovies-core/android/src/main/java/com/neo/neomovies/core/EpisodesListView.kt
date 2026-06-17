package com.neo.neomovies.core

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.appcompat.content.res.AppCompatResources
import androidx.appcompat.widget.AppCompatImageView
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.bumptech.glide.Glide
import com.bumptech.glide.load.engine.DiskCacheStrategy
import expo.modules.kotlin.AppContext
import expo.modules.kotlin.viewevent.EventDispatcher
import expo.modules.kotlin.views.ExpoView

class EpisodesListView(context: Context, appContext: AppContext) : ExpoView(context, appContext) {
  private val onEpisodePress by EventDispatcher<Map<String, Any>>()
  private val onContentHeight by EventDispatcher<Map<String, Any>>()
  private val onDownloadPress by EventDispatcher<Map<String, Any>>()
  private val recyclerView = RecyclerView(context)
  private val adapter = EpisodesAdapter(
    onEpisodePress = { episode ->
      onEpisodePress(mapOf("season" to episode.season, "episode" to episode.episode))
    },
    onDownloadPress = { episode ->
      onDownloadPress(mapOf("season" to episode.season, "episode" to episode.episode))
    }
  )

  init {
    recyclerView.layoutManager = LinearLayoutManager(context, LinearLayoutManager.VERTICAL, false)
    recyclerView.adapter = adapter
    recyclerView.overScrollMode = View.OVER_SCROLL_NEVER
    recyclerView.setHasFixedSize(false)
    recyclerView.isNestedScrollingEnabled = false
    recyclerView.layoutManager?.isItemPrefetchEnabled = true
    recyclerView.viewTreeObserver.addOnGlobalLayoutListener {
      val px = recyclerView.computeVerticalScrollRange()
      if (px > 0) {
        val dp = px / resources.displayMetrics.density
        onContentHeight(mapOf("height" to dp))
      }
    }
    addView(recyclerView, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT))
  }

  fun setEpisodes(value: List<Map<String, Any?>>) {
    val items = value.mapNotNull { raw ->
      val season = (raw["season"] as? Number)?.toInt() ?: return@mapNotNull null
      val episode = (raw["episode"] as? Number)?.toInt() ?: return@mapNotNull null
      EpisodeUi(
        season = season,
        episode = episode,
        title = (raw["title"] as? String).orEmpty(),
        description = (raw["description"] as? String).orEmpty(),
        progress = ((raw["progress"] as? Number)?.toInt() ?: 0).coerceIn(0, 100),
        stillUrl = raw["stillUrl"] as? String,
        fallbackPosterUrl = raw["fallbackPosterUrl"] as? String,
        tmdbRating = (raw["tmdbRating"] as? Number)?.toDouble(),
        imdbRating = (raw["imdbRating"] as? Number)?.toDouble(),
      )
    }
    adapter.submit(items)
    recyclerView.post {
      val px = recyclerView.computeVerticalScrollRange()
      if (px > 0) {
        val dp = px / resources.displayMetrics.density
        onContentHeight(mapOf("height" to dp))
      }
    }
  }

  fun setTextColor(hex: String?) { adapter.textColor = parseColor(hex, Color.WHITE) }
  fun setSecondaryTextColor(hex: String?) { adapter.secondaryTextColor = parseColor(hex, Color.LTGRAY) }
  fun setBorderColor(hex: String?) { adapter.borderColor = parseColor(hex, Color.TRANSPARENT) }
  fun setBackgroundColorHex(hex: String?) { adapter.backgroundColor = parseColor(hex, Color.TRANSPARENT) }

  private fun parseColor(raw: String?, fallback: Int): Int {
    if (raw.isNullOrBlank()) return fallback
    return runCatching { Color.parseColor(raw) }.getOrDefault(fallback)
  }
}

private data class EpisodeUi(
  val season: Int,
  val episode: Int,
  val title: String,
  val description: String,
  val progress: Int,
  val stillUrl: String?,
  val fallbackPosterUrl: String?,
  val tmdbRating: Double?,
  val imdbRating: Double?,
)

private class EpisodesAdapter(
  private val onEpisodePress: (EpisodeUi) -> Unit,
  private val onDownloadPress: (EpisodeUi) -> Unit,
) : RecyclerView.Adapter<EpisodesAdapter.VH>() {
  private val items = mutableListOf<EpisodeUi>()

  var textColor: Int = Color.WHITE
  var secondaryTextColor: Int = Color.LTGRAY
  var borderColor: Int = Color.TRANSPARENT
  var backgroundColor: Int = Color.TRANSPARENT

  fun submit(next: List<EpisodeUi>) {
    val diff = DiffUtil.calculateDiff(object : DiffUtil.Callback() {
      override fun getOldListSize() = items.size
      override fun getNewListSize() = next.size
      override fun areItemsTheSame(oldPos: Int, newPos: Int) =
        items[oldPos].season == next[newPos].season && items[oldPos].episode == next[newPos].episode
      override fun areContentsTheSame(oldPos: Int, newPos: Int) = items[oldPos] == next[newPos]
    })
    items.clear()
    items.addAll(next)
    diff.dispatchUpdatesTo(this)
  }

  override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): VH {
    val density = parent.resources.displayMetrics.density
    val dp = { v: Int -> (v * density).toInt() }

    val root = LinearLayout(parent.context).apply {
      orientation = LinearLayout.HORIZONTAL
      gravity = Gravity.TOP
      layoutParams = RecyclerView.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
        bottomMargin = dp(12)
      }
      // Match original look: row without card block background.
      setPadding(0, 0, 0, 0)
    }

    val imageWrap = FrameLayout(parent.context).apply {
      layoutParams = LinearLayout.LayoutParams(dp(148), dp(83))
      clipToOutline = true
      background = android.graphics.drawable.GradientDrawable().apply {
        cornerRadius = dp(10).toFloat()
        setColor(Color.parseColor("#20242b"))
      }
    }
    val image = AppCompatImageView(parent.context).apply {
      layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT)
      scaleType = ImageView.ScaleType.CENTER_CROP
      setBackgroundColor(Color.parseColor("#20242b"))
    }
    val progressBadge = TextView(parent.context).apply {
      layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
        gravity = Gravity.TOP or Gravity.START
        leftMargin = dp(6)
        topMargin = dp(6)
      }
      minWidth = dp(40)
      minHeight = dp(20)
      gravity = Gravity.CENTER
      setPadding(dp(8), dp(4), dp(8), dp(4))
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 10f)
      setTextColor(Color.WHITE)
      setTypeface(typeface, Typeface.BOLD)
      background = android.graphics.drawable.GradientDrawable().apply {
        cornerRadius = dp(8).toFloat()
        setColor(Color.parseColor("#B3000000"))
      }
      visibility = View.GONE
    }
    val playBadge = FrameLayout(parent.context).apply {
      layoutParams = FrameLayout.LayoutParams(dp(28), dp(28)).apply {
        gravity = Gravity.TOP or Gravity.END
        rightMargin = dp(6)
        topMargin = dp(6)
      }
      background = android.graphics.drawable.GradientDrawable().apply {
        shape = android.graphics.drawable.GradientDrawable.OVAL
        setColor(Color.parseColor("#99000000"))
      }
    }
    val playIcon = ImageView(parent.context).apply {
      layoutParams = FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER)
      setImageDrawable(AppCompatResources.getDrawable(parent.context, R.drawable.ic_lucide_play))
    }
    playBadge.addView(playIcon)
    val progressTrack = View(parent.context).apply {
      layoutParams = FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, dp(3), Gravity.BOTTOM)
      setBackgroundColor(Color.parseColor("#4DFFFFFF"))
    }
    val progressFill = View(parent.context).apply {
      layoutParams = FrameLayout.LayoutParams(0, dp(3), Gravity.BOTTOM or Gravity.START)
      setBackgroundColor(Color.parseColor("#FFFFFF"))
      visibility = View.GONE
    }
    imageWrap.addView(image)
    imageWrap.addView(progressBadge)
    imageWrap.addView(playBadge)
    imageWrap.addView(progressTrack)
    imageWrap.addView(progressFill)

    val info = LinearLayout(parent.context).apply {
      orientation = LinearLayout.VERTICAL
      layoutParams = LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f).apply {
        leftMargin = dp(12)
      }
    }
    val title = TextView(parent.context).apply {
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
      setTypeface(typeface, Typeface.BOLD)
      maxLines = 1
    }
    val meta = TextView(parent.context).apply {
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
      maxLines = 1
    }
    val description = TextView(parent.context).apply {
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
      maxLines = 2
    }
    val progress = TextView(parent.context).apply { visibility = View.GONE }
    info.addView(title)
    info.addView(meta)
    info.addView(description)
    info.addView(progress)

    val downloadWrap = FrameLayout(parent.context).apply {
      layoutParams = LinearLayout.LayoutParams(dp(32), dp(32)).apply {
        leftMargin = dp(8)
      }
      background = android.graphics.drawable.GradientDrawable().apply {
        shape = android.graphics.drawable.GradientDrawable.OVAL
        setColor(Color.TRANSPARENT)
      }
    }
    val downloadIcon = ImageView(parent.context).apply {
      layoutParams = FrameLayout.LayoutParams(dp(16), dp(16), Gravity.CENTER)
      setImageDrawable(AppCompatResources.getDrawable(parent.context, R.drawable.ic_lucide_download))
    }
    downloadWrap.addView(downloadIcon)

    downloadWrap.setOnClickListener {
      // Will be set in onBindViewHolder
    }
    root.addView(imageWrap)
    root.addView(info)
    root.addView(downloadWrap)
    return VH(root, imageWrap, image, progressBadge, progressFill, dp(148), title, meta, description, progress, downloadWrap, downloadIcon)
  }

  override fun onBindViewHolder(holder: VH, position: Int) {
    val item = items[position]
    holder.root.setOnClickListener { onEpisodePress(item) }
    holder.downloadWrap.setOnClickListener { onDownloadPress(item) }
    holder.root.background = null
    holder.title.setTextColor(textColor)
    holder.meta.setTextColor(secondaryTextColor)
    holder.description.setTextColor(secondaryTextColor)
    holder.progress.setTextColor(secondaryTextColor)
    holder.downloadIcon.setColorFilter(secondaryTextColor)
    (holder.downloadWrap.background as? android.graphics.drawable.GradientDrawable)?.apply {
      setStroke(1, borderColor)
    }

    val imageUrl = item.stillUrl ?: item.fallbackPosterUrl
    Glide.with(holder.image).clear(holder.image)
    holder.image.setImageDrawable(null)
    if (!imageUrl.isNullOrBlank()) {
      Glide.with(holder.image)
        .load(imageUrl)
        .diskCacheStrategy(DiskCacheStrategy.AUTOMATIC)
        .into(holder.image)
    }

    val rating = when {
      item.tmdbRating != null -> " · TMDB ${"%.1f".format(item.tmdbRating)}"
      item.imdbRating != null -> " · IMDb ${"%.1f".format(item.imdbRating)}"
      else -> ""
    }
    holder.title.text = "${item.episode}. ${item.title}"
    holder.meta.text = "S${item.season} · E${item.episode}$rating"
    holder.description.text = item.description
    if (item.progress > 0) {
      holder.progressBadge.text = "${item.progress}%"
      holder.progressBadge.visibility = View.VISIBLE
    } else {
      holder.progressBadge.visibility = View.GONE
    }
    val imageWidthPx = holder.imageWidthPx
    (holder.progressFill.layoutParams as FrameLayout.LayoutParams).width =
      ((imageWidthPx * item.progress) / 100.0).toInt().coerceAtLeast(0)
    holder.progressFill.requestLayout()
    holder.progressFill.visibility = if (item.progress > 0) View.VISIBLE else View.GONE
  }

  override fun getItemCount(): Int = items.size

  override fun onViewRecycled(holder: VH) {
    super.onViewRecycled(holder)
    Glide.with(holder.image).clear(holder.image)
    holder.image.setImageDrawable(null)
  }

  class VH(
    val root: LinearLayout,
    val imageWrap: FrameLayout,
    val image: AppCompatImageView,
    val progressBadge: TextView,
    val progressFill: View,
    val imageWidthPx: Int,
    val title: TextView,
    val meta: TextView,
    val description: TextView,
    val progress: TextView,
    val downloadWrap: FrameLayout,
    val downloadIcon: ImageView,
  ) : RecyclerView.ViewHolder(root)
}
