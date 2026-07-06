import SwiftUI

// MARK: - Общий стиль для picker-шторок

private struct PickerSheetStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .presentationDetents([.medium, .fraction(0.4)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.ultraThinMaterial)
    }
}

// MARK: - Выбор озвучки

struct VoiceoverPickerSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.availableVoiceovers, id: \.self) { name in
                    Button {
                        vm.switchVoiceover(to: name)
                        dismiss()
                    } label: {
                        HStack {
                            Text(name)
                                .foregroundStyle(.primary)
                            Spacer()
                            if vm.currentTranslationName == name {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Озвучка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .modifier(PickerSheetStyle())
    }
}

// MARK: - Выбор качества

struct QualityPickerSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(vm.availableQualities, id: \.key) { quality in
                    Button {
                        vm.changeQuality(to: quality.key)
                        dismiss()
                    } label: {
                        HStack {
                            Text(quality.key)
                                .foregroundStyle(.primary)
                            Spacer()
                            if vm.currentQualityKey == quality.key {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Качество")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .modifier(PickerSheetStyle())
    }
}

// MARK: - Выбор скорости

struct SpeedPickerSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        NavigationStack {
            List {
                ForEach(speeds, id: \.self) { speed in
                    Button {
                        vm.setPlaybackRate(speed)
                        dismiss()
                    } label: {
                        HStack {
                            Text(speedLabel(speed))
                                .foregroundStyle(.primary)
                            Spacer()
                            if vm.playbackRate == speed {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Скорость")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .modifier(PickerSheetStyle())
    }

    private func speedLabel(_ speed: Float) -> String {
        switch speed {
        case 0.5: return "0.5× — Медленно"
        case 0.75: return "0.75×"
        case 1.0: return "1× — Нормально"
        case 1.25: return "1.25×"
        case 1.5: return "1.5× — Быстро"
        case 2.0: return "2× — Очень быстро"
        default: return String(format: "%.2g×", speed)
        }
    }
}

// MARK: - Выбор субтитров

struct SubtitlePickerSheet: View {
    @ObservedObject var vm: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Выключить субтитры
                Button {
                    vm.setSubtitle(nil)
                    dismiss()
                } label: {
                    HStack {
                        Text("Выключить")
                            .foregroundStyle(.primary)
                        Spacer()
                        if vm.currentSubtitle == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .fontWeight(.semibold)
                        }
                    }
                }

                ForEach(vm.availableSubtitles, id: \.url) { sub in
                    Button {
                        vm.setSubtitle(sub)
                        dismiss()
                    } label: {
                        HStack {
                            Text(sub.label)
                                .foregroundStyle(.primary)
                            Spacer()
                            if vm.currentSubtitle?.url == sub.url {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Субтитры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
        .modifier(PickerSheetStyle())
    }
}
