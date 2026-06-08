import SwiftUI

enum FavoriteCategory: String, CaseIterable {
    case all = "Все"
    case movies = "Фильмы"
    case tvShows = "Сериалы"
    case cartoons = "Мульты"

    var title: String { rawValue }
    
    var filterType: String? {
        switch self {
        case .all: return nil
        case .movies: return "movie" // Здесь нужна дополнительная фильтрация, чтобы исключить мультфильмы, если сервер отдает их как type "movie"
        case .tvShows: return "tv"   // Аналогично для сериалов
        case .cartoons: return "cartoon" // Заглушка, позже реализуем правильный фильтр мультфильмов
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
        switch selectedCategory {
        case .all:
            return favoritesRepo.favorites
        case .movies:
            return favoritesRepo.favorites.filter { fav in
                guard fav.type == "movie" else { return false }
                // Пытаемся определить, не мультфильм ли это
                // Поскольку в FavoriteDto нет жанров, пока просто фильтруем по type
                // В идеале нужно сохранять isCartoon флаг при добавлении в избранное
                let title = (fav.title ?? "").lowercased()
                return !title.contains("мульт") && !title.contains("анимац")
            }
        case .tvShows:
            return favoritesRepo.favorites.filter { fav in
                guard fav.type == "tv" else { return false }
                let title = (fav.title ?? "").lowercased()
                return !title.contains("мульт") && !title.contains("анимац")
            }
        case .cartoons:
            return favoritesRepo.favorites.filter { fav in
                let title = (fav.title ?? "").lowercased()
                return title.contains("мульт") || title.contains("анимац") || title.contains("anime")
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // В будущем здесь будет шапка профиля (аватарка, ник пользователя)
                    
                    Picker("Папка", selection: $selectedCategory) {
                        ForEach(FavoriteCategory.allCases, id: \.self) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    
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
                        .padding(.top, 40)
                        .frame(maxWidth: .infinity)
                    } else if filteredFavorites.isEmpty {
                        VStack {
                            Text("В этой папке пока пусто")
                                .font(.system(size: 16, weight: .regular, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 40)
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
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 16)
            }
            .navigationTitle("Профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: SettingsView()) {
                        Image(systemName: "gearshape.fill")
                    }
                    .tint(.primary)
                }
            }
        }
    }
}
