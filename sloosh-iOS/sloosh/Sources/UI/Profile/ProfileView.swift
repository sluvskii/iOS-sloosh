import SwiftUI
import UIKit

enum FavoriteCategory: String, CaseIterable {
    case all = "Все"
    case movies = "Фильмы"
    case tvShows = "Сериалы"
    case cartoons = "Мульты"

    var title: String { rawValue }
    
    var filterType: String? {
        switch self {
        case .all: return nil
        case .movies: return "movie"
        case .tvShows: return "tv"
        case .cartoons: return "cartoon"
        }
    }

    func filterFavorites(_ items: [FavoriteDto]) -> [FavoriteDto] {
        switch self {
        case .all:
            return items
        case .movies:
            return items.filter { fav in
                guard fav.type == "movie" else { return false }
                return !isCartoonByTitle(fav.title)
            }
        case .tvShows:
            return items.filter { fav in
                guard fav.type == "tv" else { return false }
                return !isCartoonByTitle(fav.title)
            }
        case .cartoons:
            return items.filter { fav in
                isCartoonByTitle(fav.title)
            }
        }
    }
}

struct ProfileView: View {
    @StateObject private var favoritesRepo = FavoritesRepository.shared
    @StateObject private var authRepo = AuthRepository.shared
    @State private var selectedCategory: FavoriteCategory = .all
    @SceneStorage("profileShowsSettings") private var showsSettings = false
    @SceneStorage("profileShowsDownloads") private var showsDownloads = false
    @SceneStorage("profileShowsTierLists") private var showsTierLists = false
    @State private var deepLinkTierId: String?
    @State private var showAuthSheet = false
    @State private var showSignOutAlert = false
    @State private var showEditProfileSheet = false
    @State private var showAdminDashboard = false
    @State private var showMyProfile = false
    @Namespace private var navigationTransition
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular
    @State private var directPlaybackMovie: MediaDto?
    @State private var pendingPlayerConfig: PlayerConfig?
    @State private var playerConfig: PlayerConfig?

    private var profileHeaderTitle: String {
        if authRepo.isAuthenticated {
            if let tag = authRepo.currentUser?.displayTag, !tag.isEmpty {
                return tag
            }
            return authRepo.currentUser?.displayTitle ?? "Профиль"
        }
        return "Профиль"
    }

    private var columns: [GridItem] {
        let spacing: CGFloat = cardDensity == .compact ? 8 : 16
        let minWidth: CGFloat = cardDensity == .compact ? 95 : 105
        return [GridItem(.adaptive(minimum: minWidth), spacing: spacing)]
    }

