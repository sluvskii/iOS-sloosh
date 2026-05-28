import SwiftUI

struct WatchSelectorChip: View {
    let title: String
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
        }
        .buttonStyle(.borderedProminent)
        .tint(isSelected ? .primary : Color(UIColor.tertiarySystemFill))
        .foregroundStyle(isSelected ? Color(UIColor.systemBackground) : .primary)
        .buttonBorderShape(.capsule)
        .opacity(isAvailable ? 1.0 : 0.45)
        .disabled(!isAvailable)
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
            subview.place(at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var points: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Layout.Subviews, spacing: CGFloat) {
            var currentPoint = CGPoint.zero
            var rowHeight: CGFloat = 0
            var points: [CGPoint] = []
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentPoint.x + size.width > maxWidth, currentPoint.x > 0 {
                    currentPoint.x = 0
                    currentPoint.y += rowHeight + spacing
                    rowHeight = 0
                }
                
                points.append(currentPoint)
                currentPoint.x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
            
            self.points = points
            self.size = CGSize(width: maxWidth, height: currentPoint.y + rowHeight)
        }
    }
}
