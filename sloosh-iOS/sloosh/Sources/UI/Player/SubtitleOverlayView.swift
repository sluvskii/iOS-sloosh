import SwiftUI

/// Нативный оверлей субтитров в эталонном стиле iOS (Apple TV / Safari / AVKit)
/// Каждая строка реплики обрамлена в аккуратную полупрозрачную черную плашку со скругленными углами
struct SubtitleOverlayView: View {
    let text: String
    let showControls: Bool
    var isZoomedToFill: Bool = false

    @ObservedObject private var settings = SubtitleSettings.shared

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Прозрачный контейнер на весь экран без перехвата касаний
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                subtitleLinesView(in: geometry)
                    .padding(.bottom, effectiveBottomPadding(in: geometry))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: showControls)
        .animation(.easeInOut(duration: 0.12), value: text)
        .animation(.easeInOut(duration: 0.15), value: settings.fontSize)
    }

    // MARK: - Subtitle Lines (Эталонный нативный вид iOS)

    private func subtitleLinesView(in geometry: GeometryProxy) -> some View {
        let lines = text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let horizontalSafe = max(geometry.safeAreaInsets.leading, geometry.safeAreaInsets.trailing) * 2
        let maxSubtitleWidth = min(geometry.size.width - max(horizontalSafe + 32, 64), 760)

        return VStack(spacing: 3) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: settings.fontSize.pointSize, weight: .medium, design: .default))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.black.opacity(0.72))
                    )
            }
        }
        .frame(maxWidth: maxSubtitleWidth)
    }

    // MARK: - Responsive Padding

    private func effectiveBottomPadding(in geometry: GeometryProxy) -> CGFloat {
        let safeBottom = geometry.safeAreaInsets.bottom
        let zoomExtra: CGFloat = isZoomedToFill ? 4 : 0

        // В покое: аккуратно прямо над Home Indicator (21 + 3 = 24pt на iPhone, 10pt на iPad)
        let basePadding: CGFloat = (safeBottom > 0 ? (safeBottom + 3) : 10) + zoomExtra

        // При показе контролов: плавно приподнимаем над таймлайном (~68-70pt)
        let controlsPadding: CGFloat = max(basePadding + 44, 68)

        return showControls ? controlsPadding : basePadding
    }
}
