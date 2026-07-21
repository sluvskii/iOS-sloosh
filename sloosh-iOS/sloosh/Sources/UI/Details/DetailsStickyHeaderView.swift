import SwiftUI

struct DetailsStickyHeaderView: View {
    let details: MediaDetailsDto?
    let scrollOffset: CGFloat
    let isFavorite: Bool
    @Binding var favoriteBounce: Bool
    let onToggleFavorite: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    // Header background starts appearing at -250, fully visible at -300
    private var headerOpacity: Double {
        let minOffset: CGFloat = -250
        let maxOffset: CGFloat = -300
        if scrollOffset > minOffset { return 0 }
        if scrollOffset < maxOffset { return 1 }
        return Double((scrollOffset - minOffset) / (maxOffset - minOffset))
    }
    
    // Header logo starts appearing at -350, fully visible at -400
    private var logoOpacity: Double {
        let minOffset: CGFloat = -350
        let maxOffset: CGFloat = -400
        if scrollOffset > minOffset { return 0 }
        if scrollOffset < maxOffset { return 1 }
        return Double((scrollOffset - minOffset) / (maxOffset - minOffset))
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // Background Blur
            Rectangle()
                .fill(Color.clear)
                .glassEffect(in: Rectangle())
                .opacity(headerOpacity)
                .ignoresSafeArea()
            
            HStack(alignment: .center) {
                // Back Button
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .glassEffect(in: Circle())
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                // Centered Mini Logo
                if let details = details {
                    RemoteLogoView(
                        url: URL(string: details.displayLogoUrl ?? ""),
                        fallbackTitle: details.title ?? details.originalTitle ?? "Без названия",
                        alignment: .center
                    )
                    .frame(maxHeight: 36)
                    .opacity(logoOpacity)
                    // Move it slightly up so it's vertically centered with buttons
                    .offset(y: -4) 
                }
                
                Spacer()
                
                // Favorite Button
                Button {
                    onToggleFavorite()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolEffect(.bounce, value: favoriteBounce)
                        .frame(width: 44, height: 44)
                        .glassEffect(in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(details == nil)
                .accessibilityLabel(isFavorite ? "Убрать из избранного" : "Добавить в избранное")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .frame(height: 50 + safeAreaTop)
    }
    
    private var safeAreaTop: CGFloat {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return 47 // default dynamic island height
        }
        return window.safeAreaInsets.top
    }
}
