import SwiftUI

/// Модификатор для добавления нативного Tooltip (Popover)
struct TooltipModifier: ViewModifier {
    let text: String
    @Binding var isVisible: Bool
    var isTailTop: Bool = true
    
    func body(content: Content) -> some View {
        content
            .popover(
                isPresented: $isVisible,
                attachmentAnchor: .rect(.bounds),
                arrowEdge: isTailTop ? .top : .bottom
            ) {
                Text(text)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    // Указываем системе принудительно отображать как popover (пузырек со стрелочкой) даже на iPhone
                    .presentationCompactAdaptation(.popover)
            }
    }
}

extension View {
    func tooltip(text: String, isVisible: Binding<Bool>, isTailTop: Bool = true) -> some View {
        self.modifier(TooltipModifier(text: text, isVisible: isVisible, isTailTop: isTailTop))
    }
}
