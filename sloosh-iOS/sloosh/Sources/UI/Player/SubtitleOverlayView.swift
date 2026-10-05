import SwiftUI

/// Нативный оверлей субтитров в кинематографическом стиле (чистый текст, без рамок, без размытых теней и без перехвата касаний)
struct SubtitleOverlayView: View {
    let text: String
    let showControls: Bool
    var isZoomedToFill: Bool = false

    @ObservedObject private var settings = SubtitleSettings.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Прозрачный фоновый контейнер
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(text)
                    .font(.system(size: settings.fontSize.pointSize, weight: .semibold, design: .default))
                    .tracking(0.2)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3.5)
                    // Аккуратная тонкая тень для четкости без гигантского размытого ореола
                    .shadow(color: Color.black.opacity(0.95), radius: 1.0, x: 0, y: 1)
                    .shadow(color: Color.black.opacity(0.60), radius: 1.5, x: 0, y: 1.5)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: min(geometry.size.width - 96, 720))
                    .padding(.bottom, effectiveBottomPadding(in: geometry))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showControls)
        .animation(.easeInOut(duration: 0.12), value: text)
    }

    // MARK: - Responsive Padding

    private func effectiveBottomPadding(in geometry: GeometryProxy) -> CGFloat {
        let safeBottom = max(geometry.safeAreaInsets.bottom, 12)
        let zoomExtra: CGFloat = isZoomedToFill ? 8 : 0

        // В покое — аккуратно внизу экрана над Home Indicator (~28pt)
        // При показе контролов — плавно приподнимаем над таймлайном (+76pt)
        let basePadding = safeBottom + 12 + zoomExtra
        return showControls ? (basePadding + 76) : basePadding
    }
}
