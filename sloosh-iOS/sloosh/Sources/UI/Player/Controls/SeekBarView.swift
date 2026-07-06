import SwiftUI

// MARK: - Seek Bar с нативным Liquid Glass (iOS 26)

struct SeekBarView: View {
    @ObservedObject var vm: PlayerViewModel
    @GestureState private var isDragging = false
    @State private var dragProgress: Double = 0

    private var progress: Double {
        guard vm.currentDuration > 0 else { return 0 }
        return isDragging ? dragProgress : (vm.currentTime / vm.currentDuration)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(formatTime(vm.currentTime))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 52, alignment: .leading)

            // Ползунок
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Фоновый трек
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .frame(height: 4)

                    // Буфер
                    Capsule()
                        .fill(.white.opacity(0.4))
                        .frame(width: geo.size.width * min(1, vm.bufferedProgress), height: 4)

                    // Прогресс
                    Capsule()
                        .fill(.white)
                        .frame(width: geo.size.width * progress, height: 4)

                    // Thumb
                    Capsule()
                        .fill(.white)
                        .frame(width: isDragging ? 32 : 28, height: isDragging ? 18 : 14)
                        .shadow(radius: isDragging ? 6 : 2)
                        .offset(x: geo.size.width * progress - (isDragging ? 16 : 14))
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .updating($isDragging) { _, state, _ in state = true }
                        .onChanged { value in
                            let newProgress = (value.location.x / geo.size.width).clamped(to: 0...1)
                            dragProgress = newProgress
                        }
                        .onEnded { value in
                            let newProgress = (value.location.x / geo.size.width).clamped(to: 0...1)
                            vm.seek(to: newProgress * vm.currentDuration)
                        }
                )
            }
            .frame(height: 18) // Fixes the GeometryReader from expanding to infinity vertically

            Text("-" + formatTime(max(0, vm.currentDuration - vm.currentTime)))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 56, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Liquid Glass — нативный iOS 26, без fallback
        .glassEffect(.regular, in: .capsule)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, !seconds.isNaN else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
