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
