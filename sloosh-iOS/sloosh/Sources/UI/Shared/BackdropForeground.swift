import SwiftUI

/// Appearance policy shared by text on cinematic backdrops and variable-blur
/// headers. This is opt-in, never a global environment or card/content style.
struct BackdropForegroundAppearance {
    let opacity: Double
    let blendMode: BlendMode

    init(isDark: Bool, increasedContrast: Bool, reduceTransparency: Bool, opacity: Double) {
        let needsSolidForeground = increasedContrast || reduceTransparency
        self.opacity = needsSolidForeground ? 1 : (opacity.isFinite ? min(1, max(0, opacity)) : 0.9)
        self.blendMode = needsSolidForeground ? .normal : (isDark ? .plusLighter : .plusDarker)
    }
}

private struct BackdropForegroundModifier: ViewModifier {
    let opacity: Double
    let isEnabled: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if isEnabled {
            let isDark = colorScheme == .dark
            let appearance = BackdropForegroundAppearance(
                isDark: isDark,
                increasedContrast: contrast == .increased,
                reduceTransparency: reduceTransparency,
                opacity: opacity
            )
            content
                .foregroundStyle((isDark ? Color.white : Color.black).opacity(appearance.opacity))
                .blendMode(appearance.blendMode)
        } else {
            content
        }
    }
}

extension View {
    /// Use ONLY on neutral foreground text/symbols above changing content.
    /// Apply before any glass/background and never to whole screens, posters,
    /// brand logos, semantic colors, form fields or the Play cutout mask.
    func backdropForeground(opacity: Double = 0.9, isEnabled: Bool = true) -> some View {
        modifier(BackdropForegroundModifier(opacity: opacity, isEnabled: isEnabled))
    }
}
