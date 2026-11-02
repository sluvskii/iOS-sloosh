import SwiftUI

/// Settings preview and loading cards share the real caption's sizing policy.
struct CatalogCaptionSkeleton: View {
    let isOverlay: Bool
    let useLogos: Bool
    let showsMetadata: Bool
    @ScaledMetric(relativeTo: .caption) private var scale: CGFloat = 1

    var body: some View {
        let layout = CatalogCaptionLayout(isOverlay: isOverlay, showsMetadata: showsMetadata, scale: scale)
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: layout.spacing) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: geometry.size.width * (useLogos && !showsMetadata ? 0.9 : 0.7), height: layout.titleAreaHeight)
                if showsMetadata {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.15))
                        .frame(width: geometry.size.width * 0.5, height: layout.metadataHeight)
                }
            }
        }
        .frame(height: layout.totalHeight)
        .accessibilityHidden(true)
    }
}
