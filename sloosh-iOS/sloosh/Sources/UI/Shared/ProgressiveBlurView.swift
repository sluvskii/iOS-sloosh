import SwiftUI

/// A native SwiftUI implementation of a progressive blur effect (Liquid Glass).
/// It uses an ultra-thin material masked with a linear gradient to create a smooth fade.
struct ProgressiveBlurView: View {
    var startColor: Color = .black
    var startOpacity: Double = 1.0
    var endOpacity: Double = 0.0
    
    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: startColor.opacity(startOpacity), location: 0.0),
                        .init(color: startColor.opacity(startOpacity * 0.8), location: 0.5),
                        .init(color: startColor.opacity(startOpacity * 0.3), location: 0.8),
                        .init(color: startColor.opacity(endOpacity), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea(edges: .top)
    }
}
