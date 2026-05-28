import SwiftUI

struct WatchSelectorChip: View {
    let title: String
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(isSelected ? (colorScheme == .dark ? Color.black : Color.white) : (isAvailable ? Color.primary : Color.secondary))
        }
        .background(
            Capsule()
                .fill(isSelected ? Color.primary : (isAvailable ? (colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.9)) : (colorScheme == .dark ? Color(white: 0.15) : Color(white: 0.95))))
        )
        .opacity(isAvailable ? 1.0 : 0.6)
        .buttonStyle(ChipButtonStyle())
    }
}
