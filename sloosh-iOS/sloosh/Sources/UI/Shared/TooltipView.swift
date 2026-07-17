import SwiftUI

/// Модификатор для добавления Tooltip к любому элементу
struct TooltipModifier: ViewModifier {
    let text: String
    @Binding var isVisible: Bool
    var isTailTop: Bool = true
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    VStack {
                        if !isTailTop { Spacer() }
                        
                        if isVisible {
                            Text(text)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .glassEffect(in: Capsule())
                                .fixedSize()
                                .offset(y: isTailTop ? geo.size.height + 12 : -(geo.size.height + 12))
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.9, anchor: isTailTop ? .top : .bottom).combined(with: .opacity),
                                    removal: .scale(scale: 0.95, anchor: isTailTop ? .top : .bottom).combined(with: .opacity)
                                ))
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        isVisible = false
                                    }
                                }
                        }
                        
                        if isTailTop { Spacer() }
                    }
                    .frame(width: geo.size.width, alignment: .center)
                }
            )
            .animation(.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0), value: isVisible)
    }
}

extension View {
    func tooltip(text: String, isVisible: Binding<Bool>, isTailTop: Bool = true) -> some View {
        self.modifier(TooltipModifier(text: text, isVisible: isVisible, isTailTop: isTailTop))
    }
}
