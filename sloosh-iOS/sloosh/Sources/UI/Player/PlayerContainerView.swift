import SwiftUI
import AVKit

// MARK: - Главный контейнер плеера

struct PlayerContainerView: View {
    @ObservedObject var vm: PlayerViewModel
    let onDismiss: () -> Void

    @State private var showControls = true
    @State private var pipController: AVPictureInPictureController?
    @State private var hideTask: Task<Void, Never>?
    @State private var isInteracting = false
    @State private var isPopoverOpen = false
    @State private var isZoomedToFill = false
    @State private var tapTask: Task<Void, Never>?
    @State private var consecutiveTaps: Int = 0
    @State private var activeTapSide: TapSide? = nil
    @State private var multiSeekSeconds: Int? = nil
    @State private var initialSeekTime: Double = 0

    enum TapSide { case left, right }

    var body: some View {
        ZStack {
            // 1. Чёрный фон
            Color.black.ignoresSafeArea()

            // 2. Видеослой
            VideoLayerView(player: vm.player, pipController: $pipController, videoGravity: isZoomedToFill ? .resizeAspectFill : .resizeAspect)
                .ignoresSafeArea(edges: isZoomedToFill ? .all : .vertical)
                .onAppear { vm.pipController = pipController }
                .onChange(of: pipController) { _, newVal in vm.pipController = newVal }

            // 3. (Буферизация перенесена в саму кнопку Play)

            // 4. Ошибка (показываем поверх видео, скрываем всё остальное)
            if let error = vm.error {
                errorView(error)
                    .zIndex(10)
            } else {
                // 5. Жесты (двойной тап = перемотка, одинарный = контролы)
                gestureLayer

                // 6. Multi-tap Seek feedback
                MultiSeekFeedbackView(side: activeTapSide, seconds: multiSeekSeconds)
                    .allowsHitTesting(false)

                // 7. Контролы
                let isSeeking = multiSeekSeconds != nil || isInteracting
                PlayerControlsView(vm: vm, onDismiss: onDismiss, isInteracting: $isInteracting, isPopoverOpen: $isPopoverOpen, showControls: showControls, isSeeking: isSeeking)
                    .blur(radius: showControls ? 0 : 20)
                    .opacity(showControls ? 1 : 0)
                    .allowsHitTesting(showControls)
            }
        }
        .onAppear { scheduleAutoHide() }
        .onDisappear { hideTask?.cancel() }
        .onChange(of: vm.isPlaying) { _, _ in
            if vm.isPlaying { scheduleAutoHide() }
        }
        .onChange(of: isInteracting) { _, interacting in
            if interacting {
                hideTask?.cancel()
            } else if showControls && !isPopoverOpen {
                scheduleAutoHide()
            }
        }
        .onChange(of: isPopoverOpen) { _, open in
            if open {
                hideTask?.cancel()
            } else if showControls && !isInteracting {
                scheduleAutoHide()
            }
        }
        .gesture(
            MagnificationGesture()
                .onEnded { val in
                    if !isZoomedToFill && val > 1.25 {
                        withAnimation(showAnimation) { isZoomedToFill = true }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else if isZoomedToFill && val < 0.85 {
                        withAnimation(showAnimation) { isZoomedToFill = false }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }
        )
    }
    
    private let showAnimation: Animation = .easeInOut(duration: 0.15)
    private let hideAnimation: Animation = .easeOut(duration: 0.25)

    // MARK: - Gesture layer

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            // Левая половина — -10с
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { handleTap(side: .left) }

            // Правая половина — +10с
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { handleTap(side: .right) }
        }
        .playerGestures(
            onInteractionBegan: {
                withAnimation(hideAnimation) { showControls = false }
            }
        )
    }

