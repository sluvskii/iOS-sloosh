import SwiftUI

/// Нативный оверлей субтитров в кинематографическом стиле с поддержкой свободного перемещения
struct SubtitleOverlayView: View {
    let text: String
    let showControls: Bool
    var isZoomedToFill: Bool = false
    var onTap: (() -> Void)? = nil

    @ObservedObject private var settings = SubtitleSettings.shared

    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Полностью прозрачный фон без перехвата нажатий вне плашки субтитров
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                subtitlePlatter(in: geometry)
                    .offset(
                        x: effectiveOffsetX(in: geometry),
                        y: effectiveOffsetY(in: geometry)
                    )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Platter View

    private func subtitlePlatter(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 3) {
            // Индикатор перемещения и кнопка сброса
            if showControls || isDragging {
                HStack(spacing: 8) {
                    Capsule()
                        .fill(Color.white.opacity(isDragging ? 0.75 : 0.35))
                        .frame(width: 24, height: 3)

                    if settings.hasCustomPosition {
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                settings.resetPosition()
                                dragTranslation = .zero
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white.opacity(0.80))
                        }
                        .buttonStyle(.plain)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.top, 3)
                .transition(.opacity)
            }

            Text(text)
                .font(.system(size: settings.fontSize.pointSize, weight: .semibold, design: .default))
                .tracking(0.25)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .shadow(color: Color.black.opacity(0.95), radius: 1.5, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.80), radius: 6, x: 0, y: 2)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 2)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.62))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isDragging ? Color.white.opacity(0.40) : Color.white.opacity(0.09),
                            lineWidth: isDragging ? 1.5 : 0.75
                        )
                )
                .shadow(color: Color.black.opacity(0.35), radius: 8, x: 0, y: 4)
        )
        .frame(maxWidth: min(geometry.size.width - 64, 760))
        .scaleEffect(isDragging ? 1.025 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    dragTranslation = value.translation
                }
                .onEnded { value in
                    isDragging = false
                    let newX = clampX(settings.customOffsetX + value.translation.width, in: geometry)
                    let newY = clampY(settings.customOffsetY + value.translation.height, in: geometry)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        settings.setCustomOffset(x: newX, y: newY)
                        dragTranslation = .zero
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
        )
        .onTapGesture(count: 2) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                settings.resetPosition()
                dragTranslation = .zero
            }
        }
        .onTapGesture(count: 1) {
            onTap?()
        }
        .animation(.easeInOut(duration: 0.12), value: text)
        .animation(.easeInOut(duration: 0.20), value: showControls)
    }

    // MARK: - Offset Calculations

    private func effectiveOffsetX(in geometry: GeometryProxy) -> CGFloat {
        if isDragging {
            return clampX(settings.customOffsetX + dragTranslation.width, in: geometry)
        }
        return clampX(settings.customOffsetX, in: geometry)
    }

    private func effectiveOffsetY(in geometry: GeometryProxy) -> CGFloat {
        if isDragging {
            let targetY = settings.customOffsetY + dragTranslation.height
            return clampY(targetY, in: geometry)
        }

        if settings.hasCustomPosition {
            var y = settings.customOffsetY
            // Если субтитры перетащены близко к нижней панели, аккуратно приподнимаем при показе контролов
            if showControls && y > -75 {
                y -= 48
            }
            return clampY(y, in: geometry)
        }

        // Стандартное адаптивное положение
        let zoomExtra: CGFloat = isZoomedToFill ? 8 : 0
        let baseBottom = showControls ? -(104 + zoomExtra) : -(34 + zoomExtra)
        return baseBottom
    }

    private func clampX(_ x: CGFloat, in geometry: GeometryProxy) -> CGFloat {
        let halfWidth = geometry.size.width / 2.0
        let margin: CGFloat = 60.0
        let limit = max(40.0, halfWidth - margin)
        return min(limit, max(-limit, x))
    }

    private func clampY(_ y: CGFloat, in geometry: GeometryProxy) -> CGFloat {
        let screenHeight = geometry.size.height
        let topLimit = -(screenHeight - 80.0) // граница сверху у верхнего бара
        let bottomLimit: CGFloat = 15.0       // граница снизу
        return min(bottomLimit, max(topLimit, y))
    }
}
