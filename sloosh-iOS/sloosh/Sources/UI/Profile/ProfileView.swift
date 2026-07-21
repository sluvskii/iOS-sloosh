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
    @State private var scrollOffsets: [FavoriteCategory: CGFloat] = [:]
    @State private var directPlaybackMovie: MediaDto?
    @State private var playerConfig: PlayerConfig?
    
    private var columns: [GridItem] {
        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
        let minWidth: CGFloat = cardDensity == .compact ? 95 : 105
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }

    private var blurOpacity: Double {
        let offset = scrollOffsets[selectedCategory] ?? 0
        let progress = max(0, offset) / 30.0
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
        NavigationStack {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(FavoriteCategory.allCases, id: \.self) { category in
                        ProfileCategoryContentView(
                            category: category,
                            favoritesRepo: favoritesRepo,
                            favorites: favorites(for: category),
                            navigationTransition: navigationTransition,
                            columns: columns,
                            cardDensity: cardDensity,
                            directPlaybackMovie: $directPlaybackMovie,
                            scrollOffset: Binding(
                                get: { scrollOffsets[category] ?? 0 },
                                set: { scrollOffsets[category] = $0 }
                            )
                        )
                        .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(
                get: { selectedCategory },
                set: { newValue in
                    if let newValue = newValue {
                        selectedCategory = newValue
                    }
                }
            ))
            .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 8) {
                    // Верхний слой: Заголовок и Настройки
                    ZStack {
                        Text("Профиль")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            
                            HStack {
                                Spacer()
                                
                                Button {
                                    showsSettings = true
                                } label: {
                                    Image(systemName: "gearshape.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(.primary)
                                        .frame(width: 44, height: 44)
                                        .glassEffect(.regular, in: .circle)
                                }
                                .buttonStyle(NativeGlassButtonStyle())
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
                .sheet(item: $directPlaybackMovie) { movie in
                    let kpId = movie.externalIds?.kp ?? Int(movie.id) ?? 0
                    HomeDirectPlayWrapper(
                        kpId: kpId,
                        title: movie.title ?? movie.name ?? movie.originalTitle ?? ""
                    ) { config in
                        directPlaybackMovie = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            playerConfig = config
                        }
                    }
                }
                .fullScreenCover(item: $playerConfig) { config in
                    PlayerView(
                        iframeUrl: config.iframeUrl,
                        fallbackTitle: config.title,
                        kpId: config.kpId,
                        season: config.season,
                        episode: config.episode,
                        selectedVoiceover: config.voiceover,
                        directStreamUrl: config.streamUrl,
                        voices: config.voices,
                        subtitles: config.subtitles,
                        initialQuality: config.quality,
                        seriesResult: config.seriesResult
                    )
                }
            }
        }
    }

struct ProfileCategoryContentView: View {
    let category: FavoriteCategory
    @ObservedObject var favoritesRepo: FavoritesRepository
    let favorites: [FavoriteDto]
    let navigationTransition: Namespace.ID
    let columns: [GridItem]
    let cardDensity: CardDensity
    @Binding var directPlaybackMovie: MediaDto?
    @Binding var scrollOffset: CGFloat

    var body: some View {
        ScrollView {
            // Invisible anchor to fix layout alignment
            Color.clear.frame(height: 0).id("profile-scroll-top-\(category.rawValue)")
            VStack(spacing: 20) {
                // В будущем здесь будет шапка профиля (аватарка, ник пользователя)
                
                if favoritesRepo.favorites.isEmpty {
                    ProfileEmptyState(
                        icon: "heart.slash",
                        title: "Пока ничего не добавлено",
                        message: "Сохраняйте фильмы и сериалы в избранное, чтобы быстро возвращаться к ним позже."
                    )
                    .containerRelativeFrame(.vertical)
                } else if favorites.isEmpty {
                    ProfileEmptyState(
                        icon: "film.stack",
                        title: "В этой подборке пока пусто",
                        message: "Попробуйте открыть другую вкладку или добавьте что-нибудь в избранное."
                    )
                    .containerRelativeFrame(.vertical)
                } else {
                    let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                    let padding: CGFloat = cardDensity == .compact ? 12 : 16
                    LazyVGrid(columns: columns, spacing: spacing) {
                        ForEach(favorites) { favorite in
                            let media = favorite.toMediaDto()
                            MovieDetailsNavigationLink(movie: media, navigationTransition: navigationTransition)
                            .contextMenu {
                                Group {
                                    Button {
                                        directPlaybackMovie = media
                                    } label: {
                                        Label("Смотреть", systemImage: "play.fill")
                                    }
                                    
                                    NavigationLink(destination: DetailsView(movieId: media.id, navigationTransitionID: nil, navigationTransitionNamespace: nil)) {
                                        Label("Подробнее", systemImage: "info.circle")
                                    }
                                    
                                    Button(role: .destructive) {
                                        if let mediaId = favorite.mediaId, let type = favorite.type {
                                            favoritesRepo.removeFromFavorites(mediaId: mediaId, mediaType: type)
                                        }
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
                                .tint(nil)
                            }
                        }
                    }
                    .padding(.horizontal, padding)
                }
            }
            .padding(.bottom, 16)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newOffset in
            scrollOffset = newOffset
        }
    }
}

private struct ProfileEmptyState: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        AppEmptyStateView(
            icon: icon,
            title: title,
            description: message
        )
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
