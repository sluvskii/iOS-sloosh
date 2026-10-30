import SwiftUI

// MARK: - Watch Party Status Toast (Dynamic Island / Liquid Glass Style)

struct WatchPartyStatusToast: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "shareplay")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)

            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 4)
        .allowsHitTesting(false)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