    private func favorites(for category: FavoriteCategory) -> [FavoriteDto] {
        category.filterFavorites(favoritesRepo.favorites)
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
            ProfileCategoryContentView(
                selectedCategory: $selectedCategory,
                categoryCounts: categoryCounts,
                favoritesRepo: favoritesRepo,
                favorites: filteredFavorites,
                navigationTransition: navigationTransition,
                columns: columns,
                cardDensity: cardDensity,
                directPlaybackMovie: $directPlaybackMovie
            )
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    avatarHeaderButton
                        .tint(authRepo.isAuthenticated ? .primary : Color.slooshAccent)
                }

                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showsTierLists = true
                    } label: {
                        Image(systemName: "list.star")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .glassForeground()
                    }
                    .tint(.primary)
                    .accessibilityLabel("Тир-листы")
                }

                ToolbarItem(placement: .principal) {
                    Text(profileHeaderTitle)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.prepare()
                        generator.impactOccurred()
                        showsDownloads = true
                    } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)
                            .glassForeground()
                    }
                    .tint(.primary)
                    .accessibilityLabel("Загрузки")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.prepare()
                        generator.impactOccurred()
                        showsSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.primary)
                            .glassForeground()
                    }
                    .tint(.primary)
                    .accessibilityLabel("Настройки")
                }
            }
            .navigationDestination(isPresented: $showsDownloads) {
                DownloadsView()
            }
            .navigationDestination(isPresented: $showsTierLists) {
                TierListsHomeView()
            }
            .navigationDestination(item: $deepLinkTierId) { tierId in
                TierListViewerView(listId: tierId, initialList: nil)
            }
            .onReceive(DeepLinkManager.shared.$targetTierId) { tierId in
                guard let tierId, !tierId.isEmpty else { return }
                deepLinkTierId = tierId
                DeepLinkManager.shared.clearTierTarget()
            }
            .navigationDestination(isPresented: $showsSettings) {
                SettingsView()
            }
            .fullScreenCover(isPresented: $showAuthSheet) {
                AuthView()
            }
            .sheet(isPresented: $showEditProfileSheet) {
                EditProfileSheet()
            }
            .sheet(isPresented: $showAdminDashboard) {
                AdminDashboardView()
            }
            .navigationDestination(isPresented: $showMyProfile) {
                if let user = authRepo.currentUser {
                    let displayName = (user.displayName?.isEmpty == false ? user.displayName! : nil) ?? user.displayTitle
                    let slooshUser = SlooshUser(
                        id: user.id,
                        displayName: displayName,
                        tag: user.tag,
                        avatarUrl: user.photoURL
                    )
                    UserProfileDetailView(user: slooshUser, chatContext: false)
                }
            }
            .alert(
                "Выйти из аккаунта?",
                isPresented: $showSignOutAlert
            ) {
                Button("Выйти", role: .destructive) {
                    authRepo.signOut()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text("Вы действительно хотите выйти из своего аккаунта?")
            }
            .sheet(item: $directPlaybackMovie, onDismiss: {
                if let pending = pendingPlayerConfig {
                    pendingPlayerConfig = nil
                    DispatchQueue.main.async {
                        playerConfig = pending
                    }
                }
            }) { movie in
                HomeDirectPlayWrapper(
                    movieId: movie.id,
                    fallbackTitle: movie.title ?? movie.name ?? movie.originalTitle ?? "",
                    initialKpId: movie.externalIds?.kp
                ) { config in
                    pendingPlayerConfig = config
                    directPlaybackMovie = nil
                }
            }
            .fullScreenCover(item: $playerConfig, onDismiss: {
                playerConfig = nil
            }) { config in
                PlayerView(config: config)
                    .preferredColorScheme(.dark)
                    .environment(\.colorScheme, .dark)
            }
            .onAppear {
                Task {
                    await CloudSyncService.shared.syncAllDataAsync()
                    favoritesRepo.reloadFromDb()
                }
            }
        }
    }

    // MARK: - Avatar Header Menu

    @ViewBuilder
    private var avatarHeaderButton: some View {
        if authRepo.isAuthenticated {
            Menu {
                if authRepo.isAdmin {
                    Button {
                        showAdminDashboard = true
                    } label: {
                        Label("Панель управления", systemImage: "shield.fill")
                    }
                }

                Button {
                    showMyProfile = true
                } label: {
                    Label("Мой профиль", systemImage: "person.crop.circle")
                }

                Button {
                    showEditProfileSheet = true
                } label: {
                    Label("Редактировать профиль", systemImage: "pencil")
                }

                Button {
                    Task {
                        await CloudSyncService.shared.syncAllDataAsync()
                        favoritesRepo.reloadFromDb()
                    }
                } label: {
                    Label("Синхронизировать", systemImage: "arrow.triangle.2.circlepath")
                }

                Divider()

                Button(role: .destructive) {
                    showSignOutAlert = true
                } label: {
                    Label {
                        Text("Выйти из аккаунта")
                    } icon: {
                        if let img = UIImage(systemName: "rectangle.portrait.and.arrow.right")?.withTintColor(.systemRed, renderingMode: .alwaysOriginal) {
                            Image(uiImage: img)
                        } else {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
                .tint(.red)
            } label: {
                ProfileAvatarButton(user: authRepo.currentUser)
            }
            .menuOrder(.priority)
        } else {
            Button {
                showAuthSheet = true
            } label: {
                ProfileAvatarButton(user: nil)
            }
        }
    }
}

/// Avatar button in Profile Header
private struct ProfileAvatarButton: View {
    let user: UserProfile?

    private var isAuthenticated: Bool {
        guard let user else { return false }
        return !user.isAnonymous
    }

    var body: some View {
        if isAuthenticated {
            SlooshAvatarView(userProfile: user, size: 30)
                .clipShape(Circle())
                .contentShape(Circle())
        } else {
            signInButton
        }
    }

    private var signInButton: some View {
        Text("Войти")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.slooshAccent)
    }
}

struct ProfileCategoryContentView: View {
    @Binding var selectedCategory: FavoriteCategory
    let categoryCounts: [FavoriteCategory: Int]
    @ObservedObject var favoritesRepo: FavoritesRepository
    let favorites: [FavoriteDto]
    let navigationTransition: Namespace.ID
    let columns: [GridItem]
    let cardDensity: CardDensity
    @Binding var directPlaybackMovie: MediaDto?

    @State private var requestedCategory: FavoriteCategory? = nil
    @State private var metrics = HorizontalGalleryMetricsBox<FavoriteCategory>()

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                Color.clear.frame(height: 0).id("profile-scroll-top")

                ProfileGalleryStageView(
                    selectedCategory: $selectedCategory,
                    requestedCategory: $requestedCategory,
                    categoryCounts: categoryCounts,
                    favoritesRepo: favoritesRepo,
                    activeFavorites: favorites,
                    navigationTransition: navigationTransition,
                    columns: columns,
                    cardDensity: cardDensity,
                    metrics: metrics,
                    scrollProxy: scrollProxy,
                    directPlaybackMovie: $directPlaybackMovie
                )
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .onScrollGeometryChange(for: HorizontalGalleryScrollMetrics.self) { geometry in
                HorizontalGalleryScrollMetrics.from(geometry)
            } action: { _, newMetrics in
                metrics.apply(newMetrics)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .all)
            .refreshable {
                await CloudSyncService.shared.syncAllDataAsync(force: true)
                favoritesRepo.reloadFromDb()
            }
        }
    }
}

