import SwiftUI
import AVKit
import MediaPlayer

// MARK: - Верхняя панель: закрыть | PiP | AirPlay          громкость

struct TopBarView: View {
    @ObservedObject var vm: PlayerViewModel
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            // Левая группа: закрыть + PiP + AirPlay
            leftGroup

            Spacer()

            // Правая группа: громкость
            volumeControl
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: Left group

    @ViewBuilder
    private var leftGroup: some View {
        HStack(spacing: 0) {
            // Закрыть
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
            }

            Divider()
                .frame(width: 0.5, height: 24)
                .background(.white.opacity(0.25))
                .padding(.horizontal, 4)

            // PiP
            if AVPictureInPictureController.isPictureInPictureSupported() {
                Button {
                    vm.togglePiP()
                } label: {
                    Image(systemName: vm.isPiPActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                }

                Divider()
                    .frame(width: 0.5, height: 24)
                    .background(.white.opacity(0.25))
                    .padding(.horizontal, 4)
            }

            // AirPlay (системная кнопка)
            AirPlayButton()
                .frame(width: 40, height: 40)
        }
        .modifier(GlassGroupModifier())
    }

    // MARK: Volume

    @ViewBuilder
    private var volumeControl: some View {
        HStack(spacing: 10) {
            SystemVolumeSlider()
                .frame(width: 160, height: 20)

            Image(systemName: volumeIconName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 20)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(GlassCapsuleModifier())
    }

    private var volumeIconName: String {
        let vol = AVAudioSession.sharedInstance().outputVolume
        if vol == 0 { return "speaker.slash.fill" }
        else if vol < 0.33 { return "speaker.wave.1.fill" }
        else if vol < 0.66 { return "speaker.wave.2.fill" }
        else { return "speaker.wave.3.fill" }
    }
}

// MARK: - AirPlay button (UIViewRepresentable)

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.tintColor = .white
        view.activeTintColor = UIColor.systemBlue
        view.prioritizesVideoDevices = true
        return view
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

// MARK: - Системный слайдер громкости (MPVolumeView)

struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        view.showsRouteButton = false
        // Красим thumb и трек в белый
        view.tintColor = .white
        return view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - Glass modifiers

struct GlassGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
                )
        }
    }
}

struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .capsule)
        } else {
            content
                .background(
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                        .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
                )
        }
    }
}
