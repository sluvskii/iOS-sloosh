package com.neo.neomovies.core

import android.app.Dialog
import androidx.appcompat.app.AlertDialog
import android.os.Bundle
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.fragment.app.DialogFragment
import androidx.lifecycle.ViewModelProvider
import androidx.media3.common.C
import android.widget.Toast

class TrackSelectionDialogFragment : DialogFragment() {

    companion object {
        private const val ARG_TRACK_TYPE = "track_type"

        fun newInstance(type: @C.TrackType Int): TrackSelectionDialogFragment {
            return TrackSelectionDialogFragment().apply {
                arguments = Bundle().apply {
                    putInt(ARG_TRACK_TYPE, type)
                }
            }
        }
    }

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val type = requireArguments().getInt(ARG_TRACK_TYPE)
        val viewModel = ViewModelProvider(requireActivity())[PlayerViewModel::class.java]

        val titleRes =
            when (type) {
                C.TRACK_TYPE_AUDIO -> R.string.select_audio_track
                C.TRACK_TYPE_TEXT -> R.string.select_subtitle_track
                C.TRACK_TYPE_VIDEO -> R.string.select_video_quality
                else -> error("TrackType must be AUDIO, TEXT or VIDEO")
            }

        val tracks = viewModel.getSelectableTracks(type)
        val trackItems = tracks.map { t -> if (t.isSupported) t.label else "${t.label} (unsupported)" }
        val hasNoneOption = type == C.TRACK_TYPE_TEXT
        val hasAutoOption = type == C.TRACK_TYPE_VIDEO
        val prefix = when {
            hasNoneOption -> listOf(getString(R.string.none))
            hasAutoOption -> listOf("Auto")
            else -> emptyList()
        }
        val items = (prefix + trackItems).toTypedArray()

        val selectedTrackIndex = tracks.indexOfFirst { it.isSelected }
        val checked = when {
            hasNoneOption -> if (selectedTrackIndex >= 0) selectedTrackIndex + 1 else 0
            hasAutoOption -> if (viewModel.isVideoQualityAutoPreferred()) 0 else if (selectedTrackIndex >= 0) selectedTrackIndex + 1 else 0
            else -> if (selectedTrackIndex >= 0) selectedTrackIndex else 0
        }

        return requireActivity().let { activity ->
            AlertDialog.Builder(activity)
                .setTitle(titleRes)
                .setSingleChoiceItems(
                    items,
                    checked,
                ) { dialog, which ->
                    if (hasNoneOption && which == 0) {
                        viewModel.switchToTrack(type, -1)
                        dialog.dismiss()
                        return@setSingleChoiceItems
                    }

                    if (hasAutoOption && which == 0) {
                        viewModel.switchToTrack(type, -1)
                        dialog.dismiss()
                        return@setSingleChoiceItems
                    }

                    val trackIndex = if (hasNoneOption || hasAutoOption) which - 1 else which
                    val selected = tracks.getOrNull(trackIndex)
                    if (selected == null) return@setSingleChoiceItems

                    if (!selected.isSupported) {
                        Toast.makeText(activity, "Track is not supported by ExoPlayer on this device", Toast.LENGTH_SHORT)
                            .show()
                        return@setSingleChoiceItems
                    }

                    viewModel.switchToTrack(type, trackIndex)
                    dialog.dismiss()
                }
                .create()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        activity?.window?.let {
            WindowCompat.getInsetsController(it, it.decorView).apply {
                systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                hide(WindowInsetsCompat.Type.systemBars())
            }
        }
    }
}