private struct ProfileGalleryStageView: View {
    @Binding var selectedCategory: FavoriteCategory
    @Binding var requestedCategory: FavoriteCategory?
    let categoryCounts: [FavoriteCategory: Int]
    @ObservedObject var favoritesRepo: FavoritesRepository
    let activeFavorites: [FavoriteDto]
    let navigationTransition: Namespace.ID
    let columns: [GridItem]
    let cardDensity: CardDensity
    let metrics: HorizontalGalleryMetricsBox<FavoriteCategory>
    let scrollProxy: ScrollViewProxy
    @Binding var directPlaybackMovie: MediaDto?

    @StateObject private var swipe = HorizontalGallerySwipeController<FavoriteCategory>()

    var body: some View {
        let all = FavoriteCategory.allCases
        let activeCategory = selectedCategory
        let pageWidth = max(1, metrics.width)
        let fullPageHeight = max(UIScreen.main.bounds.height, metrics.fullHeight)
        let stepStride = pageWidth + HorizontalGallerySwipeController<FavoriteCategory>.pageGap
        let offset = swipe.effectiveOffset(current: activeCategory, in: all, pageWidth: pageWidth)

        ZStack(alignment: .topLeading) {
            ForEach(swipe.visibleCategories(current: activeCategory, in: all), id: \.self) { cat in
                let isActive = cat == activeCategory
                let catFavorites = isActive ? activeFavorites : cat.filterFavorites(favoritesRepo.favorites)
                let hasContent = !favoritesRepo.favorites.isEmpty && !catFavorites.isEmpty
                let rawSavedY = isActive ? 0 : (metrics.savedScrollOffsets[cat] ?? 0)
                let savedY = hasContent ? rawSavedY : 0
                let topBleed = metrics.topBleed(isActive: isActive, savedY: savedY, extraTopMargin: 6)
                let xPos = isActive ? offset : (offset + (swipe.slideDirection > 0 ? stepStride : -stepStride))
                let yPos = isActive ? 0 : (metrics.topOffset - topBleed)
                let clipHeight: CGFloat? = isActive ? nil : (fullPageHeight + topBleed)

                EquatableView(
                    content: ProfileFavoritePageView(
                        category: cat,
                        categoryCounts: categoryCounts,
                        hasAnyFavorites: !favoritesRepo.favorites.isEmpty,
                        favorites: catFavorites,
                        columns: columns,
                        cardDensity: cardDensity,
                        navigationTransition: navigationTransition,
                        onSelectCategory: { tapped in
                            requestedCategory = tapped
                        },
                        onDirectPlay: { media in
                            directPlaybackMovie = media
                        },
                        onDeleteFavorite: { favorite in
                            if let mediaId = favorite.mediaId, let type = favorite.type {
                                favoritesRepo.removeFromFavorites(mediaId: mediaId, mediaType: type)
                            }
                        }
                    )
                )
                .offset(y: isActive ? 0 : -(savedY - topBleed))
                .frame(width: pageWidth, height: clipHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(isActive)
                .offset(x: xPos, y: yPos)
            }
        }
        .background(
            HorizontalGallerySwipeAttachment(
                onBegan: { translationX in
                    swipe.handlePanBegan(
                        translationX,
                        metrics: metrics,
                        current: selectedCategory,
                        in: all,
                        pageWidth: pageWidth,
                        isStillCurrent: { target in
                            selectedCategory == target
                        },
                        onCommitState: { target in
                            selectedCategory = target
                        }
                    )
                },
                onChanged: { translationX in
                    swipe.handlePanChanged(
                        translationX,
                        metrics: metrics,
                        current: selectedCategory,
                        in: all,
                        pageWidth: pageWidth,
                        isStillCurrent: { target in
                            selectedCategory == target
                        },
                        onCommitState: { target in
                            selectedCategory = target
                        }
                    )
                },
                onEnded: { translationX, velocityX, didFinish in
                    swipe.handlePanEnded(
                        translationX,
                        velocityX: velocityX,
                        didFinish: didFinish,
                        metrics: metrics,
                        current: selectedCategory,
                        in: all,
                        pageWidth: pageWidth,
                        isStillCurrent: { target in
                            selectedCategory == target
                        },
                        onCommitState: { target in
                            selectedCategory = target
                        }
                    )
                },
                onScrollViewFound: { sv in
                    if swipe.attachedScrollView !== sv {
                        swipe.attachedScrollView = sv
                    }
                },
                onWindowDismiss: {
                    if swipe.dragOffset != 0 || swipe.slideDirection != 0 {
                        swipe.resetImmediately()
                    }
                }
            )
        )
        .onChange(of: requestedCategory) { _, target in
            guard let target else { return }
            requestedCategory = nil
            swipe.handleRequestedCategoryChange(
                to: target,
                metrics: metrics,
                current: selectedCategory,
                in: all,
                scrollToTop: {
                    withAnimation(.easeOut(duration: 0.22)) {
                        scrollProxy.scrollTo("profile-scroll-top", anchor: .top)
                    }
                },
                isStillCurrent: { next in
                    selectedCategory == next
                },
                onCommitState: { next in
                    selectedCategory = next
                }
            )
        }
    }
}

private struct ProfileFavoritePageView: View, Equatable {
    let category: FavoriteCategory
    let categoryCounts: [FavoriteCategory: Int]
    let hasAnyFavorites: Bool
    let favorites: [FavoriteDto]
    let columns: [GridItem]
    let cardDensity: CardDensity
    let navigationTransition: Namespace.ID
    let onSelectCategory: (FavoriteCategory) -> Void
    let onDirectPlay: (MediaDto) -> Void
    let onDeleteFavorite: (FavoriteDto) -> Void

