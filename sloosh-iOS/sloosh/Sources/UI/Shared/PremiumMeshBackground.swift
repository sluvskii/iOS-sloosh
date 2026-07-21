import SwiftUI

@available(iOS 18.0, *)
struct PremiumMeshBackground: View {
    let dominantColor: UIColor?
    
    // Fallback if no dominant color
    private var baseColor: Color {
        if let d = dominantColor {
            return Color(d)
        }
        return Color(UIColor.systemBackground)
    }
    
    private var darkBaseColor: Color {
        if let d = dominantColor {
            return Color(d.blended(with: UIColor.black, fraction: 0.6))
        }
        return Color.black
    }

    private var lightBaseColor: Color {
        if let d = dominantColor {
            return Color(d.blended(with: UIColor.systemBackground, fraction: 0.5))
        }
        return Color(UIColor.systemBackground)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let time = Float(now.remainder(dividingBy: 1000)) * 0.2 // Slow animation speed
            
            MeshGradient(
                width: 3,
                height: 3,
                points: [
                    .init(0, 0), .init(0.5, 0), .init(1, 0),
                    .init(0, 0.5),
                    .init(
                        0.5 + 0.15 * cos(time),
                        0.5 + 0.15 * sin(time)
                    ),
                    .init(1, 0.5),
                    .init(0, 1), .init(0.5, 1), .init(1, 1)
                ],
                colors: [
                    darkBaseColor, lightBaseColor, darkBaseColor,
                    lightBaseColor, baseColor, lightBaseColor,
                    darkBaseColor, lightBaseColor, darkBaseColor
                ]
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 2.0), value: dominantColor)
        }
    }
}

extension UIColor {
    func blended(with color: UIColor, fraction: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0

        self.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        color.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)

        return UIColor(
            red: r1 * (1 - fraction) + r2 * fraction,
            green: g1 * (1 - fraction) + g2 * fraction,
            blue: b1 * (1 - fraction) + b2 * fraction,
            alpha: a1 * (1 - fraction) + a2 * fraction
        )
    }
}
