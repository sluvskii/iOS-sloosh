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
                .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .foregroundStyle(
                    isSelected 
                        ? (colorScheme == .dark ? Color.black : Color.white) 
                        : (isAvailable ? Color.primary : Color.secondary)
                )
                .background(
                    Capsule()
                        .fill(
                            isSelected
                                ? (colorScheme == .dark ? Color.white : Color.black)
                                : (isAvailable ? Color(UIColor.secondarySystemFill) : Color(UIColor.tertiarySystemFill))
                        )
                )
        }
        .opacity(isAvailable ? 1.0 : 0.6)
        .buttonStyle(ChipButtonStyle())
    }
}

struct ChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        let result = FlowResult(in: width, subviews: subviews, hSpacing: horizontalSpacing, vSpacing: verticalSpacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, hSpacing: horizontalSpacing, vSpacing: verticalSpacing)
        for (index, subview) in subviews.enumerated() {
            let point = result.points[index]
            subview.place(at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var points: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Layout.Subviews, hSpacing: CGFloat, vSpacing: CGFloat) {
            var currentPoint = CGPoint.zero
            var rowHeight: CGFloat = 0
            var points: [CGPoint] = []
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentPoint.x + size.width > maxWidth, currentPoint.x > 0 {
                    currentPoint.x = 0
                    currentPoint.y += rowHeight + vSpacing
                    rowHeight = 0
                }
                
                points.append(currentPoint)
                currentPoint.x += size.width + hSpacing
                rowHeight = max(rowHeight, size.height)
            }
            
            self.points = points
            self.size = CGSize(width: maxWidth, height: currentPoint.y + rowHeight)
        }
    }
}
