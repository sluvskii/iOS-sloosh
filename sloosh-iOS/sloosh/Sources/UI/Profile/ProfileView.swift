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
        GeometryReader { geometry in
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // В будущем здесь будет шапка профиля (аватарка, ник пользователя)
                        
                        ProfileCategoryTextTabs(selectedCategory: $selectedCategory)
                        
                        if favoritesRepo.favorites.isEmpty {
                            ProfileEmptyState(
                                icon: "heart.slash",
                                title: "Пока ничего не добавлено",
                                message: "Сохраняйте фильмы и сериалы в избранное, чтобы быстро возвращаться к ним позже."
                            )
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: max(geometry.size.height - 180, 320))
                        } else if filteredFavorites.isEmpty {
                            ProfileEmptyState(
                                icon: "film.stack",
                                title: "В этой подборке пока пусто",
                                message: "Попробуйте открыть другую вкладку или добавьте что-нибудь в избранное."
                            )
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: max(geometry.size.height - 180, 320))
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
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .padding(.vertical, 16)
                }
                .navigationTitle("Профиль")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(destination: SettingsView()) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 30, height: 30)
                                .contentShape(Circle())
                        }
                        .tint(.primary)
                    }
                }
            }
        }
    }
}

private struct ProfileEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 24, weight: .bold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
            .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }
}

private struct ProfileTabScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

private struct ProfileCategoryTextTabs: View {
    @Binding var selectedCategory: FavoriteCategory
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 24

    private var tabSpacing: CGFloat {
        horizontalSizeClass == .regular ? 28 : 22
    }

    private var edgeInset: CGFloat {
        horizontalSizeClass == .regular ? 18 : 16
    }

    private var animation: Animation {
        .spring(response: 0.35, dampingFraction: 0.78, blendDuration: 0.1)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: tabSpacing) {
                    ForEach(Array(FavoriteCategory.allCases.enumerated()), id: \.element) { index, category in
                        let isSelected = selectedCategory == category
                        let isFirst = index == 0
                        let isLast = index == FavoriteCategory.allCases.count - 1

                        Button {
                            guard !isSelected else { return }
                            withAnimation(animation) {
                                selectedCategory = category
                            }
                        } label: {
                            Text(category.title)
                                .font(.system(size: titleSize, weight: isSelected ? .bold : .semibold))
                                .foregroundStyle(isSelected ? .primary : .secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(ProfileTabScaleButtonStyle())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .padding(.leading, isFirst ? edgeInset : 0)
                        .padding(.trailing, isLast ? edgeInset : 0)
                        .id(category)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollClipDisabled()
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .onAppear {
                scrollProxy.scrollTo(selectedCategory, anchor: .center)
            }
            .onChange(of: selectedCategory) { _, newCategory in
                withAnimation(animation) {
                    scrollProxy.scrollTo(newCategory, anchor: .center)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedCategory)
    }
}
