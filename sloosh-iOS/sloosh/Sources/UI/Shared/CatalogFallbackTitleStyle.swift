import Foundation

/// Experimental typography is scoped to the logo-only caption, never the
/// ordinary text-card mode or the title/year/genre layout.
enum CatalogFallbackTitleStyle {
    static let postScriptName = "SlooshCatalogCondensed-SemiBold"
    static let fontFileName = "SlooshCatalogCondensed-SemiBold.ttf"
    static let pointSize: CGFloat = 20
    static let minimumScale: CGFloat = 0.55

    static func isEnabled(useLogos: Bool, showsMetadata: Bool) -> Bool {
        useLogos && !showsMetadata
    }

    static func displayTitle(_ title: String) -> String {
        title.uppercased(with: Locale(identifier: "ru_RU"))
    }
}
