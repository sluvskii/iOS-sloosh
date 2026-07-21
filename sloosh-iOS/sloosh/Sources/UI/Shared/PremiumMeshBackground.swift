import SwiftUI

@available(iOS 18.0, *)
struct PremiumMeshBackground: View {
    let dominantColor: UIColor?
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Fallback if no dominant color
    private var baseColor: Color {
        if let d = dominantColor {
            // In light mode, soften the pure color a bit so text remains readable
            return colorScheme == .light ? Color(d.blended(with: .white, fraction: 0.2)) : Color(d)
        }
        return Color(UIColor.systemBackground)
    }
    
    private var darkBaseColor: Color {
        if let d = dominantColor {
            if colorScheme == .light {
                // In light mode, "dark" is just the pure color or slightly darkened
                return Color(d.blended(with: .black, fraction: 0.1))
            } else {
                return Color(d.blended(with: .black, fraction: 0.6))
            }
        }
        return Color.black
    }

    private var lightBaseColor: Color {
        if let d = dominantColor {
            if colorScheme == .light {
                // In light mode, "light" is blended heavily with white
                return Color(d.blended(with: .white, fraction: 0.75))
            } else {
                return Color(d.blended(with: UIColor.systemBackground, fraction: 0.5))
            }
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
