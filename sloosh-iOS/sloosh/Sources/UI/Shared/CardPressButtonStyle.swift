import SwiftUI

/// Нативный пружинящий стиль нажатия для карточек фильмов в стиле Apple:
/// при обычном тапе карточка плавно и упруго утапливается (scale ~0.955),
/// сохраняя системное контекстное меню и нативные переходы.
struct CardPressButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.955

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == CardPressButtonStyle {
    static var cardPress: CardPressButtonStyle { CardPressButtonStyle() }
    static func cardPress(scale: CGFloat = 0.955) -> CardPressButtonStyle {
        CardPressButtonStyle(scale: scale)
    }
}
