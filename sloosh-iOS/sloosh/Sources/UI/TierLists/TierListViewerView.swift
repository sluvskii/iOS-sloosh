import SwiftUI
import Photos

/// Публичный просмотрщик тир-листа: шапка с автором, доска read-only,
/// лайк, шаринг (картинка/сторис/ссылка/друзьям) и ремикс в свой редактор.
struct TierListViewerView: View {
    let listId: String
    var initialList: TierList?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = TierListsRepository.shared
    @State private var list: TierList?
    @State private var isLoading = true
    @State private var isLiked = false
    @State private var showAuthorProfile = false
    @State private var showRemixEditor = false
    @State private var showFriendSheet = false
    @State private var detailsItem: TierListItem?
    @State private var shareImage: UIImage?
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var exportError: String?
    @State private var scrollOffset: CGFloat = 0

    enum ExportTarget { case board, stories, photos }

    var body: some View {
        ZStack {
            if isLoading && list == nil {
                ProgressView()
                    .tint(Color.slooshAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let list {
                listContent(list)
            } else {
                AppEmptyStateView(
                    icon: "list.star",
                    title: "Тир-лист не найден",
                    description: "Возможно, автор удалил его"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { viewerHeader }
        .navigationTitle(list?.title ?? "Тир-лист")
        .toolbar(.hidden, for: .navigationBar)
        .background(Color(UIColor.systemBackground))
        .fullWidthSwipeBack()
        .scrollEdgeEffectStyle(.soft, for: .bottom)
        .task { await load() }
        .onChange(of: repo.publicLists) { _, updated in
            if let current = list, let fresh = updated.first(where: { $0.id == current.id }) {
                list = fresh
            }
        }
        .navigationDestination(item: $detailsItem) { item in
            DetailsView(movieId: item.detailsId, mediaType: item.mediaType)
        }
        .navigationDestination(isPresented: $showAuthorProfile) {
            authorDestination
        }
        .navigationDestination(isPresented: $showRemixEditor) {
            remixDestination
        }
        .sheet(isPresented: $showFriendSheet) {
            if let list {
                ShareToFriendSheet(tierList: list)
            }
        }
        .overlay {
            if isExporting {
                exportOverlay
            }
        }
        .overlay {
            if let image = shareImage {
                ShareSheet(items: [image])
                    .onDisappear { shareImage = nil }
            }
        }
        .alert("Не удалось создать картинку", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func load() async {
        var loaded: TierList? = initialList
        if loaded == nil {
            loaded = await TierListsRepository.shared.fetchList(id: listId)
        }
        list = loaded
        isLoading = false
        if let loaded {
            isLiked = TierListsRepository.shared.isLiked(loaded.id)
            TierListsRepository.shared.recordView(loaded.id)
        }
    }

    // MARK: Шапка

    @ViewBuilder
    private var viewerHeader: some View {
        ZStack {
            Text(list?.title ?? "Тир-лист")
                .font(.system(size: 18, weight: .semibold))
                .backdropForeground()
                .lineLimit(1)

            HStack {
                TelegramGlassIconButton(systemName: "chevron.left") {
                    dismiss()
                }
                Spacer()
                viewerMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var viewerMenu: some View {
        Menu {
            Button {
                Task { await export(as: .photos) }
            } label: {
                Label("Сохранить картинку", systemImage: "square.and.arrow.down")
            }
            Button {
                Task { await export(as: .stories) }
            } label: {
                Label("Картинка для сторис", systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
            Button {
                Task { await export(as: .board) }
            } label: {
                Label("Поделиться картинкой", systemImage: "square.and.arrow.up")
            }
            Button {
                showFriendSheet = true
            } label: {
                Label("Отправить друзьям", systemImage: "paperplane")
            }
            Divider()
            Button {
                showRemixEditor = true
            } label: {
                Label("Сделать свой", systemImage: "square.and.pencil")
            }
        } label: {
            TelegramGlassIconButton(systemName: "ellipsis.circle") {}
        }
    }

    // MARK: Контент

    @ViewBuilder
    private func listContent(_ list: TierList) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerSection(list)
                authorRow(list: list)
                statsRow(list: list)
                boardSection(list)
                actionSection(list)
                if list.authorId == AuthRepository.shared.currentUser?.id {
                    deleteOwnListButton(list)
                }
                Spacer(minLength: 40)
            }
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newOffset in
            scrollOffset = newOffset
        }
    }

    // MARK: Секции

    @ViewBuilder
    private func headerSection(_ list: TierList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(list.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 16)
                .padding(.top, 6)
            if let subtitle = list.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func authorRow(list: TierList) -> some View {
        Button {
            showAuthorProfile = true
        } label: {
            HStack(spacing: 10) {
                SlooshAvatarView(avatarSource: list.authorAvatar, fallbackText: list.authorName, size: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text(list.authorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(list.dateText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    private func statBadge(icon: String, value: Int) -> some View {
        Label("\(value)", systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(UIColor.secondarySystemFill), in: Capsule())
    }

    @ViewBuilder
    private func statsRow(list: TierList) -> some View {
        HStack(spacing: 14) {
            statBadge(icon: "heart.fill", value: list.likesCount ?? 0)
            statBadge(icon: "eye", value: list.viewsCount ?? 0)
            statBadge(icon: "film.stack", value: list.itemsCount)
            if list.templateId != nil {
                Label("по шаблону", systemImage: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func boardSection(_ list: TierList) -> some View {
        TierListBoardView(
            mode: .view,
            rows: .constant(list.rows),
            unranked: .constant(list.unranked),
            onTapItem: nil,
            onOpenDetails: { item in
                detailsItem = item
            }
        )
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func actionSection(_ list: TierList) -> some View {
        HStack(spacing: 12) {
            likeButton(list)
            shareImageButton(list)
        }
        .padding(.horizontal, 16)
    }

    private func likeButton(_ current: TierList) -> some View {
        Button {
            Task {
                let (liked, count) = await TierListsRepository.shared.toggleLike(current)
                isLiked = liked
                TierListsRepository.shared.applyLikeCount(listId: current.id, count: count)
                if list?.id == current.id {
                    list?.likesCount = count
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        } label: {
            Label("\(current.likesCount ?? 0)", systemImage: isLiked ? "heart.fill" : "heart")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(isLiked ? Color.red : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    Capsule().fill(isLiked ? Color.red.opacity(0.12) : Color(UIColor.secondarySystemFill))
                )
        }
    }

    private func shareImageButton(_ current: TierList) -> some View {
        Button {
            Task { await export(as: .board) }
        } label: {
            Label("Картинкой", systemImage: "square.and.arrow.up")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Capsule().fill(Color(UIColor.secondarySystemFill)))
        }
    }

    @ViewBuilder
    private func deleteOwnListButton(_ list: TierList) -> some View {
        Button(role: .destructive) {
            Task {
                try? await TierListsRepository.shared.deleteList(id: list.id)
                dismiss()
            }
        } label: {
            Label("Удалить тир-лист", systemImage: "trash")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
    }

    // MARK: Навигационные цели

    @ViewBuilder
    private var authorDestination: some View {
        if let author = list {
            UserProfileDetailView(
                user: SlooshUser(
                    id: author.authorId,
                    displayName: author.authorName,
                    tag: author.authorTag,
                    avatarUrl: author.authorAvatar
                ),
                chatContext: false
            )
        }
    }

    @ViewBuilder
    private var remixDestination: some View {
        if let source = list {
            let remix: TierList = {
                var remix = source
                remix.id = "draft_\(UUID().uuidString)"
                remix.isDraft = true
                remix.authorId = AuthRepository.shared.currentUser?.id ?? ""
                remix.authorName = AuthRepository.shared.currentUser?.displayName ?? ""
                remix.createdAtMs = 0
                remix.updatedAtMs = 0
                remix.likesCount = nil
                remix.viewsCount = nil
                return remix
            }()
            TierListEditorView(
                draft: remix,
                onPublished: { _ in
                    // Публикация ремикса появится в галерее «Мои»
                },
                onDismiss: {}
            )
        }
    }

    // MARK: Экспорт

    @ViewBuilder
    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView(value: exportProgress)
                    .tint(Color.slooshAccent)
                    .frame(width: 240)
                Text("Собираем картинку…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
    }

    private func export(as target: ExportTarget) async {
        guard let list else { return }
        isExporting = true
        exportProgress = 0
        let posters = await TierListImageExporter.loadPosters(for: list) { fraction in
            Task { @MainActor in exportProgress = fraction }
        }
        let author = list.authorName
        switch target {
        case .photos:
            let image = TierListImageExporter.renderBoardImage(list: list, authorName: author, posters: posters)
            await saveToPhotos(image)
        case .stories:
            let image = TierListImageExporter.renderStoriesImage(list: list, authorName: author, posters: posters)
            await MainActor.run { shareImage = image }
        case .board:
            let image = TierListImageExporter.renderBoardImage(list: list, authorName: author, posters: posters)
            await MainActor.run { shareImage = image }
        }
        isExporting = false
    }

    private func saveToPhotos(_ image: UIImage) async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            await MainActor.run { exportError = "Нет доступа к медиатеке — разрешите его в Настройках" }
            return
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            await MainActor.run { exportError = error.localizedDescription }
        }
    }
}
