import SwiftUI

/// A tall, condensed wordmark when an actual film logo isn't available. Oswald
/// is bundled locally with Cyrillic glyphs; this view never fetches a font.
struct CatalogFallbackLogoTitle: View {
    let title: String
    let isOverlay: Bool
    var scale: CGFloat = 1

    var body: some View {
        Text(CatalogFallbackTitleStyle.displayTitle(title))
            .font(.custom(CatalogFallbackTitleStyle.postScriptName,
                          fixedSize: CatalogFallbackTitleStyle.pointSize * scale))
            .foregroundStyle(isOverlay ? Color.white.opacity(0.95) : Color.primary)
            .blendMode(isOverlay ? .plusLighter : .normal)
            .lineLimit(2)
            .minimumScaleFactor(CatalogFallbackTitleStyle.minimumScale)
            .tracking(0.1 * scale)
            .allowsTightening(true)
            .truncationMode(.tail)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityLabel(title)
    }
}
