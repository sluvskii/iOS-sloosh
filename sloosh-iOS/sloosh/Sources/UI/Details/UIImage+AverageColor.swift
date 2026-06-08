import UIKit

extension UIImage {
    var averageColor: UIColor? {
        guard let cgImage = cgImage else { return nil }
        
        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &bitmap,
                                width: 1,
                                height: 1,
                                bitsPerComponent: 8,
                                bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = context else { return nil }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        return UIColor(
            red: CGFloat(bitmap[0]) / 255.0,
            green: CGFloat(bitmap[1]) / 255.0,
            blue: CGFloat(bitmap[2]) / 255.0,
            alpha: 1.0
        )
    }
}

extension UIColor {
    func blended(with backgroundColor: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        
        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        backgroundColor.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        
        // If getRed fails (e.g. for some system colors), fallback to a safe extraction
        if a1 == 0 && a2 == 0 {
            // Draw into context to force RGB
            let rect = CGRect(x: 0, y: 0, width: 1, height: 1)
            UIGraphicsBeginImageContextWithOptions(rect.size, false, 1.0)
            backgroundColor.setFill()
            UIRectFill(rect)
            self.withAlphaComponent(fraction).setFill()
            UIRectFill(rect)
            let blendedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            
            guard let cgImage = blendedImage?.cgImage else { return backgroundColor }
            
            var bitmap = [UInt8](repeating: 0, count: 4)
            let context = CGContext(data: &bitmap,
                                    width: 1,
                                    height: 1,
                                    bitsPerComponent: 8,
                                    bytesPerRow: 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(cgImage, in: rect)
            
            return UIColor(red: CGFloat(bitmap[0]) / 255.0,
                           green: CGFloat(bitmap[1]) / 255.0,
                           blue: CGFloat(bitmap[2]) / 255.0,
                           alpha: 1.0)
        }
        
        let r = r1 * fraction + r2 * (1 - fraction)
        let g = g1 * fraction + g2 * (1 - fraction)
        let b = b1 * fraction + b2 * (1 - fraction)
        let a = a1 * fraction + a2 * (1 - fraction)
        
        return UIColor(red: r, green: g, blue: b, alpha: a)
    }
}
