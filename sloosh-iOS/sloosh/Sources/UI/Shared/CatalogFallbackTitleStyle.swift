import Foundation

/// Full-caption wordmark typography follows metadata visibility, independently
/// of image-logo preference. Captions with year/genre retain ordinary SF text.
enum CatalogFallbackTitleStyle {
    static let postScriptName = "SlooshCatalogCondensed-SemiBold"
    static let fontFileName = "SlooshCatalogCondensed-SemiBold.ttf"
    // Slightly tighter than the original +0.1pt tracking; scales with lettering.
    static let trackingEm: CGFloat = -0.012
    // Actual space between glyph outlines, not the font's ascender/descender gap.
    static let lineGapEm: CGFloat = 0.07
    static let minimumPointSize: CGFloat = 10

    static func isEnabled(showsMetadata: Bool) -> Bool {
        !showsMetadata
    }

    static func displayTitle(_ title: String) -> String {
        title.uppercased(with: Locale(identifier: "ru_RU"))
    }
}
