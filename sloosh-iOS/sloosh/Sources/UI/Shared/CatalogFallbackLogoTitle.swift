import SwiftUI
import CoreText

/// Logo-like lettering: fit visible glyph outlines and draw explicit baselines,
/// avoiding the font's large default line box. No font/network/asset changes.
struct CatalogFallbackLogoTitle: View {
    let title: String
    let isOverlay: Bool
    var scale: CGFloat = 1
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let layout = CatalogWordmarkLayout.fit(title: title, in: size, scale: scale)
            context.withCGContext { cg in
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: 1, y: -1)
                cg.textMatrix = .identity
                cg.setFillColor(CGColor(gray: isOverlay || colorScheme == .dark ? 1 : 0,
                                        alpha: isOverlay ? 0.95 : 1))
                var top = max(0, (size.height - layout.inkSize.height) / 2)
                for line in layout.lines {
                    cg.textPosition = CGPoint(x: -line.ink.minX, y: size.height - top - line.ink.maxY)
                    CTLineDraw(line.shaped, cg)
                    top += line.ink.height + layout.lineGap
                }
            }
        }
        .blendMode(isOverlay ? .plusLighter : .normal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
