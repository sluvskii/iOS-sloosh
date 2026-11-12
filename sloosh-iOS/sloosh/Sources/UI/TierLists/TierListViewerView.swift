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
    @State private var exportTarget: ExportTarget?
    @State private var exportError: String?
    @State private var scrollOffset: CGFloat = 0

    enum ExportTarget { case board, stories, photos }

    var body: some View {
        VStack(spacing: 0) {
            SlooshTopBar(
                title: list?.title ?? "Тир-лист",
                blendsTitle: false,
                scrollOffset: $scrollOffset,
                leadingIcon: "chevron.left",
                leadingAction: { dismiss() },
                trailing: {
                    Menu {
                        Button {
                            exportTarget = .photos
                            Task { await export(as: .photos) }
                        } label: {
                            Label("Сохранить картинку", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            exportTarget = .stories
                            Task { await export(as: .stories) }
                        } label: {
                            Label("Картинка для сторис", systemImage: "rectangle.portrait.on.rectangle.portrait")
                        }
                        Button {
                            exportTarget = .board
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
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            )

            if isLoading && list == nil {
                ProgressView()
                    .tint(Color.slooshAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let list {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(list.title)
                                .font(.system(size: 26, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                            if let subtitle = list.subtitle, !subtitle.isEmpty {
                                Text(subtitle)
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .padding(.horizontal, 16)
                            }
                        }

                        authorRow(list: list)

                        HStack(spacing: 14) {
                            statBadge(icon: "heart.fill", value: list.likesCount ?? 0)
                            statBadge(icon: "eye", value: list.viewsCount ?? 0)
                            statBadge(icon: "film.stack", value: list.itemsCount)
                            if let template = list.templateId {
                                Label("по шаблону", systemImage: "sparkles")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.35))
                                    _ = template
                            }
                        }
                        .padding(.horizontal, 16)

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

                        actionRow(list: list)

                        if list.authorId == AuthRepository.shared.currentUser?.id {
                            Button(role: .destructive) {
                                Task {
                                    try? await TierListsRepository.shared.deleteList(id: list.id)
                                    dismiss()
                                }
                            } label: {
                                Label("Удалить тир-лист", systemImage: "trash")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.red.opacity(0.8))
                                    .padding(.horizontal, 16)
                                    .padding(.top, 6)
                            }
                        }
                        Spacer(minLength: 40)
                    }
                }
            } else {
                AppEmptyStateView(
                    icon: "list.star",
                    title: "Тир-лист не найден",
                    description: "Возможно, автор удалил его"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(TierListTheme.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .task {
            let loaded = initialList ?? await TierListsRepository.shared.fetchList(id: listId)
            list = loaded
            isLoading = false
            if let loaded {
                isLiked = TierListsRepository.shared.isLiked(loaded.id)
                TierListsRepository.shared.recordView(loaded.id)
            }
        }
        .onChange(of: repo.publicLists) { _, updated in
            if let current = list, let fresh = updated.first(where: { $0.id == current.id }) {
                list = fresh
            }
        }
        .navigationDestination(item: $detailsItem) { item in
            DetailsView(movieId: item.detailsId, mediaType: item.mediaType)
        }
        .navigationDestination(isPresented: $showAuthorProfile) {
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
        .navigationDestination(isPresented: $showRemixEditor) {
            if let source = list {
                var remix = source
                remix.id = "draft_\(UUID().uuidString)"
                remix.isDraft = true
                remix.authorId = AuthRepository.shared.currentUser?.id ?? ""
                remix.authorName = AuthRepository.shared.currentUser?.displayName ?? ""
                remix.createdAtMs = 0
                remix.updatedAtMs = 0
                remix.likesCount = nil
                remix.viewsCount = nil
                TierListEditorView(
                    draft: remix,
                    onPublished: { _ in },
                    onDismiss: {}
                )
            }
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

    // MARK: Действия

    @ViewBuilder
    private var exportOverlay: some View {
        ZStack {
            Color.black.opacity(0.75).ignoresSafeArea()
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
        exportTarget = nil
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

    // MARK: Компоненты

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
                        .foregroundStyle(.white)
                    Text(list.dateText)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }

    private func statBadge(icon: String, value: Int) -> some View {
        Label("\(value)", systemImage: icon)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.07), in: Capsule())
    }

    @ViewBuilder
    private func actionRow(list: TierList) -> some View {
        HStack(spacing: 12) {
            Button {
                Task {
                    let (liked, count) = await TierListsRepository.shared.toggleLike(list)
                    isLiked = liked
                    if let index = repo.publicLists.firstIndex(where: { $0.id == list.id }) {
                        repo.publicLists[index].likesCount = count
                    }
                    if list.id == self.list?.id {
                        self.list?.likesCount = count
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
            } label: {
                Label("\(list.likesCount ?? 0)", systemImage: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isLiked ? Color.red : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Capsule().fill(isLiked ? Color.red.opacity(0.15) : Color.white.opacity(0.08))
                    )
            }
            Button {
                exportTarget = .board
                Task { await export(as: .board) }
            } label: {
                Label("Картинкой", systemImage: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Capsule().fill(Color.white.opacity(0.08)))
            }
        }
        .padding(.horizontal, 16)
    }
}
