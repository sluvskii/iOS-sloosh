import SwiftUI

struct ProgressiveBlurView: View {
    // Высота сплошной части блюра (до начала градиентного затухания)
    var solidLocation: CGFloat = 0.5
    // Материал размытия
    var material: Material = .regularMaterial
    
    var body: some View {
        Rectangle()
            .fill(material)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: solidLocation),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .allowsHitTesting(false)
    }
}
