import SwiftUI
import UIKit
import QuartzCore

public struct ProgressiveBlurView: UIViewRepresentable {
    public var maxBlurRadius: CGFloat
    public var direction: BlurDirection
    
    public enum BlurDirection {
        case blurredTopClearBottom
        case blurredBottomClearTop
    }
    
    public init(maxBlurRadius: CGFloat = 20, direction: BlurDirection = .blurredTopClearBottom) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
    }
    
    public func makeUIView(context: Context) -> VariableBlurUIView {
        return VariableBlurUIView(maxBlurRadius: maxBlurRadius, direction: direction)
    }
    
    public func updateUIView(_ uiView: VariableBlurUIView, context: Context) {
        uiView.maxBlurRadius = maxBlurRadius
        uiView.direction = direction
    }
}

public class VariableBlurUIView: UIVisualEffectView {
    public var maxBlurRadius: CGFloat { didSet { updateFilter() } }
    public var direction: ProgressiveBlurView.BlurDirection { didSet { updateFilter() } }
    
    public init(maxBlurRadius: CGFloat, direction: ProgressiveBlurView.BlurDirection) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        super.init(effect: UIBlurEffect(style: .regular))
        self.backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        updateFilter()
    }
    
    private func updateFilter() {
        guard let backdropLayer = subviews.first?.layer else { return }
        
        let filterName = "variableBlur"
        guard let CAFilterClass = NSClassFromString("CAFilter") as? NSObject.Type else { return }
        let filterSelector = NSSelectorFromString("filterWithType:")
        guard CAFilterClass.responds(to: filterSelector) else { return }
        
        let filter = CAFilterClass.perform(filterSelector, with: filterName)?.takeUnretainedValue() as? NSObject
        filter?.setValue(maxBlurRadius, forKey: "inputRadius")
        
        let gradientImage = createGradientImage()
        filter?.setValue(gradientImage, forKey: "inputMaskImage")
        filter?.setValue(true, forKey: "inputNormalizeEdges")
        
        if let filter = filter {
            backdropLayer.filters = [filter]
        }
        
        // Маскируем саму вьюшку (чтобы скрыть жесткий край Tint-слоя)
        if let gradientImage = gradientImage {
            let maskLayer = CALayer()
            maskLayer.contents = gradientImage
            maskLayer.frame = self.bounds
            self.layer.mask = maskLayer
        }
    }
    
    private func createGradientImage() -> CGImage? {
        let size = self.bounds.size
        guard size.width > 0 && size.height > 0 else { return nil }
        
        UIGraphicsBeginImageContextWithOptions(size, false, UIScreen.main.scale)
        defer { UIGraphicsEndImageContext() }
        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        
        let colors = [
            UIColor.white.cgColor,
            UIColor.white.withAlphaComponent(0).cgColor
        ] as CFArray
        
        let locations: [CGFloat] = [0.0, 1.0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations) else { return nil }
        
        let startPoint: CGPoint
        let endPoint: CGPoint
        
        if direction == .blurredTopClearBottom {
            startPoint = CGPoint(x: 0, y: 0)
            endPoint = CGPoint(x: 0, y: size.height)
        } else {
            startPoint = CGPoint(x: 0, y: size.height)
            endPoint = CGPoint(x: 0, y: 0)
        }
        
        context.drawLinearGradient(gradient, start: startPoint, end: endPoint, options: [])
        return UIGraphicsGetImageFromCurrentImageContext()?.cgImage
    }
}
