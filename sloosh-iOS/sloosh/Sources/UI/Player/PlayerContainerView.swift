import SwiftUI
import AVKit

// MARK: - Главный контейнер плеера

struct PlayerContainerView: View {
    @ObservedObject var vm: PlayerViewModel
    let onDismiss: () -> Void

    @State private var showControls = true
    @State private var pipController: AVPictureInPictureController?
    @State private var hideTask: Task<Void, Never>?
    @State private var seekFeedback: SeekFeedback?
    @State private var isInteracting = false
    @State private var lastLeftTap: Date = .distantPast
    @State private var lastRightTap: Date = .distantPast
    @State private var isZoomedToFill = false

    struct SeekFeedback: Identifiable {
        let id = UUID()
        let isForward: Bool
    }

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
            }

            // 5. Жесты (двойной тап = перемотка, одинарный = контролы)
            gestureLayer

            // 6. Seek feedback
            if let feedback = seekFeedback {
                SeekFeedbackView(isForward: feedback.isForward)
                    .id(feedback.id)
                    .allowsHitTesting(false)
            }

            // 7. Контролы
            PlayerControlsView(vm: vm, onDismiss: onDismiss, isInteracting: $isInteracting, showControls: showControls)
                .blur(radius: showControls ? 0 : 20)
                .opacity(showControls ? 1 : 0)
                .allowsHitTesting(showControls)
        }
        .onAppear { scheduleAutoHide() }
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
    
    private let showAnimation: Animation = .easeInOut(duration: 0.35)
    private let hideAnimation: Animation = .easeOut(duration: 0.5)

    // MARK: - Gesture layer

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            // Левая половина — -10с
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    vm.seek(by: -10)
                    showSeekFeedback(forward: false)
                    withAnimation(showAnimation) { showControls = true }
                    resetHideTimer()
                }
                .onTapGesture(count: 1) {
                    toggleControls()
                }

            // Правая половина — +10с
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    vm.seek(by: 10)
                    showSeekFeedback(forward: true)
                    withAnimation(showAnimation) { showControls = true }
                    resetHideTimer()
                }
                .onTapGesture(count: 1) {
                    toggleControls()
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
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, vm.isPlaying, !isInteracting else { return }
            withAnimation(hideAnimation) { showControls = false }
        }
    }

    func resetHideTimer() {
        if !showControls { withAnimation(showAnimation) { showControls = true } }
        scheduleAutoHide()
    }

    // MARK: - Seek feedback

    private func showSeekFeedback(forward: Bool) {
        seekFeedback = SeekFeedback(isForward: forward)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            seekFeedback = nil
        }
    }
}

// MARK: - Seek ripple

private struct SeekFeedbackView: View {
    let isForward: Bool
    @State private var isVisible: Bool = false

    var body: some View {
        HStack {
            if isForward { Spacer() }
            Image(systemName: isForward ? "goforward.10" : "gobackward.10")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .glassEffect(.regular, in: .circle)
                .scaleEffect(isVisible ? 1.0 : 0.95)
                .blur(radius: isVisible ? 0 : 20)
                .opacity(isVisible ? 1 : 0)
                .onAppear {
                    withAnimation(.easeOut(duration: 0.2)) { isVisible = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.25)) { isVisible = false }
                    }
                }
            if !isForward { Spacer() }
        }
        .padding(.horizontal, 40)
    }
}
