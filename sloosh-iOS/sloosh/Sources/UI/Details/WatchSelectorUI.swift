import SwiftUI

struct WatchSelectorChip: View {
    let title: String
    let isSelected: Bool
    let isAvailable: Bool
    var namespace: Namespace.ID? = nil
    var namespaceId: String? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private static let feedback = UISelectionFeedbackGenerator()

    var body: some View {
        Button {
            Self.feedback.selectionChanged()
            action()
        } label: {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .frame(height: 32)
                .foregroundStyle(
                    isSelected
                        ? (colorScheme == .dark ? Color.black : Color.white)
                        : (isAvailable ? Color.primary : Color.secondary.opacity(0.45))
                )
                .animation(.easeInOut(duration: 0.18), value: isSelected)
                .background {
                    if isSelected {
                        if let namespace, let namespaceId {
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white : Color.primary)
                                .matchedGeometryEffect(id: namespaceId, in: namespace)
                                .shadow(color: colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
                        } else {
                            Capsule()
                                .fill(colorScheme == .dark ? Color.white : Color.primary)
                                .shadow(color: colorScheme == .dark ? Color.white.opacity(0.22) : Color.black.opacity(0.18), radius: 6, x: 0, y: 2)
                        }
                    } else {
                        Capsule()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.09) : Color(UIColor.secondarySystemFill))
                    }
                }
        }
        .buttonStyle(ChipButtonStyle())
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1.0 : 0.4)
    }
}

struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    typealias Cache = CacheData
    var spacing: CGFloat = 8
    
    struct CacheData {
        var width: CGFloat
        var count: Int
        var result: FlowResult
    }
    
    func makeCache(subviews: Subviews) -> CacheData {
        CacheData(width: -1, count: -1, result: FlowResult(size: .zero, points: [], sizes: []))
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) -> CGSize {
        let width = proposal.width ?? 300
        if abs(cache.width - width) < 0.5 && cache.count == subviews.count && !cache.result.sizes.isEmpty {
            return cache.result.size
        }
        let result = FlowResult(in: width, subviews: subviews, spacing: spacing)
        cache = CacheData(width: width, count: subviews.count, result: result)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        let result: FlowResult
        if abs(cache.width - bounds.width) < 0.5 && cache.count == subviews.count && !cache.result.sizes.isEmpty {
            result = cache.result
        } else {
            result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
            cache = CacheData(width: bounds.width, count: subviews.count, result: result)
        }
        
        for (index, subview) in subviews.enumerated() {
            guard index < result.points.count else { break }
            let point = result.points[index]
            let itemWidth = min(result.sizes[index].width, bounds.width)
            subview.place(
                at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY),
                proposal: ProposedViewSize(width: itemWidth, height: nil)
            )
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var points: [CGPoint] = []
        var sizes: [CGSize] = []
        
        init(size: CGSize, points: [CGPoint], sizes: [CGSize]) {
            self.size = size
            self.points = points
            self.sizes = sizes
        }
        
        init(in maxWidth: CGFloat, subviews: Layout.Subviews, spacing: CGFloat) {
            var currentPoint = CGPoint.zero
            var rowHeight: CGFloat = 0
            var points: [CGPoint] = []
            var sizes: [CGSize] = []
            
            for subview in subviews {
                let maxAllowedChildWidth = max(50, maxWidth)
                var size = subview.sizeThatFits(ProposedViewSize(width: maxAllowedChildWidth, height: nil))
                if size.width > maxAllowedChildWidth {
                    size.width = maxAllowedChildWidth
                }
                
                if currentPoint.x + size.width > maxWidth, currentPoint.x > 0 {
                    currentPoint.x = 0
                    currentPoint.y += rowHeight + spacing
                    rowHeight = 0
                }
                
                points.append(currentPoint)
                sizes.append(size)
                currentPoint.x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
            
            self.points = points
            self.sizes = sizes
            self.size = CGSize(width: maxWidth, height: currentPoint.y + rowHeight)
        }
    }
}
