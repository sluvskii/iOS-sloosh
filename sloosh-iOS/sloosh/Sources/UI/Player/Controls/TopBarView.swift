import SwiftUI
import AVKit
import MediaPlayer
import TipKit

// MARK: - Верхняя панель: [X | PiP | AirPlay]          [━━● ─] 🔊

struct TopBarView: View {
    @ObservedObject var vm: PlayerViewModel
    let onDismiss: () -> Void
    @Binding var isInteracting: Bool
    
    // Tips

    var body: some View {
        HStack(alignment: .center) {
            leftGroup
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    // MARK: Левая группа: закрыть | PiP | AirPlay

    private var leftGroup: some View {
        HStack(spacing: 0) {
            // Закрыть
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .blendMode(.plusLighter)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.glassPress)
            .accessibilityLabel("Закрыть плеер")

            // PiP
            if AVPictureInPictureController.isPictureInPictureSupported() {
                Button { vm.togglePiP() } label: {
                    Image(systemName: vm.isPiPActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .blendMode(.plusLighter)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.glassPress)
                .accessibilityLabel(vm.isPiPActive ? "Выйти из режима картинка в картинке" : "Картинка в картинке")
            }

            // AirPlay (системная кнопка Apple)
            AirPlayButton()
                .frame(width: 44, height: 44)
                .colorMultiply(.white.opacity(0.75))
                .blendMode(.plusLighter)
        }
        .padding(.horizontal, 2)
        .frame(height: 44)
        .clipShape(Capsule())
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

// MARK: - AirPlay — нативная кнопка Apple

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor.systemBlue
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
