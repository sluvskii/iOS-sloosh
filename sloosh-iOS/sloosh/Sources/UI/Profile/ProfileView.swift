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
    @SceneStorage("profileShowsSettings") private var showsSettings = false
    @Namespace private var navigationTransition
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular
    @State private var scrollOffset: CGFloat = 0
    
    private var columns: [GridItem] {
        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
        let minWidth: CGFloat = cardDensity == .compact ? 95 : 105
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }

    private var blurOpacity: Double {
        let progress = max(0, scrollOffset) / 30.0
        return min(1.0, Double(progress))
    }

    private func favorites(for category: FavoriteCategory) -> [FavoriteDto] {
        switch category {
        case .all:
            return favoritesRepo.favorites
        case .movies:
            return favoritesRepo.favorites.filter { fav in
                guard fav.type == "movie" else { return false }
                return !isCartoonByTitle(fav.title)
            }
        case .tvShows:
            return favoritesRepo.favorites.filter { fav in
                guard fav.type == "tv" else { return false }
                return !isCartoonByTitle(fav.title)
            }
        case .cartoons:
            return favoritesRepo.favorites.filter { fav in
                isCartoonByTitle(fav.title)
            }
        }
    }

    var filteredFavorites: [FavoriteDto] {
        favorites(for: selectedCategory)
    }

    private var categoryCounts: [FavoriteCategory: Int] {
        Dictionary(uniqueKeysWithValues: FavoriteCategory.allCases.map { category in
            (category, favorites(for: category).count)
        })
    }

    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        // В будущем здесь будет шапка профиля (аватарка, ник пользователя)
                        
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
                            let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                            let padding: CGFloat = cardDensity == .compact ? 12 : 16
                            LazyVGrid(columns: columns, spacing: spacing) {
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
                            .padding(.horizontal, padding)
                        }
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .padding(.vertical, 16)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newOffset in
                    scrollOffset = newOffset
                }
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                        // Верхний слой: Заголовок и Настройки
                        ZStack {
                            Text("Профиль")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                            
                            HStack {
                                Spacer()
                                
                                Button {
                                    showsSettings = true
                                } label: {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 20))
                                        .foregroundStyle(.primary)
                                        .frame(width: 44, height: 44)
                                        .glassEffect(.regular.interactive(), in: .circle)
                                }
                                .tint(.primary)
                            }
                        }
                        .padding(.horizontal, 16)
                        
                        // Нижний слой: Текстовые табы
                        ProfileCategoryTextTabs(
                            selectedCategory: $selectedCategory,
                            categoryCounts: categoryCounts
                        )
                        .padding(.bottom, 2)
                    }
                    .background(
                        VariableBlurView(tintOpacity: 0.75)
                            .padding(.bottom, -60) // Более длинный прогрессивный блюр для двух слоев
                            .ignoresSafeArea(edges: .top)
                            .opacity(blurOpacity)
                            .animation(.easeInOut(duration: 0.2), value: blurOpacity)
                    )
                }
                .navigationDestination(isPresented: $showsSettings) {
                    SettingsView()
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
    let categoryCounts: [FavoriteCategory: Int]
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 28

    private let titleHeight: CGFloat = 36

    private var tabSpacing: CGFloat {
        horizontalSizeClass == .regular ? 16 : 12
    }

    private var edgeContentInset: CGFloat {
        horizontalSizeClass == .regular ? 18 : 16
    }

    private var tabScrollAnimation: Animation {
        .spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.1)
    }

    private func layeredText(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight,
        isSelected: Bool
    ) -> some View {
        let isDark = colorScheme == .dark
        let opacity = isSelected ? (isDark ? 0.9 : 0.8) : (isDark ? 0.45 : 0.4)
        let color = isDark ? Color.white.opacity(opacity) : Color.black.opacity(opacity)
        let blendMode: BlendMode = isDark ? .plusLighter : .plusDarker
        
        return Text(text)
            .font(.system(size: size, weight: weight))
            .tracking(-0.8)
            .foregroundStyle(color)
            .blendMode(blendMode)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: tabSpacing) {
                    ForEach(Array(FavoriteCategory.allCases.enumerated()), id: \.element) { index, category in
                        let isSelected = selectedCategory == category
                        let isFirst = index == 0
                        let isLast = index == FavoriteCategory.allCases.count - 1

                        Button {
                            guard !isSelected else { return }
                            withAnimation(tabScrollAnimation) {
                                selectedCategory = category
                            }
                        } label: {
                            layeredText(
                                category.title,
                                size: titleSize,
                                weight: isSelected ? .bold : .semibold,
                                isSelected: isSelected
                            )
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: titleHeight, alignment: .center)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(ProfileTabScaleButtonStyle())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .id(category)
                        .padding(.leading, isFirst ? edgeContentInset : 0)
                        .padding(.trailing, isLast ? edgeContentInset : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollTargetLayout()
            }
            .frame(height: titleHeight + 4, alignment: .topLeading)
            .scrollClipDisabled()
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .animation(tabScrollAnimation, value: selectedCategory)
            .onAppear {
                scrollProxy.scrollTo(selectedCategory, anchor: .center)
            }
            .onChange(of: selectedCategory) { _, newCategory in
                withAnimation(tabScrollAnimation) {
                    scrollProxy.scrollTo(newCategory, anchor: .center)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedCategory)
    }
}
