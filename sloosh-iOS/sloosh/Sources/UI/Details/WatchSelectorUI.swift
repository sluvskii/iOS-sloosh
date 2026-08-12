import SwiftUI

struct WatchSelectorChip: View {
    let title: String
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(
                    isSelected 
                        ? (colorScheme == .dark ? Color.black : Color.white) 
                        : (isAvailable ? Color.primary : Color.secondary)
                )
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? (colorScheme == .dark ? Color.white : Color.primary)
                                : (isAvailable ? Color(UIColor.secondarySystemFill) : Color(UIColor.tertiarySystemFill))
                        )
                )
        }
        .buttonStyle(ChipButtonStyle())
        .opacity(isAvailable ? 1.0 : 0.5)
    }
}

struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let result = FlowResult(in: width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
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
