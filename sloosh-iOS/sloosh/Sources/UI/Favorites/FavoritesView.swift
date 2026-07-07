import SwiftUI

struct FavoritesView: View {
    @StateObject private var favoritesRepo = FavoritesRepository.shared
    @Namespace private var navigationTransition
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular
    
    private var columns: [GridItem] {
        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
        let minWidth: CGFloat = cardDensity == .compact ? 95 : 105
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if favoritesRepo.favorites.isEmpty {
                    VStack {
                        Image(systemName: "heart.slash.fill")
                            .font(.system(size: 64))
                            .foregroundColor(.gray.opacity(0.5))
                            .padding(.bottom, 8)
                        Text("Пока нет избранного")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Добавляйте фильмы и сериалы,\nчтобы посмотреть их позже")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                        let padding: CGFloat = cardDensity == .compact ? 12 : 16
                        LazyVGrid(columns: columns, spacing: spacing) {
                            ForEach(favoritesRepo.favorites) { favorite in
                                let media = favorite.toMediaDto()
                                MovieDetailsNavigationLink(movie: media, navigationTransition: navigationTransition)
                                .contextMenu {
                                    Button(role: .destructive) {
                                        if let mediaId = favorite.mediaId, let type = favorite.type {
                                            favoritesRepo.removeFromFavorites(mediaId: mediaId, mediaType: type)
                                        }
                                    } label: {
                                        Label("Удалить из избранного", systemImage: "trash")
                                    }
                                }
                            }
                        }
                        .padding(padding)
                    }
                    .refreshable {
                        favoritesRepo.refreshMissingMetadataIfNeeded()
                    }
                }
            }
            .navigationTitle("Избранное")
            .background(Color(UIColor.systemBackground))
        }
    }
}
