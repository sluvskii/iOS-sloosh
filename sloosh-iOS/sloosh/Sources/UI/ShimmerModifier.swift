import SwiftUI

struct ShimmerModifier: ViewModifier {
    let startDate = Date()

    func body(content: Content) -> some View {
        TimelineView(.animation) { timeline in
            content.visualEffect { content, proxy in
                content.colorEffect(
                    ShaderLibrary.shimmerEffect(
                        .float(timeline.date.timeIntervalSince(startDate)),
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