    private let itemIds: [String]

    init(
        category: FavoriteCategory,
        categoryCounts: [FavoriteCategory: Int],
        hasAnyFavorites: Bool,
        favorites: [FavoriteDto],
        columns: [GridItem],
        cardDensity: CardDensity,
        navigationTransition: Namespace.ID,
        onSelectCategory: @escaping (FavoriteCategory) -> Void,
        onDirectPlay: @escaping (MediaDto) -> Void,
        onDeleteFavorite: @escaping (FavoriteDto) -> Void
    ) {
        self.category = category
        self.categoryCounts = categoryCounts
        self.hasAnyFavorites = hasAnyFavorites
        self.favorites = favorites
        self.columns = columns
        self.cardDensity = cardDensity
        self.navigationTransition = navigationTransition
        self.onSelectCategory = onSelectCategory
        self.onDirectPlay = onDirectPlay
        self.onDeleteFavorite = onDeleteFavorite
        self.itemIds = favorites.map(\.artworkIdentifier)
    }

    static func == (lhs: ProfileFavoritePageView, rhs: ProfileFavoritePageView) -> Bool {
        lhs.category == rhs.category &&
        lhs.categoryCounts == rhs.categoryCounts &&
        lhs.hasAnyFavorites == rhs.hasAnyFavorites &&
        lhs.cardDensity == rhs.cardDensity &&
        lhs.itemIds == rhs.itemIds
    }

