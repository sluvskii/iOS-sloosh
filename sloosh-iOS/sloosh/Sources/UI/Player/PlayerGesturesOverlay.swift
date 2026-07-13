import SwiftUI
import MediaPlayer

struct PlayerGesturesModifier: ViewModifier {
    @State private var showIndicator = false
    @State private var indicatorValue: Double = 0
    @State private var indicatorIcon: String = "sun.max.fill"
    
    // Начальные значения перед жестом
    @State private var initialBrightness: CGFloat = 0.0
    @State private var initialVolume: Float = 0.0
    @State private var isDragging: Bool = false
    
    private let volumeManager = VolumeManager.shared
    
    func body(content: Content) -> some View {
        GeometryReader { geo in
            ZStack {
                // Передаем весь контент (например, gestureLayer с тапами), 
                // и параллельно перехватываем свайпы без блокировки тапов!
                content
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 15)
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    initialBrightness = UIScreen.main.brightness
                                    initialVolume = volumeManager.currentVolume
                                }
                                handleDrag(value: value, height: geo.size.height)
                            }
                            .onEnded { _ in
                                isDragging = false
                                withAnimation(.easeOut(duration: 0.3)) {
                                    showIndicator = false
                                }
                            }
                    )
                
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
    
    private func handleDrag(value: DragGesture.Value, height: CGFloat) {
        let delta = -value.translation.height / (height * 0.5) // Полный свайп на половину экрана
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

extension View {
    func playerGestures() -> some View {
        self.modifier(PlayerGesturesModifier())
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
