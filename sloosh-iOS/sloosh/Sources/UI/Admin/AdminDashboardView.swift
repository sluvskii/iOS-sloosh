import SwiftUI

// MARK: - Admin Dashboard View (iOS 26+ Edge-to-Edge Liquid Glass)

public struct AdminDashboardView: View {
    @StateObject private var repo = AdminRepository.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab: AdminTab = .analytics
    @State private var userSearchQuery: String = ""
    @State private var channelSearchQuery: String = ""
    @State private var analyticsSearchQuery: String = ""
    @State private var selectedUserForDetails: AdminUserItem? = nil
    @State private var channelToDelete: ChannelModel? = nil
    @State private var showDeleteChannelAlert: Bool = false

    @ScaledMetric(relativeTo: .headline) private var tabTitleSize: CGFloat = 20
    private let tabTitleHeight: CGFloat = 34
    private let tabSpacing: CGFloat = 16
    private let tabEdgeContentInset: CGFloat = 16
    private var tabScrollAnimation: Animation {
        .spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.1)
    }

    private enum AdminTab: String, CaseIterable, Identifiable {
        case analytics = "Аналитика"
        case users = "Пользователи"
        case channels = "Каналы"
        case diagnostics = "Система"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .analytics: return "chart.xyaxis.line"
            case .users: return "person.2.fill"
            case .channels: return "megaphone.fill"
            case .diagnostics: return "waveform.path.ecg"
            }
        }
    }

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                switch selectedTab {
                case .analytics:
                    analyticsTab
                        .transition(.opacity)
                case .users:
                    usersTab
                        .transition(.opacity)
                case .channels:
                    channelsTab
                        .transition(.opacity)
                case .diagnostics:
                    diagnosticsTab
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedTab)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                customTopHeader
            }
            .sheet(item: $selectedUserForDetails) { user in
                AdminUserDetailSheet(user: user)
            }
            .task {
                await repo.fetchOverviewStats()
            }
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Custom Top Header (Liquid Glass & Progressive Variable Blur)

    private var customTopHeader: some View {
        VStack(spacing: 12) {
            // Header Bar (Title & Actions)
            ZStack {
                Text("Панель управления")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .allowsHitTesting(false)

                HStack {
                    // Refresh Button (44x44 TelegramGlassIconButton)
                    AdminRefreshButton(repo: repo) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        Task {
                            await repo.fetchOverviewStats()
                        }
                    }

                    Spacer()

                    // Close Button (44x44 TelegramGlassIconButton)
                    TelegramGlassIconButton(systemName: "xmark", iconSize: 17, buttonSize: 44) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            // Category Text Tabs
            tabSelector
                .padding(.bottom, 4)
        }
        .padding(.bottom, 2)
        .background(
            VariableBlurView(tintColor: .clear, tintOpacity: 0.0)
                .padding(.bottom, -30)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: - Native Liquid Glass Text Tab Selector (Matching HomeView)

    private func layeredTabTitle(
        _ text: String,
        size: CGFloat,
        weight: Font.Weight,
        isSelected: Bool
    ) -> some View {
        let isDark = colorScheme == .dark
        let opacity = isSelected ? (isDark ? 0.95 : 0.9) : (isDark ? 0.45 : 0.4)
        let color = isDark ? Color.white.opacity(opacity) : Color.black.opacity(opacity)
        let blendMode: BlendMode = isDark ? .plusLighter : .plusDarker

        return Text(text)
            .font(.system(size: size, weight: weight))
            .tracking(-0.6)
            .foregroundStyle(color)
            .blendMode(blendMode)
    }

    private var tabSelector: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: tabSpacing) {
                    ForEach(Array(AdminTab.allCases.enumerated()), id: \.element) { index, tab in
                        let isSelected = selectedTab == tab
                        let isFirst = index == 0
                        let isLast = index == AdminTab.allCases.count - 1

                        Button {
                            withAnimation(tabScrollAnimation) {
                                guard !isSelected else { return }
                                selectedTab = tab
                            }
                        } label: {
                            layeredTabTitle(
                                tab.rawValue,
                                size: tabTitleSize,
                                weight: isSelected ? .bold : .semibold,
                                isSelected: isSelected
                            )
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(height: tabTitleHeight, alignment: .center)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(AdminTabScaleButtonStyle())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .id(tab)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                        .padding(.leading, isFirst ? tabEdgeContentInset : 0)
                        .padding(.trailing, isLast ? tabEdgeContentInset : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollTargetLayout()
            }
            .frame(height: tabTitleHeight + 4, alignment: .topLeading)
            .scrollClipDisabled()
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .animation(tabScrollAnimation, value: selectedTab)
            .onAppear {
                scrollProxy.scrollTo(selectedTab, anchor: .center)
            }
            .onChange(of: selectedTab) { _, newTab in
                withAnimation(tabScrollAnimation) {
                    scrollProxy.scrollTo(newTab, anchor: .center)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    // MARK: - Tab 1: Analytics & Live Activity

    private var analyticsTab: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Unified Hero KPI Dashboard (3-column)
                unifiedKpiCard

                // 2. Section: Сейчас смотрят (Now Playing Feed)
                liveWatchingSection

                // 3. Section: Рейтинг озвучек платформы
                globalTranslationsSection

                // 4. Section: Выбор озвучки по тайтлам
                mediaAnalyticsSection
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
    }

    private var unifiedKpiCard: some View {
        HStack(spacing: 0) {
            // Col 1: Аудитория
            VStack(alignment: .leading, spacing: 3) {
                Text("АУДИТОРИЯ")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.6)

                Text("\(repo.stats.totalUsers)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text("\(repo.stats.onlineUsers) в сети" + (repo.stats.guestUsersCount > 0 ? " • \(repo.stats.guestUsersCount) г." : ""))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 38)
                .padding(.horizontal, 12)

            // Col 2: Смотрят сейчас
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(repo.stats.watchingNowCount > 0 ? Color.primary : Color.secondary)
                        .frame(width: 5, height: 5)
                        .opacity(repo.stats.watchingNowCount > 0 ? 0.9 : 0.4)

                    Text("СМОТРЯТ")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .tracking(0.6)
                }

                Text("\(repo.stats.watchingNowCount)")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Text(repo.stats.watchingNowCount > 0 ? "активных сессий" : "нет просмотров")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 38)
                .padding(.horizontal, 12)

            // Col 3: Топ озвучка
            VStack(alignment: .leading, spacing: 3) {
                Text("ТОП ОЗВУЧКА")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.6)

                Text(repo.stats.topGlobalTranslation)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("выбор большинства")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var liveWatchingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Сейчас смотрят")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                if repo.stats.watchingNowCount > 0 {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.primary)
                            .frame(width: 4, height: 4)
                        Text("\(repo.stats.watchingNowCount)")
                    }
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08))
                    .clipShape(Capsule())
                }

                Spacer()

                if repo.stats.liveWatchingSessions.count > 1 {
                    Text("В реальном времени")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 2)

            if repo.stats.liveWatchingSessions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "play.slash")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)

                    Text("Сейчас никто не воспроизводит видео")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(14)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(repo.stats.liveWatchingSessions) { session in
                            liveWatchingCard(session)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
    }

    private func liveWatchingCard(_ session: LiveSessionItem) -> some View {
        HStack(spacing: 10) {
            if let poster = session.media?.posterUrl, let url = URL(string: poster) {
                AsyncCachedImage(url: url) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.18))
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .frame(width: 44, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                    Image(systemName: "film")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .frame(width: 44, height: 64)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.primary.opacity(0.8))
                        .frame(width: 4, height: 4)

                    Text(session.displayTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Text(session.media?.title ?? "Видео")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if let epTitle = session.media?.displayEpisodeTitle {
                    Text(epTitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let trans = session.media?.translation {
                    Text(trans)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(Capsule())
                }
            }
            .frame(width: 160, alignment: .leading)
        }
        .padding(10)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var globalTranslationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Рейтинг озвучек")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                Text("Выбор зрителей по всей платформе")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 2)

            if repo.globalTranslations.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "waveform")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)

                    Text("Данные накапливаются при первых просмотрах")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)

                    Spacer()
                }
                .padding(14)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    ForEach(Array(repo.globalTranslations.prefix(6).enumerated()), id: \.element.id) { index, item in
                        translationRankRow(rank: index + 1, item: item)
                        if index < min(5, repo.globalTranslations.count - 1) {
                            Divider()
                        }
                    }
                }
                .padding(14)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }

    private func translationRankRow(rank: Int, item: GlobalTranslationStat) -> some View {
        VStack(spacing: 5) {
            HStack {
                Text("#\(rank)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(rank == 1 ? .primary : .secondary)
                    .frame(width: 22, alignment: .leading)

                Text(item.translation)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()

                Text("\(String(format: "%.0f", item.percentage))% • \(item.count) чел.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 4)

                    Capsule()
                        .fill(Color.primary.opacity(rank == 1 ? 0.85 : 0.45))
                        .frame(width: max(6, geo.size.width * CGFloat(item.percentage / 100.0)), height: 4)
                }
            }
            .frame(height: 4)
        }
    }

    private var filteredMediaAnalytics: [MediaAnalyticsStats] {
        let q = analyticsSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return repo.mediaAnalytics }
        return repo.mediaAnalytics.filter { m in
            m.title.lowercased().contains(q) || m.mediaKey.lowercased().contains(q)
        }
    }

    private var mediaAnalyticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Статистика по тайтлам")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.primary)
                .padding(.horizontal, 2)

            // Search Bar
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                TextField("Поиск фильма или сериала...", text: $analyticsSearchQuery)
                    .font(.system(size: 14))

                if !analyticsSearchQuery.isEmpty {
                    Button { analyticsSearchQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(in: Capsule())

            if filteredMediaAnalytics.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "film.stack")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                    Text(analyticsSearchQuery.isEmpty ? "Пока нет данных о выборе озвучек" : "Ничего не найдено")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(filteredMediaAnalytics) { mediaStats in
                        mediaAnalyticsCard(mediaStats)
                    }
                }
            }
        }
    }

    private func mediaAnalyticsCard(_ media: MediaAnalyticsStats) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let poster = media.posterUrl, let url = URL(string: poster) {
                    AsyncCachedImage(url: url) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.18))
                    } content: { image in
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                    .frame(width: 38, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(media.title)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    Text("Выборов: \(media.totalPlays)")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)

                    if let top = media.topTranslation {
                        HStack(spacing: 4) {
                            Text("Топ:")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("\(top.translation) (\(String(format: "%.0f", top.percentage))%)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    }
                }

                Spacer()
            }

            if !media.translations.isEmpty {
                Divider()

                VStack(spacing: 5) {
                    ForEach(media.translations) { vote in
                        HStack {
                            Text(vote.translation)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(String(format: "%.0f", vote.percentage))% • \(vote.count) чел.")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(vote.id == media.topTranslation?.id ? .primary : .secondary)
                        }
                    }
                }
            }
        }
        .padding(12)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Tab 2: Users Management

    private var filteredUsers: [AdminUserItem] {
        let query = userSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return repo.users }
        return repo.users.filter { u in
            u.displayName.lowercased().contains(query) ||
            (u.tag?.lowercased().contains(query) ?? false) ||
            u.id.lowercased().contains(query) ||
            (u.email?.lowercased().contains(query) ?? false)
        }
    }

    private var usersTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header Summary Card
                HStack {
                    Text("\(repo.users.count) пользователей")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Text("\(repo.stats.onlineUsers) онлайн")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    let banned = repo.users.filter { $0.isBanned }.count
                    if banned > 0 {
                        Text("•")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                        Text("\(banned) в бане")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(in: Capsule())

                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    TextField("Поиск по имени, @тегу, email или ID...", text: $userSearchQuery)
                        .font(.system(size: 14))

                    if !userSearchQuery.isEmpty {
                        Button { userSearchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(in: Capsule())

                // List
                if filteredUsers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("Пользователи не найдены")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredUsers) { user in
                            userRow(user)
                                .onTapGesture {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    selectedUserForDetails = user
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
    }

    private func userRow(_ user: AdminUserItem) -> some View {
        HStack(spacing: 10) {
            SlooshAvatarView(
                avatarSource: user.avatarUrl,
                fallbackText: user.displayTitle,
                size: 40,
                showOnline: true,
                isOnline: user.isCurrentlyOnline
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(user.displayTitle)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if user.isBanned {
                        Text("Бан")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.08))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
                    if !user.displayTag.isEmpty {
                        Text(user.displayTag)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    if !user.displayTag.isEmpty && !user.statusDescription.isEmpty {
                        Text("•")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Text(user.statusDescription)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Menu {
                Button {
                    UIPasteboard.general.string = user.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    ToastManager.shared.show(title: "ID скопирован", icon: "doc.on.doc")
                } label: {
                    Label("Скопировать ID", systemImage: "doc.on.doc")
                }

                if let tag = user.tag, !tag.isEmpty {
                    Button {
                        UIPasteboard.general.string = "@\(tag)"
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        ToastManager.shared.show(title: "Тег скопирован", icon: "at")
                    } label: {
                        Label("Скопировать @тег", systemImage: "at")
                    }
                }

                Button {
                    selectedUserForDetails = user
                } label: {
                    Label("Подробнее", systemImage: "info.circle")
                }

                Divider()

                Button(role: user.isBanned ? .none : .destructive) {
                    Task {
                        _ = await repo.toggleBanUser(userId: user.id, isBanned: !user.isBanned)
                    }
                } label: {
                    Label(user.isBanned ? "Разблокировать" : "Заблокировать", systemImage: user.isBanned ? "checkmark.circle" : "nosign")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .padding(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Tab 3: Channels Moderation & Messenger Metrics

    private var filteredChannels: [ChannelModel] {
        let query = channelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return repo.channels }
        return repo.channels.filter { ch in
            ch.name.lowercased().contains(query) ||
            ch.tag.lowercased().contains(query) ||
            ch.ownerId.lowercased().contains(query)
        }
    }

    private var channelsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Unified Messenger Stats Card (4-column)
                HStack(spacing: 0) {
                    channelStatPod(title: "КАНАЛЫ", value: "\(repo.stats.totalChannels)")
                    Divider().frame(height: 28).padding(.horizontal, 8)
                    channelStatPod(title: "ПОСТЫ", value: "\(repo.stats.totalPosts)")
                    Divider().frame(height: 28).padding(.horizontal, 8)
                    channelStatPod(title: "ПРОСМОТРЫ", value: formatCount(repo.stats.totalViews))
                    Divider().frame(height: 28).padding(.horizontal, 8)
                    channelStatPod(title: "РЕАКЦИИ", value: "\(repo.stats.totalReactions)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Search Bar
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)

                    TextField("Поиск по названию или @тегу канала...", text: $channelSearchQuery)
                        .font(.system(size: 14))

                    if !channelSearchQuery.isEmpty {
                        Button { channelSearchQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .glassEffect(in: Capsule())

                // List
                if filteredChannels.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "megaphone")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary)
                        Text("Каналы не найдены")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredChannels) { channel in
                            channelRow(channel)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
        .confirmationDialog(
            "Удалить канал?",
            isPresented: $showDeleteChannelAlert,
            titleVisibility: .visible
        ) {
            Button("Удалить канал навсегда", role: .destructive) {
                if let ch = channelToDelete {
                    Task {
                        _ = await repo.deleteChannel(channelId: ch.id)
                    }
                }
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    private func channelStatPod(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func channelRow(_ channel: ChannelModel) -> some View {
        HStack(spacing: 10) {
            SlooshAvatarView(channel: channel, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(channel.name)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(channel.displayTag)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)

                    Text(channel.formattedSubscriberCount)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button {
                channelToDelete = channel
                showDeleteChannelAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .padding(8)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Tab 4: System Diagnostics

    private var diagnosticsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Subsystems status
                HStack(spacing: 12) {
                    systemSubpod(title: "Сеть", status: "В норме")
                    systemSubpod(title: "Медиа-сервер", status: "В норме")
                    systemSubpod(title: "База данных", status: "В норме")
                }
                .padding(12)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                // Header with Clear
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Журнал диагностики")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)
                        Text("Системные события и ошибки приложения")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Очистить") {
                        AppDiagnostics.shared.clearLogs()
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 2)
                .padding(.top, 4)

                let logs = AppDiagnostics.shared.recentLogs
                if logs.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Ошибок не зафиксировано")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("Все компоненты работают штатно")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(14)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    VStack(spacing: 6) {
                        ForEach(Array(logs.enumerated()), id: \.offset) { _, log in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)

                                Text(log)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(10)
                            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollContentBackground(.hidden)
    }

    private func systemSubpod(title: String, status: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
            HStack(spacing: 4) {
                Circle().fill(Color.primary.opacity(0.7)).frame(width: 4, height: 4)
                Text(status)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }
}

// MARK: - Admin User Detail Sheet

private struct AdminUserDetailSheet: View {
    let user: AdminUserItem
    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = AdminRepository.shared
    @State private var isBannedState: Bool = false

    init(user: AdminUserItem) {
        self.user = user
        _isBannedState = State(initialValue: user.isBanned)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    // Avatar & Names
                    VStack(spacing: 8) {
                        SlooshAvatarView(
                            avatarSource: user.avatarUrl,
                            fallbackText: user.displayTitle,
                            size: 72,
                            showOnline: true,
                            isOnline: user.isCurrentlyOnline
                        )

                        VStack(spacing: 3) {
                            Text(user.displayTitle)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.primary)

                            if !user.displayTag.isEmpty {
                                Text(user.displayTag)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }

                            Text(user.statusDescription)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 12)

                    // Details Card
                    VStack(spacing: 10) {
                        detailRow(title: "User ID", value: user.id, canCopy: true)
                        Divider()
                        detailRow(title: "Тег", value: user.displayTag.isEmpty ? "Не указан" : user.displayTag, canCopy: !user.displayTag.isEmpty)
                        if let email = user.email, !email.isEmpty {
                            Divider()
                            detailRow(title: "Email", value: email, canCopy: true)
                        }
                        Divider()
                        detailRow(title: "Каналов создано", value: "\(user.channelsCount)", canCopy: false)
                        Divider()
                        detailRow(title: "Статус", value: isBannedState ? "Заблокирован" : "Активен", canCopy: false)
                    }
                    .padding(14)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.horizontal, 16)

                    // Moderation Button
                    Button {
                        Task {
                            let newBan = !isBannedState
                            let success = await repo.toggleBanUser(userId: user.id, isBanned: newBan)
                            if success {
                                isBannedState = newBan
                                ToastManager.shared.show(
                                    title: newBan ? "Пользователь заблокирован" : "Пользователь разблокирован",
                                    icon: newBan ? "nosign" : "checkmark.circle"
                                )
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isBannedState ? "checkmark.circle" : "nosign")
                            Text(isBannedState ? "Разблокировать доступ" : "Заблокировать пользователя")
                        }
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundColor(isBannedState ? .primary : .red.opacity(0.9))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassEffect(in: Capsule())
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 32)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Профиль пользователя")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.primary)
                }
            }
        }
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
    }

    private func detailRow(title: String, value: String, canCopy: Bool) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundColor(.primary)
                .lineLimit(1)

            if canCopy {
                Button {
                    UIPasteboard.general.string = value
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    ToastManager.shared.show(title: "Скопировано", icon: "doc.on.doc")
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Admin Tab Scale Button Style (Tactile Spring Feedback)

private struct AdminTabScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Admin Refresh Button (UIKit-backed Telegram Glass Button)

private struct AdminRefreshButton: View {
    @ObservedObject var repo: AdminRepository
    let action: () -> Void

    var body: some View {
        ZStack {
            TelegramGlassIconButton(
                systemName: repo.isLoading ? "" : "arrow.clockwise",
                iconSize: 18,
                buttonSize: 44
            ) {
                action()
            }

            if repo.isLoading {
                ProgressView()
                    .scaleEffect(0.9)
                    .allowsHitTesting(false)
            }
        }
    }
}

