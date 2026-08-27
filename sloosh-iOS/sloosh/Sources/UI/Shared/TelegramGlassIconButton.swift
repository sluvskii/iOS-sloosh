import SwiftUI
import UIKit

/// Кастомная кнопка-иконка в стиле Telegram-iOS: 100% надежные тапы через UIKit UIControl,
/// полное отсутствие дефолтного потемнения/прозрачности, нативный Liquid Glass и адаптивный динамический цвет (Light/Dark Mode).
struct TelegramGlassIconButton: View {
    let systemName: String
    let iconSize: CGFloat
    let buttonSize: CGFloat
    let tintColor: Color?
    let action: () -> Void
    
    init(
        systemName: String,
        iconSize: CGFloat = 22,
        buttonSize: CGFloat = 44,
        tintColor: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.iconSize = iconSize
        self.buttonSize = buttonSize
        self.tintColor = tintColor
        self.action = action
    }
    
    var body: some View {
        TelegramUIButtonRepresentable(
            systemName: systemName,
            iconSize: iconSize,
            tintColor: tintColor,
            action: action
        )
        .frame(width: buttonSize, height: buttonSize)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

private struct TelegramUIButtonRepresentable: UIViewRepresentable {
    let systemName: String
    let iconSize: CGFloat
    let tintColor: Color?
    let action: () -> Void
    
    func makeUIView(context: Context) -> UIButton {
        let button = HighlightableTelegramButton(type: .custom)
        
        let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        let image = UIImage(systemName: systemName, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.tintColor = tintColor != nil ? UIColor(tintColor!) : UIColor.label
        
        button.action = action
        return button
    }
    
    func updateUIView(_ uiView: UIButton, context: Context) {
        if let button = uiView as? HighlightableTelegramButton {
            button.action = action
            let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
            let image = UIImage(systemName: systemName, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
            button.setImage(image, for: .normal)
            button.tintColor = tintColor != nil ? UIColor(tintColor!) : UIColor.label
        }
    }
}

private class HighlightableTelegramButton: UIButton {
    var action: (() -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }
    
    @objc private func didTap() {
        action?()
    }
    
    override var isHighlighted: Bool {
        didSet {
            self.alpha = 1.0
            self.transform = .identity
        }
    }
}
