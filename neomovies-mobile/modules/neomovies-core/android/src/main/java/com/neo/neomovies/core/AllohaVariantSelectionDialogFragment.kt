package com.neo.neomovies.core

import android.app.Dialog
import android.os.Bundle
import androidx.appcompat.app.AlertDialog
import androidx.fragment.app.DialogFragment
import androidx.fragment.app.activityViewModels

class AllohaVariantSelectionDialogFragment : DialogFragment() {

    private val viewModel: PlayerViewModel by activityViewModels()

    override fun onCreateDialog(savedInstanceState: Bundle?): Dialog {
        val type = arguments?.getString(ARG_TYPE) ?: TYPE_AUDIO

        return if (type == TYPE_AUDIO) {
            val variants = viewModel.getAllohaAudioVariants()
            val labels = variants.map { it["title"] ?: "Unknown" }.toTypedArray()
            val selected = variants.indexOfFirst { it["selected"] == "true" }.coerceAtLeast(0)
            AlertDialog.Builder(requireContext())
                .setTitle(getString(R.string.alloha_sheet_audio))
                .setSingleChoiceItems(labels, selected) { dialog, which ->
                    dialog.dismiss()
                    val index = variants[which]["index"]?.toIntOrNull() ?: which
                    viewModel.selectAllohaAudioVariant(index)
                }
                .create()
        } else {
            val variants = viewModel.getAllohaQualityVariants()
            val labels = variants.map { it["label"] ?: "Unknown" }.toTypedArray()
            val selected = variants.indexOfFirst { it["selected"] == "true" }.coerceAtLeast(0)
            AlertDialog.Builder(requireContext())
                .setTitle(getString(R.string.alloha_sheet_quality))
                .setSingleChoiceItems(labels, selected) { dialog, which ->
                    dialog.dismiss()
                    val index = variants[which]["index"]?.toIntOrNull() ?: which
                    if (index == -1) viewModel.selectAllohaAutoQuality()
                    else viewModel.selectAllohaQualityVariant(index)
                }
                .create()
        }
    }

    companion object {
        private const val ARG_TYPE = "type"
        const val TYPE_AUDIO = "audio"
        const val TYPE_QUALITY = "quality"

        fun newInstance(type: String) = AllohaVariantSelectionDialogFragment().apply {
            arguments = Bundle().apply { putString(ARG_TYPE, type) }
        }
    }
}
