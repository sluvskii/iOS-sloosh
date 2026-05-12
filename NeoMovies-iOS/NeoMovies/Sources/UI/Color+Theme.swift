import SwiftUI

extension Color {
    static let neoAccent = Color(UIColor { traitCollection in
        if traitCollection.userInterfaceStyle == .dark {
            return UIColor(red: 0.70, green: 1.0, blue: 0.0, alpha: 1.0)
        } else {
            return UIColor(red: 0.45, green: 0.80, blue: 0.0, alpha: 1.0)
        }
    })
}