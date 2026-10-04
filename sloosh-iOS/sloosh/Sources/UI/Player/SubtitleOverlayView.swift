import SwiftUI

/// Нативный оверлей субтитров в кинематографическом стиле (чистый текст без фоновых рамок)
struct SubtitleOverlayView: View {
    let text: String
    let showControls: Bool
    var isZoomedToFill: Bool = false
    var onTap: (() -> Void)? = nil

    @ObservedObject private var settings = SubtitleSettings.shared

    @State private var dragTranslation: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @State private var isDragging: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Полностью прозрачный фон без перехвата касаний
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)

                subtitleContent(in: geometry)
                    .offset(
                        x: effectiveX(in: geometry),
                        y: effectiveY(in: geometry)
                    )
                    .padding(.bottom, baseBottomPadding(in: geometry))
                    .animation(isDragging ? nil : .spring(response: 0.30, dampingFraction: 0.88), value: showControls)
                    .animation(isDragging ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: settings.customOffsetX)
                    .animation(isDragging ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: settings.customOffsetY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Subtitle Content View

    private func subtitleContent(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 3) {
            // Тонкий аккуратный индикатор только во время активного перемещения
            if isDragging {
                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: 24, height: 3)
                    .shadow(color: Color.black.opacity(0.85), radius: 2, x: 0, y: 1)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }

            Text(text)
                .font(.system(size: settings.fontSize.pointSize, weight: .semibold, design: .default))
                .tracking(0.2)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(3.5)
                // 360-градусный четкий контур для безупречной читаемости на любом фоне без подложки
                .shadow(color: Color.black.opacity(0.95), radius: 0.8, x: 0, y: 1)
                .shadow(color: Color.black.opacity(0.95), radius: 0.8, x: 0, y: -1)
                .shadow(color: Color.black.opacity(0.95), radius: 0.8, x: 1, y: 0)
                .shadow(color: Color.black.opacity(0.95), radius: 0.8, x: -1, y: 0)
                .shadow(color: Color.black.opacity(0.90), radius: 0.8, x: 0.7, y: 0.7)
                .shadow(color: Color.black.opacity(0.90), radius: 0.8, x: -0.7, y: 0.7)
                .shadow(color: Color.black.opacity(0.90), radius: 0.8, x: 0.7, y: -0.7)
                .shadow(color: Color.black.opacity(0.90), radius: 0.8, x: -0.7, y: -0.7)
                // Мягкие кинематографические тени для глубокого контраста
                .shadow(color: Color.black.opacity(0.85), radius: 3.5, x: 0, y: 1.5)
                .shadow(color: Color.black.opacity(0.60), radius: 8.0, x: 0, y: 3.0)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .frame(maxWidth: min(geometry.size.width - 120, 680))
                .fixedSize(horizontal: false, vertical: true)
        }
        .scaleEffect(isDragging ? 1.03 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        let startX = settings.hasCustomPosition ? settings.customOffsetX : 0
                        let startY: CGFloat
                        if settings.hasCustomPosition {
                            var y = settings.customOffsetY
                            if showControls && y > -36 { y -= 40 }
                            startY = y
                        } else {
                            startY = showControls ? -40 : 0
                        }
                        dragStartOffset = CGSize(width: startX, height: startY)
                        dragTranslation = .zero
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    dragTranslation = value.translation
                }
                .onEnded { value in
                    let finalX = clampX(dragStartOffset.width + value.translation.width, in: geometry)
                    let finalY = clampY(dragStartOffset.height + value.translation.height, in: geometry)

                    let defaultY: CGFloat = showControls ? -40 : 0
                    let isNearDefault = abs(finalX) < 24 && abs(finalY - defaultY) < 28

                    if isNearDefault {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            settings.resetPosition()
                            dragTranslation = .zero
                            dragStartOffset = .zero
                            isDragging = false
                        }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    } else {
                        let normalizedY = (showControls && finalY > -76) ? (finalY + 40) : finalY
                        settings.setCustomOffset(x: Double(finalX), y: Double(normalizedY))
                        dragTranslation = .zero
                        dragStartOffset = .zero
                        isDragging = false
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
        )
        .onTapGesture(count: 2) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                settings.resetPosition()
                dragTranslation = .zero
                dragStartOffset = .zero
            }
        }
        .onTapGesture(count: 1) {
            onTap?()
        }
        .animation(.easeInOut(duration: 0.12), value: text)
    }

    // MARK: - Position Calculations

    private func baseBottomPadding(in geometry: GeometryProxy) -> CGFloat {
        // Минимальный естественный отступ снизу над Home Indicator
        let safeBottom = max(geometry.safeAreaInsets.bottom, 10)
        return safeBottom + 6
    }

    private func effectiveX(in geometry: GeometryProxy) -> CGFloat {
        if isDragging {
            let rawX = dragStartOffset.width + dragTranslation.width
            return clampX(rawX, in: geometry)
        }
        if settings.hasCustomPosition {
            return clampX(settings.customOffsetX, in: geometry)
        }
        return 0
    }

    private func effectiveY(in geometry: GeometryProxy) -> CGFloat {
        if isDragging {
            let rawY = dragStartOffset.height + dragTranslation.height
            return clampY(rawY, in: geometry)
        }

        if settings.hasCustomPosition {
            var y = settings.customOffsetY
            // Если субтитры перетащены близко к нижней панели, аккуратно приподнимаем при показе контролов
            if showControls && y > -36 {
                y -= 40
            }
            return clampY(y, in: geometry)
        }

        // Стандартное адаптивное смещение: при показе контролов приподнимаем над полосой таймлайна (+40pt)
        return showControls ? -40 : 0
    }

    private func clampX(_ x: CGFloat, in geometry: GeometryProxy) -> CGFloat {
        let maxHorizontal = max(24, (geometry.size.width / 2.0) - 60)
        return min(maxHorizontal, max(-maxHorizontal, x))
    }

    private func clampY(_ y: CGFloat, in geometry: GeometryProxy) -> CGFloat {
        let topSafeArea = geometry.safeAreaInsets.top
        let maxTop = -(geometry.size.height - topSafeArea - 70)
        let maxBottom: CGFloat = 6.0
        return min(maxBottom, max(maxTop, y))
    }
}
