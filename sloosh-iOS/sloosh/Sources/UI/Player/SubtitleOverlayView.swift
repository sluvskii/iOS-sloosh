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
                .font(.system(size: 21, weight: .semibold, design: .default))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .shadow(color: Color.black.opacity(1.0), radius: 0, x: 1, y: 1)
                .shadow(color: Color.black.opacity(1.0), radius: 0, x: -1, y: -1)
                .shadow(color: Color.black.opacity(0.95), radius: 3, x: 0, y: 2)
                .padding(.horizontal, 20)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.55))
                )
                .padding(.horizontal, 32)
                .padding(.bottom, showControls ? 108 : 36)
                .animation(.spring(response: 0.30, dampingFraction: 0.88), value: showControls)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.10), value: text)
    }
}
