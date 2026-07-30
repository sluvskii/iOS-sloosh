import SwiftUI
import UIKit

/// Кастомная кнопка-иконка в стиле Telegram-iOS: 100% надежные тапы через UIKit UIControl,
/// полное отсутствие дефолтного потемнения/прозрачности, нативный Liquid Glass и плавный сквиши-эффект.
struct TelegramGlassIconButton: View {
    let systemName: String
    let iconSize: CGFloat
    let buttonSize: CGFloat
    let action: () -> Void
    
    init(
        systemName: String,
        iconSize: CGFloat = 22,
        buttonSize: CGFloat = 44,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.iconSize = iconSize
        self.buttonSize = buttonSize
        self.action = action
    }
    
    var body: some View {
        TelegramUIButtonRepresentable(
            systemName: systemName,
            iconSize: iconSize,
            action: action
        )
        .frame(width: buttonSize, height: buttonSize)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}

/// Кастомный контейнер кнопок в стиле Telegram-iOS для ЛЮБЫХ произвольных SwiftUI вьюшек (текст, иконки, капсулы):
/// 100% отмена потемнения/полупрозрачности на уровне UIKit UIControl,
/// пружинная реакция нажатия (squishy scale) без конфликтов жестов и с гарантированным вызовом action на .touchUpInside.
struct TelegramTouchView<Content: View>: View {
    let action: () -> Void
    let content: () -> Content
    
    init(action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.action = action
        self.content = content
    }
    
    var body: some View {
        TelegramTouchRepresentable(action: action, content: content())
    }
}

private struct TelegramUIButtonRepresentable: UIViewRepresentable {
    let systemName: String
    let iconSize: CGFloat
    let action: () -> Void
    
    func makeUIView(context: Context) -> UIButton {
        let button = HighlightableTelegramButton(type: .custom)
        button.adjustsImageWhenHighlighted = false
        button.adjustsImageWhenDisabled = false
        
        let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
        let image = UIImage(systemName: systemName, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
        button.setImage(image, for: .normal)
        button.tintColor = .white
        
        button.action = action
        return button
    }
    
    func updateUIView(_ uiView: UIButton, context: Context) {
        if let button = uiView as? HighlightableTelegramButton {
            button.action = action
            let config = UIImage.SymbolConfiguration(pointSize: iconSize, weight: .medium)
            let image = UIImage(systemName: systemName, withConfiguration: config)?.withRenderingMode(.alwaysTemplate)
            button.setImage(image, for: .normal)
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
        adjustsImageWhenHighlighted = false
        adjustsImageWhenDisabled = false
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }
    
    @objc private func didTap() {
        action?()
    }
    
    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(
                withDuration: isHighlighted ? 0.1 : 0.25,
                delay: 0,
                usingSpringWithDamping: 0.7,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.90, y: 0.90) : .identity
                self.alpha = 1.0
            }
        }
    }
}

private struct TelegramTouchRepresentable<Content: View>: UIViewRepresentable {
    let action: () -> Void
    let content: Content
    
    func makeUIView(context: Context) -> HighlightableTelegramContainerView {
        let container = HighlightableTelegramContainerView()
        container.action = action
        container.setContentView(UIHostingController(rootView: content).view)
        return container
    }
    
    func updateUIView(_ uiView: HighlightableTelegramContainerView, context: Context) {
        uiView.action = action
        uiView.updateContentView(UIHostingController(rootView: content).view)
    }
}

private class HighlightableTelegramContainerView: UIControl {
    var action: (() -> Void)?
    private var hostingController: UIHostingController<AnyView>?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        backgroundColor = .clear
        isOpaque = false
        addTarget(self, action: #selector(didTap), for: .touchUpInside)
    }
    
    func setContentView(_ view: UIView) {
        subviews.forEach { $0.removeFromSuperview() }
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.frame = bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(view)
    }
    
    func updateContentView(_ view: UIView) {
        setContentView(view)
    }
    
    @objc private func didTap() {
        action?()
    }
    
    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(
                withDuration: isHighlighted ? 0.1 : 0.25,
                delay: 0,
                usingSpringWithDamping: 0.75,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
                self.alpha = 1.0
            }
        }
    }
}
