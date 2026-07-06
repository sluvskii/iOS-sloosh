import SwiftUI

// MARK: - Seek Bar с нативным Liquid Glass (iOS 26)

struct SeekBarView: View {
    @ObservedObject var vm: PlayerViewModel
    @Binding var isInteracting: Bool
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    @State private var isHStackScrubbing = false
    @State private var screenScrubInitialTime: Double = 0
    @State private var scrubStartLocationX: CGFloat = 0

    private var progress: Double {
        guard vm.currentDuration > 0 else { return 0 }
        if let scrub = vm.screenScrubTime { return scrub / vm.currentDuration }
        return isDragging ? dragProgress : (vm.currentTime / vm.currentDuration)
    }

    private var displayTime: Double {
        if let scrub = vm.screenScrubTime { return scrub }
        return isDragging ? (dragProgress * vm.currentDuration) : vm.currentTime
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(formatTime(displayTime))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)

            // Чистый SwiftUI слайдер для динамической толщины
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.25))
                        .frame(height: isHStackScrubbing ? 8 : 4)

                    Capsule()
                        .fill(.white)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * progress)),
                               height: isHStackScrubbing ? 8 : 4)
                }
                .frame(maxHeight: .infinity)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHStackScrubbing)
            }
            .frame(height: 24)

            Text("-" + formatTime(max(0, vm.currentDuration - displayTime)))
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Liquid Glass — нативный iOS 26, без fallback
        .glassEffect(.regular, in: .capsule)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if abs(value.translation.height) > abs(value.translation.width) && !isHStackScrubbing {
                        return
                    }
                    if !isHStackScrubbing {
                        isHStackScrubbing = true
                        screenScrubInitialTime = vm.currentTime
                        scrubStartLocationX = value.startLocation.x
                        isInteracting = true
                    }
                    
                    let trackWidth = UIScreen.main.bounds.width - 32 // Примерная ширина рабочей области
                    let startX = max(1, min(trackWidth - 1, scrubStartLocationX))
                    
                    let thumbX = (screenScrubInitialTime / vm.currentDuration) * Double(trackWidth)
                    let distanceToThumb = abs(Double(startX) - thumbX)
                    
                    // Чем дальше тап от ползунка, тем быстрее свайп (до 6 раз быстрее)
                    let speedFactor = 1.0 + (distanceToThumb / Double(trackWidth)) * 5.0
                    
                    let baseMultiplier = vm.currentDuration / Double(trackWidth)
                    let deltaSeconds = Double(value.translation.width) * baseMultiplier * speedFactor
                    
                    vm.screenScrubTime = max(0, min(vm.currentDuration, screenScrubInitialTime + deltaSeconds))
                }
                .onEnded { value in
                    guard isHStackScrubbing else { return }
                    isHStackScrubbing = false
                    isInteracting = false
                    
                    // Если это был просто тап (не тянули), прыгаем в точку касания
                    if value.translation.width == 0 {
                        let trackWidth = UIScreen.main.bounds.width - 32
                        let tapX = max(0, min(trackWidth, value.startLocation.x))
                        vm.seek(to: (Double(tapX) / Double(trackWidth)) * vm.currentDuration)
                        vm.screenScrubTime = nil
                        return
                    }
                    
                    if let target = vm.screenScrubTime {
                        vm.seek(to: target)
                        vm.screenScrubTime = nil
                    }
                }
        )
        .onChange(of: isDragging) { _, dragging in
            if dragging { isInteracting = true }
            else if !isHStackScrubbing { isInteracting = false }
        }
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
