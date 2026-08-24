import UIKit
import SwiftUI

extension Color {
    public static let slooshAccent = Color(UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.70, green: 1.0, blue: 0.0, alpha: 1.0)
        } else {
            return UIColor(red: 0.45, green: 0.80, blue: 0.0, alpha: 1.0)
        }
    })
}

extension UIColor {
    public convenience init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        if cleanHex.count == 6 {
            var rgbValue: UInt64 = 0
            guard Scanner(string: cleanHex).scanHexInt64(&rgbValue) else { return nil }
            self.init(
                red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
                blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
                alpha: 1.0
            )
        } else if cleanHex.count == 8 {
            var rgbValue: UInt64 = 0
            guard Scanner(string: cleanHex).scanHexInt64(&rgbValue) else { return nil }
            self.init(
                red: CGFloat((rgbValue & 0xFF000000) >> 24) / 255.0,
                green: CGFloat((rgbValue & 0x00FF0000) >> 16) / 255.0,
                blue: CGFloat((rgbValue & 0x0000FF00) >> 8) / 255.0,
                alpha: CGFloat(rgbValue & 0x000000FF) / 255.0
            )
        } else {
            return nil
        }
    }
}