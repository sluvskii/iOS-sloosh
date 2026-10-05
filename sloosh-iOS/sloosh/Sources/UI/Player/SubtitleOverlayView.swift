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

        return VStack(spacing: 4) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: settings.fontSize.pointSize, weight: .medium, design: .default))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.black.opacity(0.72))
                    )
            }
        }
        .frame(maxWidth: min(geometry.size.width - 64, 760))
    }

    // MARK: - Responsive Padding

    private func effectiveBottomPadding(in geometry: GeometryProxy) -> CGFloat {
        let safeBottom = max(geometry.safeAreaInsets.bottom, 12)
        let zoomExtra: CGFloat = isZoomedToFill ? 8 : 0

        // В покое — аккуратно внизу экрана над Home Indicator (~24-28pt)
        // При показе контролов — плавно приподнимаем над таймлайном (+68pt)
        let basePadding = safeBottom + 10 + zoomExtra
        return showControls ? (basePadding + 68) : basePadding
    }
}
