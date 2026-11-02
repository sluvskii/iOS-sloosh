import Foundation

/// Keep the caption footprint stable when metadata is hidden. The logo (or a
/// two-line text fallback) inherits the title + spacing + metadata area.
struct CatalogCaptionLayout {
    let isOverlay: Bool
    let showsMetadata: Bool
    var scale: CGFloat = 1

    var titleHeight: CGFloat { (isOverlay ? 22 : 20) * scale }
    var metadataHeight: CGFloat { (isOverlay ? 12 : 14) * scale }
    var spacing: CGFloat { 2 * scale }
    var totalHeight: CGFloat { titleHeight + spacing + metadataHeight }
    var titleAreaHeight: CGFloat { showsMetadata ? titleHeight : totalHeight }
    var titleLineLimit: Int { showsMetadata ? 1 : 2 }
    var classicCardExtraHeight: CGFloat { 8 + totalHeight + 2 }

    func fittedLogoSize(imageSize: CGSize, availableWidth: CGFloat) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0, availableWidth > 0,
              imageSize.width.isFinite, imageSize.height.isFinite, availableWidth.isFinite else { return .zero }
        let factor = min(availableWidth / imageSize.width, titleAreaHeight / imageSize.height)
        return CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
    }

    static func metadataText(year: String?, genre: String?) -> String? {
        let parts = [year, genre].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
