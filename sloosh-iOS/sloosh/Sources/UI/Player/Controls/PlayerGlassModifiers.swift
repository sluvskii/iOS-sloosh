import SwiftUI
import AVKit

// MARK: - Общие glass-примитивы для всего плеера
// iOS 26 minimum deployment target — .glassEffect() доступен без #available

/// Круглая glass-кнопка (Liquid Glass)
struct GlassCircleEffect: ViewModifier {
    let diameter: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: diameter, height: diameter)
            .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// Капсульная glass-панель (Liquid Glass)
struct GlassCapsuleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: .capsule)
    }
}

/// Glass-группа (для набора кнопок в одной панели)
struct GlassGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .glassEffect(.regular, in: .capsule)
    }
}

/// ButtonStyle для любых glass-кнопок без изменения прозрачности при нажатии
struct GlassPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassPressButtonStyle {
    static var glassPress: GlassPressButtonStyle { GlassPressButtonStyle() }
}

