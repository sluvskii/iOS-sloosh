import SwiftUI
import MediaPlayer

struct PlayerGesturesOverlay: View {
    @State private var showIndicator = false
    @State private var indicatorValue: Double = 0
    @State private var indicatorIcon: String = "sun.max.fill"
    
    // Начальные значения перед жестом
    @State private var initialBrightness: CGFloat = 0.0
    @State private var initialVolume: Float = 0.0
    @State private var isDragging: Bool = false
    
    private let volumeManager = VolumeManager.shared
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Невидимый слой для перехвата свайпов через UIKit
                PanGestureView { value in
                    handleDrag(value: value, height: geo.size.height)
                }
                
                // Центральный индикатор
                if showIndicator {
                    VStack(spacing: 12) {
                        Image(systemName: indicatorIcon)
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44) // Фиксируем размер иконки
                        
                        GeometryReader { barGeo in
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white)
                                        .frame(width: max(0, barGeo.size.width * indicatorValue))
                                }
                        }
                        .frame(width: 120, height: 4)
                    }
                    .padding(24)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .environment(\.colorScheme, .dark)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
        }
    }
    
    private func handleDrag(value: PanGestureData, height: CGFloat) {
        if value.state == .began {
            isDragging = true
            initialBrightness = UIScreen.main.brightness
            initialVolume = volumeManager.currentVolume
            return
        }
        
        if value.state == .ended || value.state == .cancelled {
            isDragging = false
            withAnimation {
                showIndicator = false
            }
            return
        }
        
        let delta = -value.translation.y / (height * 0.5) // Полный свайп на половину экрана
        let isRightSide = value.startLocation.x > UIScreen.main.bounds.width / 2
        
        if isRightSide {
            // Громкость
            let newVolume = max(0.0, min(1.0, Float(initialVolume) + Float(delta)))
            volumeManager.setVolume(newVolume)
            
            indicatorIcon = newVolume == 0 ? "speaker.slash.fill" : (newVolume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill")
            indicatorValue = Double(newVolume)
        } else {
            // Яркость
            let newBrightness = max(0.0, min(1.0, initialBrightness + delta))
            UIScreen.main.brightness = newBrightness
            
            indicatorIcon = newBrightness < 0.3 ? "sun.min.fill" : "sun.max.fill"
            indicatorValue = Double(newBrightness)
        }
        
        if !showIndicator {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                showIndicator = true
            }
        }
    }
}

// Данные о жесте
struct PanGestureData {
    let state: UIGestureRecognizer.State
    let translation: CGPoint
    let startLocation: CGPoint
}

// UIKit Gesture View, не блокирующий тапы
struct PanGestureView: UIViewRepresentable {
    var onPan: (PanGestureData) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.cancelsTouchesInView = false // Важно для пропуская тапов в плеер
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPan: onPan)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPan: (PanGestureData) -> Void
        var startLocation: CGPoint = .zero

        init(onPan: @escaping (PanGestureData) -> Void) {
            self.onPan = onPan
        }

        @objc func handlePan(_ recognizer: UIPanGestureRecognizer) {
            if recognizer.state == .began {
                startLocation = recognizer.location(in: recognizer.view)
            }
            
            let data = PanGestureData(
                state: recognizer.state,
                translation: recognizer.translation(in: recognizer.view),
                startLocation: startLocation
            )
            onPan(data)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}

final class VolumeManager {
    static let shared = VolumeManager()
    
    private var volumeSlider: UISlider?
    
    var currentVolume: Float {
        return volumeSlider?.value ?? 0.5
    }
    
    private init() {
        let volumeView = MPVolumeView(frame: .zero)
        volumeView.showsRouteButton = false
        // Ищем системный слайдер внутри MPVolumeView
        for view in volumeView.subviews {
            if let slider = view as? UISlider {
                self.volumeSlider = slider
                break
            }
        }
    }
    
    func setVolume(_ volume: Float) {
        DispatchQueue.main.async {
            self.volumeSlider?.value = volume
        }
    }
}
