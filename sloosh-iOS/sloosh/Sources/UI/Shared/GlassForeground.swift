import SwiftUI

/// Blend only the foreground of glass controls, never the glass surface itself.
/// Keeps explicit semantic tints and disabled states intact.
struct GlassForegroundAppearance {
    let opacity: Double
    let blendMode: BlendMode

    init(isDark: Bool, increasedContrast: Bool, reduceTransparency: Bool,
         blendsContent: Bool, controlEnabled: Bool, opacity: Double = 0.72, isInverted: Bool = false) {
        guard blendsContent && controlEnabled else {
            self.opacity = 1
            self.blendMode = .normal
            return
        }
        let foreground = BackdropForegroundAppearance(
            isDark: isInverted ? !isDark : isDark, increasedContrast: increasedContrast,
            reduceTransparency: reduceTransparency, opacity: opacity
        )
        self.opacity = foreground.opacity
        self.blendMode = foreground.blendMode
    }

    static func shouldBlend(tint: Color?) -> Bool {
        guard let tint else { return true }
        return tint == .primary || tint == .secondary || tint == .white
    }
}

private struct GlassForegroundModifier: ViewModifier {
    let opacity: Double
    let blendsContent: Bool
    let isInverted: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.isEnabled) private var controlEnabled

    func body(content: Content) -> some View {
        let appearance = GlassForegroundAppearance(
            isDark: colorScheme == .dark, increasedContrast: contrast == .increased,
            reduceTransparency: reduceTransparency, blendsContent: blendsContent,
            controlEnabled: controlEnabled, opacity: opacity, isInverted: isInverted
        )
        content
            .opacity(appearance.opacity)
            .blendMode(appearance.blendMode)
    }
}

extension View {
    /// Place on an icon/text label BEFORE its background and .glassEffect.
    /// This preserves its color; explicit semantic tints should opt out.
    func glassForeground(opacity: Double = 0.72, isEnabled: Bool = true, isInverted: Bool = false) -> some View {
        modifier(GlassForegroundModifier(opacity: opacity, blendsContent: isEnabled, isInverted: isInverted))
    }
}
