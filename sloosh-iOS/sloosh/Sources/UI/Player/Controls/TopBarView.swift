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
    @State private var sharePlayTip = SharePlayTip()

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
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.65))
                    .blendMode(.plusLighter)
                    .frame(width: 44, height: 40)
            }

            divider

            // PiP
            if AVPictureInPictureController.isPictureInPictureSupported() {
                Button { vm.togglePiP() } label: {
                    Image(systemName: vm.isPiPActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                        .blendMode(.plusLighter)
                        .frame(width: 44, height: 40)
                }

                divider
            }

            // SharePlay
            Button { vm.startSharePlay() } label: {
                Image(systemName: "shareplay")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(vm.groupSession != nil ? Color.green : Color.white.opacity(0.65))
                    .blendMode(vm.groupSession != nil ? .normal : .plusLighter)
                    .frame(width: 44, height: 40)
            }
            .buttonStyle(NativeGlassButtonStyle())
            .popoverTip(sharePlayTip)

            divider

            // AirPlay (системная кнопка Apple)
            AirPlayButton()
                .frame(width: 44, height: 40)
                .colorMultiply(.white.opacity(0.65))
                .blendMode(.plusLighter)
        }
        .glassEffect(.regular, in: .capsule)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.2))
            .frame(width: 0.5, height: 22)
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
