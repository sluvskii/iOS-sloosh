import SwiftUI

enum FavoriteCategory: String, CaseIterable {
    case all = "Все"
    case movies = "Фильмы"
    case tvShows = "Сериалы"

    var title: String { rawValue }
    
    var filterType: String? {
        switch self {
        case .all: return nil
        case .movies: return "movie"
        case .tvShows: return "tv"
        }
    }
}

struct ProfileView: View {
    @StateObject private var favoritesRepo = FavoritesRepository.shared
    @State private var selectedCategory: FavoriteCategory = .all
    @Namespace private var navigationTransition
    
    let columns = [
        GridItem(.adaptive(minimum: 105), spacing: 16)
    ]
    
    var filteredFavorites: [FavoriteDto] {
        if let type = selectedCategory.filterType {
            return favoritesRepo.favorites.filter { $0.type == type }
        }
        return favoritesRepo.favorites
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(pinnedViews: [.sectionHeaders]) {
                    
                    // В будущем здесь будет шапка профиля (аватарка, ник пользователя)
                    VStack {
                        // Заглушка для высоты
                    }
                    .frame(height: 40)
                    
                    Section {
                        if favoritesRepo.favorites.isEmpty {
                            VStack {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 64))
                                    .foregroundColor(.gray.opacity(0.5))
                                    .padding(.bottom, 8)
                                Text("Пусто")
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                Text("Здесь будут ваши избранные фильмы и сериалы")
                                    .font(.system(size: 16, weight: .regular, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 4)
                            }
                            .padding(.top, 100)
                            .frame(maxWidth: .infinity)
                        } else if filteredFavorites.isEmpty {
                            VStack {
                                Text("В этой папке пока пусто")
                                    .font(.system(size: 16, weight: .regular, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 100)
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(filteredFavorites) { favorite in
                                    let media = favorite.toMediaDto()
                                    MovieDetailsNavigationLink(movie: media, navigationTransition: navigationTransition)
                                    .contextMenu {
                                        Button(role: .destructive) {
                                            if let mediaId = favorite.mediaId, let type = favorite.type {
                                                favoritesRepo.removeFromFavorites(mediaId: mediaId, mediaType: type)
                                            }
                                        } label: {
                                            Label("Удалить", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(16)
                        }
                    } header: {
                        HStack {
                            Spacer()
                            Picker("Папка", selection: $selectedCategory) {
                                ForEach(FavoriteCategory.allCases, id: \.self) { category in
                                    Text(category.title).tag(category)
                                }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                            .scaleEffect(0.91)
                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.primary)
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                }
            }
        }
    }
}
