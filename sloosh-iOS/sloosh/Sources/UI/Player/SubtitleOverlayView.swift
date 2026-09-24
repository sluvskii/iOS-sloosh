import SwiftUI

/// Нативный оверлей субтитров в стиле Apple TV+
struct SubtitleOverlayView: View {
    let text: String
    let showControls: Bool
    var isZoomedToFill: Bool = false

    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .shadow(color: Color.black.opacity(0.9), radius: 2.5, x: 0, y: 1.5)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.72))
                )
                .padding(.horizontal, 28)
                .padding(.bottom, showControls ? 104 : 32)
                .animation(.spring(response: 0.32, dampingFraction: 0.85), value: showControls)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.12), value: text)
    }
}