    var body: some View {
        VStack(spacing: 14) {
            ProfileCategoryPillStrip(
                selectedCategory: category,
                categoryCounts: categoryCounts,
                onSelect: onSelectCategory
            )

            if !hasAnyFavorites {
                ProfileEmptyState(
                    icon: "heart.slash",
                    title: "Пока ничего не добавлено",
                    message: "Сохраняйте фильмы и сериалы в избранное, чтобы быстро возвращаться к ним позже."
                )
                .padding(.top, 56)
                .padding(.bottom, 48)
            } else if favorites.isEmpty {
                ProfileEmptyState(
                    icon: "film.stack",
                    title: "В этой подборке пока пусто",
                    message: "Попробуйте открыть другую вкладку или добавьте что-нибудь в избранное."
                )
                .padding(.top, 56)
                .padding(.bottom, 48)
            } else {
                let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                let padding: CGFloat = cardDensity == .compact ? 12 : 16
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(favorites, id: \.artworkIdentifier) { favorite in
                        let media = favorite.toMediaDto()
                        MovieDetailsNavigationLink(movie: media, navigationTransition: navigationTransition, refreshArtwork: true)
                            .contextMenu {
                                Group {
                                    Button {
                                        onDirectPlay(media)
                                    } label: {
                                        Label("Смотреть", systemImage: "play.fill")
                                    }

                                    NavigationLink(destination: DetailsView(movieId: media.id, mediaType: media.type, navigationTransitionID: nil, navigationTransitionNamespace: nil)) {
                                        Label("Подробнее", systemImage: "info.circle")
                                    }

                                    Button(role: .destructive) {
                                        onDeleteFavorite(favorite)
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

private struct ProfileCategoryPillStrip: View {
    let selectedCategory: FavoriteCategory
    let categoryCounts: [FavoriteCategory: Int]
    let onSelect: (FavoriteCategory) -> Void

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FavoriteCategory.allCases, id: \.self) { category in
                        let isSelected = selectedCategory == category
                        let count = categoryCounts[category] ?? 0
                        Button {
                            onSelect(category)
                        } label: {
                            HStack(spacing: 5) {
                                Text(category.title)
                                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(isSelected ? Color.secondary : Color.secondary.opacity(0.65))
                                }
                            }
                            .lineLimit(1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.14))
                                }
                            }
                            .contentShape(.capsule)
                            .glassEffect(.regular.interactive(), in: .capsule)
                        }
                        .buttonStyle(.glassPress)
                        .id(category)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollClipDisabled()
            .onAppear {
                scrollProxy.scrollTo(selectedCategory, anchor: .center)
            }
            .onChange(of: selectedCategory) { _, newCategory in
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    scrollProxy.scrollTo(newCategory, anchor: .center)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedCategory)
    }
}
