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
    @State private var overrideVolume: Float? = nil
    @State private var isVolumeDragging = false

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
        HStack(spacing: 8) {
            Image(systemName: volumeIcon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
            
            LiquidSliderView(
                value: Binding(
                    get: { Double(overrideVolume ?? volumeObserver.volume) },
                    set: { overrideVolume = Float($0) }
                ),
                isDragging: $isVolumeDragging
            )
            .frame(height: 24)

            // Невидимый системный слайдер для фактического изменения громкости системы
            SystemVolumeSlider(overrideVolume: $overrideVolume)
                .frame(width: 0, height: 0)
                .opacity(0)
        }
        .frame(width: 80) // Сделали компактнее (было 100)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .onChange(of: isVolumeDragging) { _, dragging in
            if dragging { isInteracting = true }
        }
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

struct SystemVolumeSlider: UIViewRepresentable {
    @Binding var overrideVolume: Float?

    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView()
        // Скрываем кнопку AirPlay — она уже есть отдельно
        v.subviews
            .compactMap { $0 as? UIButton }
            .forEach { $0.isHidden = true }
        
        // Убираем кружок-ползунок
        v.setVolumeThumbImage(UIImage(), for: .normal)
        
        v.tintColor = .white
        return v
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        if let vol = overrideVolume {
            if let slider = uiView.subviews.first(where: { $0 is UISlider }) as? UISlider {
                slider.value = vol
            }
            DispatchQueue.main.async {
                self.overrideVolume = nil
            }
        }
    }
}
