import SwiftUI
import MediaPlayer

struct PlayerGesturesModifier: ViewModifier {
    var onInteractionBegan: (() -> Void)?
    var onInteractionEnded: (() -> Void)?
    var onHoldBegan: (() -> Void)?
    var onHoldEnded: (() -> Void)?
    
    @State private var showIndicator = false
    @State private var indicatorValue: Double = 0
    @State private var indicatorIcon: String = "sun.max.fill"
    
    // Начальные значения перед жестом
    @State private var initialBrightness: CGFloat = 0.0
    @State private var initialVolume: Float = 0.0
    @State private var isDragging: Bool = false
    @State private var isHolding: Bool = false
    @State private var draggingSide: TapSide? = nil
    @State private var hideTask: Task<Void, Never>?
    @State private var holdTask: Task<Void, Never>?
    
    enum TapSide { case left, right }
    
    private let volumeManager = VolumeManager.shared
    
    @GestureState private var isDetectingLongPress = false

    func body(content: Content) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                content
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 15)
                            .onChanged { value in
                                holdTask?.cancel()
                                holdTask = nil
                                if isHolding {
                                    isHolding = false
                                    onHoldEnded?()
                                }
                                hideTask?.cancel()
                                hideTask = nil
                                
                                if !isDragging {
                                    isDragging = true
                                    onInteractionBegan?()
                                    let screen = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen
                                    initialBrightness = screen?.brightness ?? 0.5
                                    initialVolume = volumeManager.currentVolume
                                    draggingSide = value.startLocation.x > (screen?.bounds.width ?? 393) / 2 ? .right : .left
                                }
                                handleDrag(value: value, height: geo.size.height)
                            }
                            .onEnded { _ in
                                isDragging = false
                                if isHolding {
                                    isHolding = false
                                    onHoldEnded?()
                                }
                                onInteractionEnded?()
                                
                                hideTask?.cancel()
                                hideTask = Task {
                                    try? await Task.sleep(for: .seconds(1.0))
                                    guard !Task.isCancelled else { return }
                                    await MainActor.run {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                            showIndicator = false
                                        }
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.35)
                            .updating($isDetectingLongPress) { currentState, gestureState, _ in
                                gestureState = currentState
                            }
                    )
                    .onChange(of: isDetectingLongPress) { _, isDetecting in
                        if isDetecting && !isDragging {
                            isHolding = true
                            onHoldBegan?()
                        } else if !isDetecting && isHolding {
                            isHolding = false
                            onHoldEnded?()
                        }
                    }
                
                // Верхний индикатор (подобен системному), только для яркости (левая сторона)
                if showIndicator && draggingSide == .left {
                    HStack(spacing: 12) {
                        Image(systemName: indicatorIcon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 24)
                        
                        GeometryReader { barGeo in
                            Capsule()
                                .fill(Color.white.opacity(0.3))
                                .overlay(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white)
                                        .frame(width: max(0, barGeo.size.width * indicatorValue))
                                }
                        }
                        .frame(height: 5)
                    }
                    .padding(.horizontal, 16)
                    .frame(width: 180, height: 40)
                    .glassEffect(.regular, in: .capsule)
                    .environment(\.colorScheme, .dark)
                    .padding(.top, 24)
                    .transition(.asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.95)),
                        removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.8))
                    ))
                }
            }
        }
    }
    
    private func handleDrag(value: DragGesture.Value, height: CGFloat) {
        let delta = -value.translation.height / (height * 0.5) // Полный свайп на половину экрана
        let isRightSide = draggingSide == .right
        
        if isRightSide {
            // Громкость (система сама показывает свой ползунок сверху, так как мы меняем MPVolumeView slider программно)
            let newVolume = max(0.0, min(1.0, Float(initialVolume) + Float(delta)))
            volumeManager.setVolume(newVolume)
            
            // Для громкости наш кастомный UI больше не показываем
            if showIndicator {
                withAnimation { showIndicator = false }
            }
        } else {
            // Яркость
            let newBrightness = max(0.0, min(1.0, initialBrightness + delta))
            (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.screen.brightness = newBrightness
            
            indicatorIcon = newBrightness < 0.3 ? "sun.min.fill" : "sun.max.fill"
            indicatorValue = Double(newBrightness)
            
            if !showIndicator {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showIndicator = true
                }
            }
        }
    }
}

extension View {
    func playerGestures(
        onInteractionBegan: (() -> Void)? = nil,
        onInteractionEnded: (() -> Void)? = nil,
        onHoldBegan: (() -> Void)? = nil,
        onHoldEnded: (() -> Void)? = nil
    ) -> some View {
        self.modifier(PlayerGesturesModifier(
            onInteractionBegan: onInteractionBegan,
            onInteractionEnded: onInteractionEnded,
            onHoldBegan: onHoldBegan,
            onHoldEnded: onHoldEnded
        ))
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
