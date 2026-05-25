import SwiftUI

struct FavoritesView: View {
    @StateObject private var favoritesRepo = FavoritesRepository.shared
    
    let columns = [
        GridItem(.adaptive(minimum: 105), spacing: 16)
    ]
    
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
                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(favoritesRepo.favorites) { favorite in
                                let media = favorite.toMediaDto()
                                NavigationLink(destination: DetailsView(movieId: media.id)) {
                                    MoviePosterCard(movie: media)
                                }
                                .buttonStyle(.plain)
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
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Избранное")
            .background(Color(UIColor.systemBackground))
        }
    }
}
