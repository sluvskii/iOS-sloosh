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
    @State private var isZoomedToFill = false
    @State private var tapTask: Task<Void, Never>?
    @State private var consecutiveTaps: Int = 0
    @State private var activeTapSide: TapSide? = nil
    @State private var multiSeekSeconds: Int? = nil

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

            // 4. Ошибка
            if let error = vm.error {
                errorView(error)
                    .zIndex(10)
            }

            // 5. Жесты (двойной тап = перемотка, одинарный = контролы)
            gestureLayer

            // 6. Multi-tap Seek feedback
            if let seconds = multiSeekSeconds, let side = activeTapSide {
                MultiSeekFeedbackView(side: side, seconds: seconds)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            // 7. Контролы
            PlayerControlsView(vm: vm, onDismiss: onDismiss, isInteracting: $isInteracting, showControls: showControls)
                .blur(radius: showControls ? 0 : 20)
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
        }
        .onAppear { scheduleAutoHide() }
        .onDisappear { hideTask?.cancel() }
        .onChange(of: vm.isPlaying) { _, _ in
            if vm.isPlaying { scheduleAutoHide() }
        }
        .onChange(of: isInteracting) { _, interacting in
            if interacting {
                hideTask?.cancel()
            } else if showControls {
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
    }

    private func handleTap(side: TapSide) {
        tapTask?.cancel()
        
        if activeTapSide != side {
            consecutiveTaps = 0
            activeTapSide = side
            multiSeekSeconds = nil
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
            vm.seek(by: Double(seconds) * direction)
            
            let totalSeconds = (currentTaps - 1) * seconds
            withAnimation(.easeOut(duration: 0.15)) {
                self.multiSeekSeconds = totalSeconds
            }
            
            resetHideTimer()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            
            tapTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                
                self.consecutiveTaps = 0
                self.activeTapSide = nil
                withAnimation(.easeOut(duration: 0.3)) {
                    self.multiSeekSeconds = nil
                }
            }
        }
    }

    // MARK: - Error view

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.red)
            Text(error)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Закрыть") {
                vm.cleanup()
                onDismiss()
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .glassEffect(.regular.interactive(), in: .capsule)
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

// MARK: - Seek ripple

private struct MultiSeekFeedbackView: View {
    let side: PlayerContainerView.TapSide
    let seconds: Int
    @State private var isVisible = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            HStack(spacing: 0) {
                if side == .right { Spacer(minLength: 0) }
                
                ZStack {
                    // Progressive blur using a soft radial gradient mask
                    Rectangle()
                        .fill(.regularMaterial)
                        .mask(
                            RadialGradient(
                                gradient: Gradient(colors: [.black.opacity(0.8), .clear]),
                                center: side == .left ? .leading : .trailing,
                                startRadius: width * 0.05,
                                endRadius: width * 0.35
                            )
                        )
                    
                    VStack(spacing: 12) {
                        Image(systemName: side == .left ? "gobackward" : "goforward")
                            .font(.system(size: 32, weight: .medium))
                        
                        Text("\(seconds) сек")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .contentTransition(.numericText(value: Double(seconds)))
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: seconds)
                    }
                    .foregroundStyle(.white)
                    // Смещение контента немного к краю экрана для лучшего баланса
                    .offset(x: side == .left ? -20 : 20)
                }
                .frame(width: width * 0.4) // 40% of the screen
                .opacity(isVisible ? 1 : 0)
                .ignoresSafeArea()
                
                if side == .left { Spacer(minLength: 0) }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) { isVisible = true }
        }
    }
}
