import SwiftUI

// MARK: - Шторки выбора озвучки, качества, скорости, субтитров

// MARK: Озвучка
struct VoiceoverPickerSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PopoverContainer(title: "Озвучка") {
            ForEach(vm.availableVoiceovers, id: \.self) { name in
                popoverRow(
                    label: name,
                    isSelected: vm.currentTranslationName == name
                ) {
                    vm.switchVoiceover(to: name)
                    dismiss()
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
        PopoverContainer(title: "Качество") {
            ForEach(vm.availableQualities, id: \.key) { q in
                popoverRow(
                    label: q.key,
                    isSelected: vm.currentQualityKey == q.key
                ) {
                    vm.changeQuality(to: q.key)
                    dismiss()
                }
            }
        }
    }
}

// MARK: Скорость
struct SpeedPickerSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.5, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        PopoverContainer(title: "Скорость") {
            ForEach(speeds, id: \.self) { rate in
                popoverRow(
                    label: rateLabel(rate),
                    isSelected: vm.playbackRate == rate
                ) {
                    vm.setPlaybackRate(rate)
                    dismiss()
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
        PopoverContainer(title: "Субтитры") {
            popoverRow(label: "Без субтитров", isSelected: vm.currentSubtitle == nil) {
                vm.setSubtitle(nil)
                dismiss()
            }
            ForEach(vm.availableSubtitles, id: \.url) { sub in
                popoverRow(
                    label: sub.label,
                    isSelected: vm.currentSubtitle?.url == sub.url
                ) {
                    vm.setSubtitle(sub)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Вспомогательные View

private struct PopoverContainer<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .padding(.bottom, 4)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 8) {
                    content
                }
            }
        }
        .padding(16)
        .frame(minWidth: 260, maxWidth: 450)
        // Принудительно открываем как Popover даже на iPhone
        .presentationCompactAdaptation(.popover)
        .preferredColorScheme(.dark)
    }
}

@ViewBuilder
private func popoverRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(label)
            .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
            .foregroundStyle(isSelected ? .black : .white)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(
                Capsule()
                    .fill(isSelected ? Color.white : Color.white.opacity(0.15))
            )
    }
    .buttonStyle(.plain)
}
