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
            // Скорость воспроизведения
            Button {
                showSpeedSheet = true
            } label: {
                speedLabel
                    .frame(width: 44, height: 40)
            }

            if vm.availableVoiceovers.count > 1 {
                divider
                // Озвучка
                Button {
                    showVoiceoverSheet = true
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 40)
                }
            }

            if vm.availableQualities.count > 1 {
                divider
                // Качество
                Button {
                    showQualitySheet = true
                } label: {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 40)
                }
            }

            if !vm.availableSubtitles.isEmpty {
                divider
                // Субтитры
                Button {
                    showSubtitleSheet = true
                } label: {
                    Image(systemName: vm.currentSubtitle != nil ? "text.bubble.fill" : "text.bubble")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 40)
                }
            }
        }
        .modifier(GlassCapsuleModifier())
    }

    @ViewBuilder
    private var speedLabel: some View {
        let label = vm.playbackRate == 1.0 ? "1×" :
                    vm.playbackRate == 1.5 ? "1.5×" :
                    vm.playbackRate == 2.0 ? "2×" :
                    String(format: "%.2g×", vm.playbackRate)
        Text(label)
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 0.5, height: 24)
    }
}
