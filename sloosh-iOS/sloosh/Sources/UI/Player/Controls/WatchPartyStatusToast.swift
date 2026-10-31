import SwiftUI

// MARK: - Watch Party Status Toast (Dynamic Island / Liquid Glass Style)

struct WatchPartyStatusToast: View {
    let message: String

    private var iconName: String {
        if message.contains("паузу") { return "pause.fill" }
        if message.contains("возобновил") { return "play.fill" }
        if message.contains("перемотал") { return "goforward" }
        if message.contains("серию") { return "rectangle.stack" }
        if message.contains("скорость") { return "gauge.with.dots.needle.bottom.50percent" }
        if message.contains("вышел") || message.contains("завершён") { return "xmark.circle" }
        if message.contains("Не удалось") { return "exclamationmark.circle" }
        return "shareplay"
    }

    private var iconColor: Color {
        if message.contains("вышел") || message.contains("завершён") || message.contains("Не удалось") {
            return Color.red
        }
        if message.contains("паузу") {
            return Color.orange
        }
        if message.contains("скорость") {
            return Color.cyan
        }
        return Color.green
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 6)
        .allowsHitTesting(false)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
