import SwiftUI

// MARK: - Нижняя правая панель: скорость | озвучка | качество | субтитры

struct BottomRowView: View {
    @ObservedObject var vm: PlayerViewModel
    @Binding var showVoiceoverSheet: Bool
    @Binding var showQualitySheet: Bool
    @Binding var showSpeedSheet: Bool
    @Binding var showSubtitleSheet: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Скорость
            Button { showSpeedSheet = true } label: {
                Text(speedLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .blendMode(.plusLighter)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.glassPress)
            .accessibilityLabel("Скорость воспроизведения: \(speedLabel)")
            .popover(isPresented: $showSpeedSheet) {
                SpeedPickerSheet(vm: vm)
            }

            if vm.availableVoiceovers.count > 1 {
                Button { showVoiceoverSheet = true } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .blendMode(.plusLighter)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.glassPress)
                .accessibilityLabel("Озвучка")
                .popover(isPresented: $showVoiceoverSheet) {
                    VoiceoverPickerSheet(vm: vm)
                }
            }

            if vm.availableQualities.count > 1 {
                Button { showQualitySheet = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .blendMode(.plusLighter)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.glassPress)
                .accessibilityLabel("Качество видео")
                .popover(isPresented: $showQualitySheet) {
                    QualityPickerSheet(vm: vm)
                }
            }

            if !vm.availableSubtitles.isEmpty {
                Button { showSubtitleSheet = true } label: {
                    Image(systemName: vm.currentSubtitle != nil ? "text.bubble.fill" : "text.bubble")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .blendMode(.plusLighter)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.glassPress)
                .accessibilityLabel(vm.currentSubtitle != nil ? "Субтитры (включены)" : "Субтитры")
                .popover(isPresented: $showSubtitleSheet) {
                    SubtitlePickerSheet(vm: vm)
                }
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 44)
        .clipShape(Capsule())
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var speedLabel: String {
        switch vm.playbackRate {
        case 1.0: return "1×"
        case 1.5: return "1.5×"
        case 2.0: return "2×"
        default:  return String(format: "%.2g×", vm.playbackRate)
        }
    }
}
