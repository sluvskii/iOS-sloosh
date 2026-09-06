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
        ZStack {
            // Логотип проекта или название фильма строго по центру
            centerLogoView
                .padding(.horizontal, 148)
                .allowsHitTesting(false)

            // Левая группа: закрыть + (PiP | AirPlay)
            HStack(alignment: .center, spacing: 8) {
                closeButton
                dualActionsGroup
                Spacer()
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - Логотип / Название по центру

    private var centerLogoView: some View {
        Group {
            if let logoUrl = vm.displayLogoUrl {
                AsyncCachedImage(url: logoUrl) {
                    fallbackTextView
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 36)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                } fallback: {
                    fallbackTextView
                }
            } else {
                fallbackTextView
            }
        }
        .frame(maxWidth: 240)
    }

    private var fallbackTextView: some View {
        Text(vm.fallbackTitle)
            .font(.system(size: 15, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .blendMode(.plusLighter)
            .lineLimit(1)
            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
    }

    // MARK: - Отдельная кнопка «Закрыть» (нативная круглая иконка как в окне шеринга)

    private var closeButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.glassPress)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Закрыть плеер")
    }

    // MARK: - Двойная капсула: PiP + AirPlay

    private var dualActionsGroup: some View {
        HStack(spacing: 0) {
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
