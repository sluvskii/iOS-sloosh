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
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .blendMode(.plusLighter)
                    .frame(width: 44, height: 40)
            }
            .popover(isPresented: $showSpeedSheet) {
                SpeedPickerSheet(vm: vm)
            }

            if vm.availableVoiceovers.count > 1 {
                divider
                Button { showVoiceoverSheet = true } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .blendMode(.plusLighter)
                        .frame(width: 44, height: 40)
                }
                .popover(isPresented: $showVoiceoverSheet) {
                    VoiceoverPickerSheet(vm: vm)
                }
            }

            if vm.availableQualities.count > 1 {
                divider
                Button { showQualitySheet = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .blendMode(.plusLighter)
                        .frame(width: 44, height: 40)
                }
                .popover(isPresented: $showQualitySheet) {
                    QualityPickerSheet(vm: vm)
                }
            }

            if !vm.availableSubtitles.isEmpty {
                divider
                Button { showSubtitleSheet = true } label: {
                    Image(systemName: vm.currentSubtitle != nil ? "text.bubble.fill" : "text.bubble")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .blendMode(.plusLighter)
                        .frame(width: 44, height: 40)
                }
                .popover(isPresented: $showSubtitleSheet) {
                    SubtitlePickerSheet(vm: vm)
                }
            }
        }
        .glassEffect(.regular, in: .capsule)
    }

    private var speedLabel: String {
        switch vm.playbackRate {
        case 1.0: return "1×"
        case 1.5: return "1.5×"
        case 2.0: return "2×"
        default:  return String(format: "%.2g×", vm.playbackRate)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 0.5, height: 22)
    }
}
