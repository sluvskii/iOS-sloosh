import SwiftUI

/// Пузырек подсказки с хвостиком
struct TooltipShape: Shape {
    var tailPosition: CGFloat // 0.0 to 1.0
    var tailHeight: CGFloat = 8
    var tailWidth: CGFloat = 16
    var cornerRadius: CGFloat = 12
    var isTailTop: Bool = true
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let tailX = rect.width * tailPosition
        let contentRect = CGRect(x: 0,
                                 y: isTailTop ? tailHeight : 0,
                                 width: rect.width,
                                 height: rect.height - tailHeight)
        
        // Рисуем прямоугольник с закругленными краями
        path.addRoundedRect(in: contentRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
        
        // Вырезаем и добавляем хвостик
        var tailPath = Path()
        if isTailTop {
            tailPath.move(to: CGPoint(x: tailX - tailWidth/2, y: tailHeight))
            tailPath.addLine(to: CGPoint(x: tailX, y: 0))
            tailPath.addLine(to: CGPoint(x: tailX + tailWidth/2, y: tailHeight))
            tailPath.closeSubpath()
        } else {
            let y = rect.height - tailHeight
            tailPath.move(to: CGPoint(x: tailX - tailWidth/2, y: y))
            tailPath.addLine(to: CGPoint(x: tailX, y: rect.height))
            tailPath.addLine(to: CGPoint(x: tailX + tailWidth/2, y: y))
            tailPath.closeSubpath()
        }
        
        path.addPath(tailPath)
        return path
    }
}

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
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 12)
                                    .glassEffect(in: TooltipShape(tailPosition: 0.5, cornerRadius: 14, isTailTop: isTailTop))
                                    .overlay(
                                        TooltipShape(tailPosition: 0.5, cornerRadius: 14, isTailTop: isTailTop)
                                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
                                .fixedSize()
                                .offset(y: isTailTop ? geo.size.height + 8 : -(geo.size.height + 8))
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.8, anchor: isTailTop ? .top : .bottom).combined(with: .opacity),
                                    removal: .scale(scale: 0.9, anchor: isTailTop ? .top : .bottom).combined(with: .opacity)
                                ))
                                .onTapGesture {
                                    withAnimation {
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
