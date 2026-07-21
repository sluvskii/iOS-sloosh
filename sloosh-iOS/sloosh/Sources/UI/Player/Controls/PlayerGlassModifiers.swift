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

public struct NativeGlassButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        // Prevents default opacity fade which breaks UIVisualEffectView blur
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
