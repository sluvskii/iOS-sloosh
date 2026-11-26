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
                .sharedBackgroundVisibility(authRepo.isAuthenticated ? .hidden : .automatic)

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
                    .frame(width: 38, height: 38)
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .contentShape(.contextMenuPreview, Circle())
            }
            .menuOrder(.priority)
            .buttonStyle(.plain)
            .frame(width: 38, height: 38)
            .clipShape(Circle())
            .contentShape(Circle())
            .contentShape(.contextMenuPreview, Circle())
        } else {
            Button {
                showAuthSheet = true
            } label: {
                ProfileAvatarButton(user: nil)
            }
            .buttonStyle(.plain)
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
            SlooshAvatarView(userProfile: user, size: 36)
                .frame(width: 36, height: 36)
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

    private func switchCategory(by step: Int) {
        let all = FavoriteCategory.allCases
        guard let currentIndex = all.firstIndex(of: selectedCategory) else { return }
        let targetIndex = currentIndex + step
        guard targetIndex >= 0 && targetIndex < all.count else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.88)) {
            selectedCategory = all[targetIndex]
        }
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                Color.clear.frame(height: 0).id("profile-scroll-top")

                VStack(spacing: 14) {
                    ProfileCategoryPillStrip(
                        selectedCategory: $selectedCategory,
                        categoryCounts: categoryCounts
                    )

                    Group {
                        if favoritesRepo.favorites.isEmpty {
                            ProfileEmptyState(
                                icon: "heart.slash",
                                title: "Пока ничего не добавлено",
                                message: "Сохраняйте фильмы и сериалы в избранное, чтобы быстро возвращаться к ним позже."
                            )
                            .padding(.top, 72)
                            .padding(.bottom, 48)
                        } else if favorites.isEmpty {
                            ProfileEmptyState(
                                icon: "film.stack",
                                title: "В этой подборке пока пусто",
                                message: "Попробуйте открыть другую вкладку или добавьте что-нибудь в избранное."
                            )
                            .padding(.top, 72)
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
                                                directPlaybackMovie = media
                                            } label: {
                                                Label("Смотреть", systemImage: "play.fill")
                                            }

                                            NavigationLink(destination: DetailsView(movieId: media.id, mediaType: media.type, navigationTransitionID: nil, navigationTransitionNamespace: nil)) {
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
                    .id(selectedCategory)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: selectedCategory)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 45, coordinateSpace: .local)
                            .onEnded { value in
                                let dx = value.translation.width
                                let dy = value.translation.height
                                guard abs(dx) > 70, abs(dx) > abs(dy) * 1.8, abs(value.predictedEndTranslation.width) > 90 else { return }
                                switchCategory(by: dx < 0 ? 1 : -1)
                            }
                    )
                }
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .refreshable {
                await CloudSyncService.shared.syncAllDataAsync(force: true)
                favoritesRepo.reloadFromDb()
            }
            .onChange(of: selectedCategory) { _, _ in
                withAnimation(.easeOut(duration: 0.22)) {
                    scrollProxy.scrollTo("profile-scroll-top", anchor: .top)
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
        AppEmptyStateView(
            icon: icon,
            title: title,
            description: message
        )
    }
}

private struct ProfileCategoryPillStrip: View {
    @Binding var selectedCategory: FavoriteCategory
    let categoryCounts: [FavoriteCategory: Int]

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(FavoriteCategory.allCases, id: \.self) { category in
                        let isSelected = selectedCategory == category
                        let count = categoryCounts[category] ?? 0
                        Button {
                            guard !isSelected else { return }
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                selectedCategory = category
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Text(category.title)
                                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
                                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)

                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(isSelected ? Color.secondary : Color.secondary.opacity(0.65))
                                }
                            }
                            .lineLimit(1)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
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
