import SwiftUI

struct CustomDetailsTopBar: View {
    let scrollOffset: CGFloat
    let title: String
    let logoUrl: String?
    let showLogo: Bool
    let isFavorite: Bool
    let namespace: Namespace.ID
    let onBack: () -> Void
    let onFavorite: () -> Void
    
    // Threshold where the bar becomes fully opaque
    private let fadeThreshold: CGFloat = 200
    
    private var glassOpacity: CGFloat {
        if scrollOffset < 50 { return 0 }
        let progress = (scrollOffset - 50) / (fadeThreshold - 50)
        return min(max(progress, 0), 1)
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Glass Background that fades in
            VariableBlurView(tintOpacity: 0.75)
                .ignoresSafeArea(edges: .top)
                .opacity(glassOpacity)
                .allowsHitTesting(false)
            
            HStack(spacing: 16) {
                // Back Button
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(glassOpacity < 0.5 ? 0.3 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Назад")
                
                Spacer()
                
                // Logo / Title Transition
                if showLogo {
                    Group {
                        if let logoUrl = logoUrl, !logoUrl.isEmpty {
                            AsyncCachedImage(url: URL(string: logoUrl)) { phase in
                                switch phase {
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFit()
                                default:
                                    Text(title)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                }
                            }
                        } else {
                            Text(title)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxHeight: 34)
                    .matchedGeometryEffect(id: "detailsLogo", in: namespace)
                }
                
                Spacer()
                
                // Favorite Button
                Button(action: onFavorite) {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.black.opacity(glassOpacity < 0.5 ? 0.3 : 0))
                        )
                        .contentShape(Rectangle())
                        .symbolEffect(.bounce, value: isFavorite)
                }
                .accessibilityLabel(isFavorite ? "Убрать из избранного" : "Добавить в избранное")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .frame(height: 54, alignment: .bottom)
            .frame(maxWidth: .infinity)
        }
    }
}