    private func handleTap(side: TapSide) {
        tapTask?.cancel()
        
        if activeTapSide != side {
            consecutiveTaps = 0
            activeTapSide = side
            multiSeekSeconds = nil
            initialSeekTime = vm.currentTime
        }
        
        consecutiveTaps += 1
        let currentTaps = consecutiveTaps
        
        if currentTaps == 1 {
            tapTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                
                self.consecutiveTaps = 0
                self.activeTapSide = nil
                self.toggleControls()
            }
        } else {
            let seconds = 10
            let direction = (side == .right) ? 1.0 : -1.0
            
            let totalSeconds = (currentTaps - 1) * seconds
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                self.multiSeekSeconds = totalSeconds
            }
            
            let targetTime = initialSeekTime + Double(totalSeconds) * direction
            vm.screenScrubTime = max(0, min(vm.currentDuration, targetTime))
            
            if showControls {
                scheduleAutoHide()
            }
            
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
            tapTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                
                if let finalScrubTime = vm.screenScrubTime {
                    vm.seek(to: finalScrubTime)
                    vm.screenScrubTime = nil
                }
                
                self.consecutiveTaps = 0
                withAnimation(.easeOut(duration: 0.4)) {
                    self.activeTapSide = nil
                    self.multiSeekSeconds = nil
                }
            }
        }
    }

    // MARK: - Error view

    private func errorView(_ error: String) -> some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.orange)
                
                Text("Ошибка воспроизведения")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                
                Text(error)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                HStack(spacing: 12) {
                    Button("Закрыть") {
                        vm.cleanup()
                        onDismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .buttonStyle(NativeGlassButtonStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)
                    
                    Button("Попробовать снова") {
                        vm.retryPlayback()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .buttonStyle(NativeGlassButtonStyle())
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
        }
    }

    // MARK: - Auto-hide

    private func toggleControls() {
        if showControls {
            withAnimation(hideAnimation) { showControls = false }
            hideTask?.cancel()
        } else {
            withAnimation(showAnimation) { showControls = true }
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled, vm.isPlaying, !isInteracting else { return }
            withAnimation(hideAnimation) { showControls = false }
        }
    }

    func resetHideTimer() {
        if !showControls { withAnimation(showAnimation) { showControls = true } }
        scheduleAutoHide()
    }

}

// MARK: - Seek ripple transitions

private struct BlurTransitionModifier: ViewModifier {
    let isActive: Bool
    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 0 : 1)
            .blur(radius: isActive ? 20 : 0)
            .scaleEffect(isActive ? 1.2 : 1.0)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(
            active: BlurTransitionModifier(isActive: true),
            identity: BlurTransitionModifier(isActive: false)
        )
    }
}

private struct MultiSeekFeedbackView: View {
    let side: PlayerContainerView.TapSide?
    let seconds: Int?

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            
            ZStack {
                if let sec = seconds, let s = side {
                    HStack(spacing: 0) {
                        if s == .right { Spacer(minLength: 0) }
                        
                        ZStack {
                            // Плавный прогрессивный блюр с градиентом
                            VariableBlurView(
                                maxBlurRadius: 6,
                                direction: s == .left ? .blurredLeadingClearTrailing : .blurredTrailingClearLeading,
                                tintColor: .black,
                                tintOpacity: 0.35
                            )
                            .transition(.opacity)
                            
                            VStack(spacing: 12) {
                                Image(systemName: s == .left ? "gobackward" : "goforward")
                                    .font(.system(size: 32, weight: .medium))
                                
                                Text("\(sec) сек")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .contentTransition(.numericText(value: Double(sec)))
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: sec)
                            }
                            .foregroundStyle(.white.opacity(0.65))
                            .blendMode(.plusLighter)
                            .offset(x: s == .left ? -15 : 15)
                            .transition(.blurFade)
                        }
                        .frame(width: width * 0.45) // Чуть шире для более плавного градиента
                        
                        if s == .left { Spacer(minLength: 0) }
                    }
                    .id(s) // Предотвращаем анимацию перемещения с одной стороны на другую
                }
            }
        }
        .ignoresSafeArea() // Полностью игнорируем челку/островки для плотного прилегания
    }
}
