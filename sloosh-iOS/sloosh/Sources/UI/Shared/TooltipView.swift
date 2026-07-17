import SwiftUI

/// Идеально скругленная форма (Capsule) с элегантным хвостиком
struct TooltipShape: Shape {
    var isTop: Bool
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tailHeight: CGFloat = 6
        let tailWidth: CGFloat = 12
        
        let contentRect = CGRect(
            x: 0,
            y: isTop ? tailHeight : 0,
            width: rect.width,
            height: rect.height - tailHeight
        )
        
        // Максимально скругленные края (эффект Capsule)
        let cornerRadius = contentRect.height / 2
        path.addRoundedRect(in: contentRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        
        // Аккуратный маленький хвостик по центру
        var tailPath = Path()
        let tailX = rect.midX
        if isTop {
            tailPath.move(to: CGPoint(x: tailX - tailWidth/2, y: tailHeight))
            tailPath.addLine(to: CGPoint(x: tailX, y: 0))
            tailPath.addLine(to: CGPoint(x: tailX + tailWidth/2, y: tailHeight))
        } else {
            let y = rect.height - tailHeight
            tailPath.move(to: CGPoint(x: tailX - tailWidth/2, y: y))
            tailPath.addLine(to: CGPoint(x: tailX, y: rect.height))
            tailPath.addLine(to: CGPoint(x: tailX + tailWidth/2, y: y))
        }
        tailPath.closeSubpath()
        path.addPath(tailPath)
        
        return path
    }
}

/// Модификатор для добавления кастомного элегантного Tooltip
struct TooltipModifier: ViewModifier {
    let text: String
    @Binding var isVisible: Bool
    var isTailTop: Bool = true
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        if !isTailTop { Spacer(minLength: 0) }
                        
                        if isVisible {
                            Text(text)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 16)
                                .padding(.top, isTailTop ? 8 + 6 : 8)
                                .padding(.bottom, isTailTop ? 8 : 8 + 6)
                                .glassEffect(in: TooltipShape(isTop: isTailTop))
                                .fixedSize()
                                .offset(y: isTailTop ? geo.size.height + 8 : -(geo.size.height + 8))
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
                        
                        if isTailTop { Spacer(minLength: 0) }
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
