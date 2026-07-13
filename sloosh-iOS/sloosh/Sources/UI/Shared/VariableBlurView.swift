import SwiftUI
import UIKit
import QuartzCore

/// Создает эффект прогрессивного размытия (Liquid Glass),
/// плавно переходящего от полного блюра к полной прозрачности.
/// Реализация скопирована из Telegram-iOS с обходом приватного API.
public struct VariableBlurView: View {
    public var maxBlurRadius: CGFloat = 2
    public var direction: VariableBlurRepresentable.BlurDirection = .blurredTopClearBottom
    public var tintColor: Color = Color(UIColor.systemBackground)
    public var tintOpacity: Double = 0.90
    
    public init(maxBlurRadius: CGFloat = 2, direction: VariableBlurRepresentable.BlurDirection = .blurredTopClearBottom, tintColor: Color = Color(UIColor.systemBackground), tintOpacity: Double = 0.90) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
    }
    
    public var body: some View {
        VariableBlurRepresentable(maxBlurRadius: maxBlurRadius, direction: direction)
            .overlay(
                LinearGradient(
                    colors: [
                        tintColor.opacity(direction == .blurredTopClearBottom ? tintOpacity : 0.0),
                        tintColor.opacity(direction == .blurredTopClearBottom ? 0.0 : tintOpacity)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
    }
}

public struct VariableBlurRepresentable: UIViewRepresentable {
    public var maxBlurRadius: CGFloat = 2
    public var direction: BlurDirection = .blurredTopClearBottom
    
    public enum BlurDirection {
        case blurredTopClearBottom
        case blurredBottomClearTop
    }
    
    public init(maxBlurRadius: CGFloat = 2, direction: BlurDirection = .blurredTopClearBottom) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
    }

    public func makeUIView(context: Context) -> VariableBlurUIView {
        return VariableBlurUIView(maxBlurRadius: maxBlurRadius, direction: direction)
    }

    public func updateUIView(_ uiView: VariableBlurUIView, context: Context) {
        if uiView.maxBlurRadius != maxBlurRadius || uiView.direction != direction {
            uiView.maxBlurRadius = maxBlurRadius
            uiView.direction = direction
        }
    }
}

public final class VariableBlurUIView: UIVisualEffectView {
    public var maxBlurRadius: CGFloat {
        didSet {
            resetEffect()
        }
    }
    
    public var direction: VariableBlurRepresentable.BlurDirection {
        didSet {
            resetEffect()
        }
    }
    
    public init(maxBlurRadius: CGFloat = 2, direction: VariableBlurRepresentable.BlurDirection = .blurredTopClearBottom) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        super.init(effect: UIBlurEffect(style: .regular))
        
        if self.subviews.indices.contains(1) {
            let tintOverlayView = subviews[1]
            tintOverlayView.alpha = 0
        }
        
        self.resetEffect()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        if #available(iOS 13.0, *) {
            if self.traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
                self.resetEffect()
            }
        }
    }
    
    private func resetEffect() {
        let filterClassStringEncoded = "Q0FGaWx0ZXI="
        let filterClassString: String = {
            if let data = Data(base64Encoded: filterClassStringEncoded),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return ""
        }()
        let filterWithTypeStringEncoded = "ZmlsdGVyV2l0aFR5cGU6"
        let filterWithTypeString: String = {
            if let data = Data(base64Encoded: filterWithTypeStringEncoded),
               let string = String(data: data, encoding: .utf8) {
                return string
            }
            return ""
        }()

        let filterWithTypeSelector = Selector(filterWithTypeString)

        guard let filterClass = NSClassFromString(filterClassString) as AnyObject as? NSObjectProtocol else {
            return
        }

        guard filterClass.responds(to: filterWithTypeSelector) else {
            return
        }

        let variableBlur = filterClass.perform(filterWithTypeSelector, with: "variableBlur").takeUnretainedValue()

        guard let variableBlur = variableBlur as? NSObject else {
            return
        }
        
        guard let gradientImageRef = createGradientImage() else {
            return
        }

        variableBlur.setValue(self.maxBlurRadius, forKey: "inputRadius")
        variableBlur.setValue(gradientImageRef, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")
        
        let backdropLayer = self.subviews.first?.layer
        backdropLayer?.filters = [variableBlur]
        backdropLayer?.setValue(UIScreen.main.scale, forKey: "scale")
    }
    
    private func createGradientImage() -> CGImage? {
        let height: CGFloat = 100
        let width: CGFloat = 1
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }
        
        let colors = [UIColor(white: 0, alpha: 1).cgColor, UIColor(white: 0, alpha: 0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) else {
            return nil
        }
        
        let startPoint = direction == .blurredTopClearBottom ? CGPoint(x: 0, y: height) : CGPoint(x: 0, y: 0)
        let endPoint = direction == .blurredTopClearBottom ? CGPoint(x: 0, y: 0) : CGPoint(x: 0, y: height)
        
        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
        return context.makeImage()
    }
}
