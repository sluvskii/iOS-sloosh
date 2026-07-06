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

    struct SeekFeedback: Identifiable {
        let id = UUID()
        let isForward: Bool
    }

    var body: some View {
        ZStack {
            // 1. Чёрный фон
            Color.black.ignoresSafeArea()

            // 2. Видеослой
            VideoLayerView(player: vm.player, pipController: $pipController)
                .ignoresSafeArea()
                .onAppear { vm.pipController = pipController }
                .onChange(of: pipController) { _, newVal in vm.pipController = newVal }

            // 3. Буферизация
            if vm.isBuffering && !vm.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.4)
            }

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
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // 7. Контролы
            if showControls {
                PlayerControlsView(vm: vm, onDismiss: onDismiss, isInteracting: $isInteracting)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showControls)
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
    }

    // MARK: - Gesture layer

    private var gestureLayer: some View {
        HStack(spacing: 0) {
            // Левая половина — -10с
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    vm.seek(by: -10)
                    showSeekFeedback(forward: false)
                    resetHideTimer()
                }
                .onTapGesture(count: 1) { toggleControls() }

            // Правая половина — +10с
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    vm.seek(by: 10)
                    showSeekFeedback(forward: true)
                    resetHideTimer()
                }
                .onTapGesture(count: 1) { toggleControls() }
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
        withAnimation { showControls.toggle() }
        if showControls { scheduleAutoHide() } else { hideTask?.cancel() }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled, vm.isPlaying, !isInteracting else { return }
            withAnimation { showControls = false }
        }
    }

    func resetHideTimer() {
        if !showControls { withAnimation { showControls = true } }
        scheduleAutoHide()
    }

    // MARK: - Seek feedback

    private func showSeekFeedback(forward: Bool) {
        withAnimation { seekFeedback = SeekFeedback(isForward: forward) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
            withAnimation { seekFeedback = nil }
        }
    }
}

// MARK: - Seek ripple

private struct SeekFeedbackView: View {
    let isForward: Bool
    @State private var scale: CGFloat = 0.7
    @State private var opacity: Double = 1.0

    var body: some View {
        HStack {
            if isForward { Spacer() }
            Image(systemName: isForward ? "goforward.10" : "gobackward.10")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                // Liquid Glass капсула вместо кастомного кружка
                .glassEffect(.regular, in: .circle)
                .scaleEffect(scale)
                .opacity(opacity)
                .onAppear {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                        scale = 1.0
                    }
                    withAnimation(.easeOut(duration: 0.28).delay(0.32)) {
                        opacity = 0
                    }
                }
            if !isForward { Spacer() }
        }
        .padding(.horizontal, 40)
    }
}
