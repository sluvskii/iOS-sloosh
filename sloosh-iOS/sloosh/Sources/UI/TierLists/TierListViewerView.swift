import SwiftUI
import Photos

/// Публичный просмотрщик тир-листа: системный навбар (лайк + меню шаринга),
/// доска read-only, тап постера открывает фильм. Body декомпозирован —
/// иначе тайп-чекер Swift не справляется с длинной цепочкой модификаторов.
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

    var body: some View {
        scrollSection
            .navigationTitle(list?.title ?? "Тир-лист")
            .navigationBarTitleDisplayMode(.inline)
            .tint(.primary)
            .toolbar {
                likeToolbarItem
                menuToolbarItem
            }
            .task { await load() }
            .onChange(of: repo.publicLists) { _, updated in
                syncFromFeed(updated)
            }
            .navigationDestination(item: $detailsItem) { item in
                detailsDestination(item)
            }
            .navigationDestination(isPresented: $showAuthorProfile) {
                authorDestination
            }
            .navigationDestination(isPresented: $showRemixEditor) {
                remixDestination
            }
            .sheet(isPresented: $showFriendSheet) {
                friendSheet
            }
            .overlay {
                exportOverlay
            }
            .overlay {
                shareSheetOverlay
            }
            .alert("Не удалось создать картинку", isPresented: exportAlertBinding) {
                Button("Понятно", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
    }

    // MARK: Скролл-контент

    @ViewBuilder
    private var scrollSection: some View {
        ScrollView {
            if isLoading && list == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let current = list {
                listContent(current)
            } else {
                Text("Тир-лист не найден — возможно, автор удалил его")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
    }

    @ViewBuilder
    private func listContent(_ current: TierList) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection(current)
            authorRow(current)
            statsRow(current)
            boardSection(current)
            if current.authorId == AuthRepository.shared.currentUser?.id {
                deleteOwnListButton(current)
            }
            Spacer(minLength: 40)
        }
    }

    @ViewBuilder
    private func headerSection(_ current: TierList) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let subtitle = current.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private func authorRow(_ current: TierList) -> some View {
        Button {
            showAuthorProfile = true
        } label: {
            HStack(spacing: 10) {
                SlooshAvatarView(avatarSource: current.authorAvatar, fallbackText: current.authorName, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(current.authorName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("\(current.dateText) · \(current.itemsCount) фильмов")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    private func statBadge(icon: String, value: Int) -> some View {
        Label("\(value)", systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func statsRow(_ current: TierList) -> some View {
        HStack(spacing: 14) {
            statBadge(icon: "heart.fill", value: current.likesCount ?? 0)
            statBadge(icon: "eye", value: current.viewsCount ?? 0)
            statBadge(icon: "film.stack", value: current.itemsCount)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func boardSection(_ current: TierList) -> some View {
        TierListBoardView(
            mode: .view,
            rows: .constant(current.rows),
            unranked: .constant(current.unranked),
            onTapItem: nil,
            onOpenDetails: { item in
                detailsItem = item
            }
        )
    }

    @ViewBuilder
    private func deleteOwnListButton(_ current: TierList) -> some View {
        Button("Удалить тир-лист", role: .destructive) {
            Task {
                try? await TierListsRepository.shared.deleteList(id: current.id)
                dismiss()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    // MARK: Тулбар

    @ToolbarContentBuilder
    private var likeToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                Task {
                    let (liked, count) = await like()
                    isLiked = liked
                    if let current = list, current.id == listId {
                        list?.likesCount = count
                    }
                }
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .foregroundStyle(isLiked ? .red : .primary)
            }
            .disabled(list == nil)
        }
    }

    @ToolbarContentBuilder
    private var menuToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                exportMenuItems
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.primary)
            }
            .disabled(list == nil)
        }
    }

    @ViewBuilder
    private var exportMenuItems: some View {
        Button {
            Task { await exportToPhotos() }
        } label: {
            Label("Сохранить картинку", systemImage: "square.and.arrow.down")
        }
        Button {
            Task { await exportStoriesImage() }
        } label: {
            Label("Картинка для сторис", systemImage: "rectangle.portrait.on.rectangle.portrait")
        }
        Button {
            Task { await shareBoardImage() }
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
    }

    // MARK: Навигационные цели

    @ViewBuilder
    private func detailsDestination(_ item: TierListItem) -> some View {
        DetailsView(movieId: item.detailsId, mediaType: item.mediaType)
    }

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
                onPublished: { _ in },
                onDismiss: {}
            )
        }
    }

    @ViewBuilder
    private var friendSheet: some View {
        if let current = list {
            ShareToFriendSheet(tierList: current)
        }
    }

    // MARK: Экспорт

    @ViewBuilder
    private var exportOverlay: some View {
        if isExporting {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 14) {
                    ProgressView(value: exportProgress)
                        .frame(width: 240)
                    Text("Собираем картинку…")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    @ViewBuilder
    private var shareSheetOverlay: some View {
        if let image = shareImage {
            ShareSheet(items: [image])
                .onDisappear { shareImage = nil }
        }
    }

    private var exportAlertBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )
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

    private func syncFromFeed(_ updated: [TierList]) {
        if let current = list, let fresh = updated.first(where: { $0.id == current.id }) {
            list = fresh
        }
    }

    private func like() async -> (Bool, Int) {
        guard let current = list else { return (isLiked, 0) }
        let (liked, count) = await TierListsRepository.shared.toggleLike(current)
        TierListsRepository.shared.applyLikeCount(listId: current.id, count: count)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return (liked, count)
    }

    private func exportToPhotos() async {
        guard let current = list else { return }
        isExporting = true
        exportProgress = 0
        let posters = await loadPosters(for: current)
        let image = TierListImageExporter.renderBoardImage(list: current, authorName: current.authorName, posters: posters)
        await saveToPhotos(image)
        isExporting = false
    }

    private func exportStoriesImage() async {
        guard let current = list else { return }
        isExporting = true
        exportProgress = 0
        let posters = await loadPosters(for: current)
        let image = TierListImageExporter.renderStoriesImage(list: current, authorName: current.authorName, posters: posters)
        await MainActor.run { shareImage = image }
        isExporting = false
    }

    private func shareBoardImage() async {
        guard let current = list else { return }
        isExporting = true
        exportProgress = 0
        let posters = await loadPosters(for: current)
        let image = TierListImageExporter.renderBoardImage(list: current, authorName: current.authorName, posters: posters)
        await MainActor.run { shareImage = image }
        isExporting = false
    }

    private func loadPosters(for current: TierList) async -> [String: UIImage] {
        await TierListImageExporter.loadPosters(for: current) { fraction in
            Task { @MainActor in exportProgress = fraction }
        }
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
