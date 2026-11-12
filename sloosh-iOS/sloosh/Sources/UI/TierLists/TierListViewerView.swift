import SwiftUI
import Photos

/// Публичный просмотрщик тир-листа: системный навбар с меню (шеринг,
/// ремикс), лайк в тулбаре, доска read-only, тап постера открывает фильм.
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
        ScrollView {
            if isLoading && list == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let list {
                listContent(list)
            } else {
                Text("Тир-лист не найден — возможно, автор удалил его")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .navigationTitle(list?.title ?? "Тир-лист")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
                }
                .disabled(list == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
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
                        Task {
                            if let image = await exportedImage(of: list) {
                                SharePresenter.presentShare(items: [image])
                            }
                        }
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
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(list == nil)
            }
        }
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
        .alert("Не удалось создать картинку", isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } }
        )) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    // MARK: Загрузка и действия

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

    private func like() async -> (Bool, Int) {
        guard let list else { return (isLiked, 0) }
        let (liked, count) = await TierListsRepository.shared.toggleLike(list)
        TierListsRepository.shared.applyLikeCount(listId: list.id, count: count)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        return (liked, count)
    }

    private func exportedImage(of list: TierList) async -> UIImage? {
        isExporting = true
        exportProgress = 0
        let posters = await TierListImageExporter.loadPosters(for: list) { fraction in
            Task { @MainActor in exportProgress = fraction }
        }
        let image = TierListImageExporter.renderBoardImage(list: list, authorName: list.authorName, posters: posters)
        isExporting = false
        return image
    }

    // MARK: Контент

    @ViewBuilder
    private func listContent(_ list: TierList) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let subtitle = list.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            Button {
                showAuthorProfile = true
            } label: {
                HStack(spacing: 10) {
                    SlooshAvatarView(avatarSource: list.authorAvatar, fallbackText: list.authorName, size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(list.authorName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("\(list.dateText) · \(list.itemsCount) фильмов")
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

            TierListBoardView(
                mode: .view,
                rows: .constant(list.rows),
                unranked: .constant(list.unranked),
                onTapItem: nil,
                onOpenDetails: { item in
                    detailsItem = item
                }
            )

            if list.authorId == AuthRepository.shared.currentUser?.id {
                Button("Удалить тир-лист", role: .destructive) {
                    Task {
                        try? await TierListsRepository.shared.deleteList(id: list.id)
                        dismiss()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
            }

            Spacer(minLength: 40)
        }
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
    private var exportOverlay: some View {
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

    private func export(as target: ExportTarget) async {
        guard let list else { return }
        isExporting = true
        exportProgress = 0
        let posters = await TierListImageExporter.loadPosters(for: list) { fraction in
            Task { @MainActor in exportProgress = fraction }
        }
        switch target {
        case .photos:
            let image = TierListImageExporter.renderBoardImage(list: list, authorName: list.authorName, posters: posters)
            await saveToPhotos(image)
        case .stories:
            let image = TierListImageExporter.renderStoriesImage(list: list, authorName: list.authorName, posters: posters)
            await MainActor.run { shareImage = image }
        case .board:
            let image = TierListImageExporter.renderBoardImage(list: list, authorName: list.authorName, posters: posters)
            await MainActor.run { shareImage = image }
        }
        isExporting = false
    }

    enum ExportTarget { case board, stories, photos }

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
