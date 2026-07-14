import SwiftUI
import AVKit
import MediaPlayer

// MARK: - Наблюдатель за громкостью (class — корректно захватывает KVO)

final class VolumeObserver: ObservableObject {
    @Published var volume: Float = AVAudioSession.sharedInstance().outputVolume
    private var observation: NSKeyValueObservation?
    
    init() {
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.initial, .new]) { [weak self] session, _ in
            DispatchQueue.main.async {
                self?.volume = session.outputVolume
            }
        }
    }
    
    deinit { observation?.invalidate() }
}

// MARK: - Верхняя панель: [X | PiP | AirPlay]          [━━● ─] 🔊

struct TopBarView: View {
    @ObservedObject var vm: PlayerViewModel
    let onDismiss: () -> Void
    @Binding var isInteracting: Bool
    
    @StateObject private var volumeObserver = VolumeObserver()
    
    @State private var dragInitialVolume: Float = 0
    @State private var scrubStartLocationX: CGFloat = 0
    @State private var isVolumeScrubbing = false

    var body: some View {
        HStack(alignment: .center) {
            leftGroup
            Spacer()
            volumeGroup
        }
        .padding(.horizontal, 16)
    }

    // MARK: Левая группа: закрыть | PiP | AirPlay

    private var leftGroup: some View {
        HStack(spacing: 0) {
            // Закрыть
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 40)
            }

            divider

            // PiP
            if AVPictureInPictureController.isPictureInPictureSupported() {
                Button { vm.togglePiP() } label: {
                    Image(systemName: vm.isPiPActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 40)
                }

                divider
            }

            // AirPlay (системная кнопка Apple)
            AirPlayButton()
                .frame(width: 44, height: 40)
        }
        .glassEffect(.regular, in: .capsule)
    }

    // MARK: Правая группа: громкость

    @ViewBuilder
    private var volumeGroup: some View {
        HStack(spacing: 6) {
            CustomVolumeSlider(observer: volumeObserver)
                .frame(width: 100, height: 4)

            Image(systemName: volumeIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 18)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) && !isVolumeScrubbing {
                        return
                    }
                    if !isVolumeScrubbing {
                        isVolumeScrubbing = true
                        dragInitialVolume = volumeObserver.volume
                        scrubStartLocationX = value.startLocation.x
                        isInteracting = true
                    }
                    
                    let trackWidth = 100.0 + 6.0 + 18.0 + 28.0 // Примерная ширина всей капсулы (100 + spacing + icon + padding)
                    let startX = max(1, min(trackWidth - 1, scrubStartLocationX))
                    
                    let thumbX = Double(dragInitialVolume) * Double(trackWidth)
                    let distanceToThumb = abs(Double(startX) - thumbX)
                    
                    let speedFactor = 1.0 + (distanceToThumb / Double(trackWidth)) * 5.0
                    let baseMultiplier = 1.0 / Double(trackWidth) // Макс громкость = 1.0
                    
                    let deltaVol = Double(value.translation.width) * baseMultiplier * speedFactor
                    let newVol = Float(max(0, min(1.0, Double(dragInitialVolume) + deltaVol)))
                    VolumeManager.shared.setVolume(newVol)
                    volumeObserver.volume = newVol
                }
                .onEnded { value in
                    guard isVolumeScrubbing else { return }
                    isVolumeScrubbing = false
                    isInteracting = false
                }
        )
    }

    private var volumeIcon: String {
        let vol = volumeObserver.volume
        if vol == 0 { return "speaker.slash.fill" }
        else if vol < 0.33 { return "speaker.wave.1.fill" }
        else if vol < 0.66 { return "speaker.wave.2.fill" }
        else { return "speaker.wave.3.fill" }
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

// MARK: - Системный слайдер громкости

struct CustomVolumeSlider: View {
    @ObservedObject var observer: VolumeObserver
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                Capsule()
                    .fill(Color.white)
                    .frame(width: max(0, geo.size.width * CGFloat(observer.volume)))
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let percent = max(0, min(1, value.location.x / geo.size.width))
                        VolumeManager.shared.setVolume(Float(percent))
                        observer.volume = Float(percent)
                    }
            )
        }
    }
}
