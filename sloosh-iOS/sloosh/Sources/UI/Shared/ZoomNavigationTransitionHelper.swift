import SwiftUI

private struct OptionalZoomNavigationTransitionModifier: ViewModifier {
    let sourceID: String?
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let sourceID, let namespace {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

private struct OptionalCardZoomTransitionSourceModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID?
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if let namespace {
            content
                .geometryGroup()
                .matchedTransitionSource(id: id, in: namespace) { configuration in
                    configuration
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
        } else {
            content
        }
    }
}

extension View {
    /// Groups card geometry and applies a unified rounded clip shape for zoom transitions
    /// so source snapshots never tear or leak transparent background gaps on dismiss.
    func cardZoomTransitionSource(
        id: String,
        in namespace: Namespace.ID,
        cornerRadius: CGFloat = 12
    ) -> some View {
        geometryGroup()
            .matchedTransitionSource(id: id, in: namespace) { configuration in
                configuration
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
    }

    /// Conditionally attaches `cardZoomTransitionSource` when an owning namespace is provided.
    func optionalCardZoomTransitionSource(
        id: String,
        in namespace: Namespace.ID?,
        cornerRadius: CGFloat = 14
    ) -> some View {
        modifier(OptionalCardZoomTransitionSourceModifier(id: id, namespace: namespace, cornerRadius: cornerRadius))
    }

    /// Conditionally enables SwiftUI `.zoom` navigation transitions when both source ID and namespace are present.
    func optionalZoomNavigationTransition(
        sourceID: String?,
        in namespace: Namespace.ID?
    ) -> some View {
        modifier(OptionalZoomNavigationTransitionModifier(sourceID: sourceID, namespace: namespace))
    }
}
