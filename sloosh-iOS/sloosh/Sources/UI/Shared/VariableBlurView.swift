import SwiftUI

/// Создает эффект прогрессивного размытия (Liquid Glass),
/// плавно переходящего от полного блюра к полной прозрачности.
/// Безопасная для App Store реализация через градиентную маску.
public struct VariableBlurView: View {
    public var startPoint: UnitPoint = .top
    public var endPoint: UnitPoint = .bottom
    
    public init(startPoint: UnitPoint = .top, endPoint: UnitPoint = .bottom) {
        self.startPoint = startPoint
        self.endPoint = endPoint
    }
    
    public var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .black, location: 0.0),
                        .init(color: .black.opacity(0.8), location: 0.4),
                        .init(color: .black.opacity(0.4), location: 0.7),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: startPoint,
                    endPoint: endPoint
                )
            )
            .allowsHitTesting(false)
            .ignoresSafeArea()
    }
}
