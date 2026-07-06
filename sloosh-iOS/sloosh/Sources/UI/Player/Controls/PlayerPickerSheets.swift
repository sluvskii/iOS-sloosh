import SwiftUI

// MARK: - Шторки выбора озвучки, качества, скорости, субтитров

// MARK: Озвучка
struct VoiceoverPickerSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.availableVoiceovers, id: \.self) { name in
                    pickerRow(
                        label: name,
                        isSelected: vm.currentTranslationName == name
                    ) {
                        vm.switchVoiceover(to: name)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Озвучка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

// MARK: Качество
struct QualityPickerSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.availableQualities, id: \.key) { q in
                    pickerRow(
                        label: q.key,
                        isSelected: vm.currentQualityKey == q.key
                    ) {
                        vm.changeQuality(to: q.key)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Качество")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

// MARK: Скорость
struct SpeedPickerSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        NavigationStack {
            List {
                ForEach(speeds, id: \.self) { rate in
                    pickerRow(
                        label: rateLabel(rate),
                        isSelected: vm.playbackRate == rate
                    ) {
                        vm.setPlaybackRate(rate)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Скорость")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1.0 ? "Обычная (1×)" : String(format: "%.2g×", rate)
    }
}

// MARK: Субтитры
struct SubtitlePickerSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                pickerRow(label: "Без субтитров", isSelected: vm.currentSubtitle == nil) {
                    vm.setSubtitle(nil)
                    dismiss()
                }
                ForEach(vm.availableSubtitles, id: \.url) { sub in
                    pickerRow(
                        label: sub.label,
                        isSelected: vm.currentSubtitle?.url == sub.url
                    ) {
                        vm.setSubtitle(sub)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Субтитры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Вспомогательная строка пикера

@ViewBuilder
private func pickerRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        HStack {
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .fontWeight(.semibold)
            }
        }
    }
}
