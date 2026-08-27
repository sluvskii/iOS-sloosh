import SwiftUI

struct ShimmerModifier: ViewModifier {
    nonisolated(unsafe) private static let referenceDate = Date()

    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            let date = timeline.date
            content.visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.shimmerEffect(
                        .float(date.timeIntervalSince(Self.referenceDate)),
                        .float2(proxy.size)
                    )
                )
            }
        }
    }
}

extension View {
    func shimmer() -> some View {
        self.modifier(ShimmerModifier())
    }
}
