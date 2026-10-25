import SwiftUI
import UIKit

// MARK: - Media Comments Sheet

/// Лист комментариев к фильму или сериалу.
/// Открывается из секции `MediaCommentsSection` на экране деталей.
struct MediaCommentsSheetView: View {
    let mediaKey: String
    var autoFocusComposer: Bool = false

    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = MediaCommentsRepository.shared
    @ObservedObject private var authRepo = AuthRepository.shared

    @State private var text: String = ""
    @State private var isSpoiler: Bool = false
    @State private var isSending: Bool = false
    @State private var sort: MediaCommentSort = .newest
    @State private var revealedSpoilers: Set<String> = []
    @State private var showAuthSheet: Bool = false
    @State private var authorProfile: SlooshUser?
    @State private var deleteTarget: MediaComment?
    @State private var reportTarget: MediaComment?
    @State private var cooldownRemaining: Int = 0
    @State private var cooldownTask: Task<Void, Never>?
    @FocusState private var isComposerFocused: Bool

    private var comments: [MediaComment] { repo.comments(for: mediaKey) }
    private var isLoading: Bool { repo.isLoading(mediaKey) }

    private var sortedComments: [MediaComment] {
        switch sort {
        case .newest:
            return comments
        case .popular:
            return comments.sorted { lhs, rhs in
                if lhs.likesCount != rhs.likesCount { return lhs.likesCount > rhs.likesCount }
                return lhs.createdAtMs > rhs.createdAtMs
            }
        }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool {
        !trimmedText.isEmpty && !isSending && cooldownRemaining == 0
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Комментарии")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .foregroundStyle(.primary)
                        }
                        .accessibilityLabel("Закрыть")
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    composerBar
                }
                .onAppear {
                    cooldownRemaining = repo.cooldownRemaining(mediaKey: mediaKey)
                    startCooldownTickerIfNeeded()
                    if autoFocusComposer, authRepo.isAuthenticated {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            isComposerFocused = true
                        }
                    }
                }
                .task(id: mediaKey) {
                    repo.primeFromDisk(mediaKey: mediaKey)
                    await repo.fetch(mediaKey: mediaKey)
                }
                .onDisappear {
                    cooldownTask?.cancel()
                    cooldownTask = nil
                }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.large])
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .fullScreenCover(isPresented: $showAuthSheet) {
            AuthView()
        }
        .sheet(item: $authorProfile) { user in
            UserProfileDetailView(user: user)
        }
        .confirmationDialog(
            "Удалить комментарий?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { comment in
            Button("Удалить", role: .destructive) {
                delete(comment)
            }
            Button("Отмена", role: .cancel) {}
        } message: { _ in
            Text("Комментарий исчезнет для всех пользователей.")
        }
        .confirmationDialog(
            "Пожаловаться на комментарий",
            isPresented: Binding(
                get: { reportTarget != nil },
                set: { if !$0 { reportTarget = nil } }
            ),
            presenting: reportTarget
        ) { comment in
            Button("Спам") { sendReport(comment, reason: "spam") }
            Button("Оскорбления") { sendReport(comment, reason: "abuse") }
            Button("Спойлер без пометки") { sendReport(comment, reason: "spoiler") }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && comments.isEmpty {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if comments.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    sortBar
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    ForEach(Array(sortedComments.enumerated()), id: \.element.id) { index, comment in
                        commentRow(comment)

                        if index < sortedComments.count - 1 {
                            Divider()
                                .background(Color.primary.opacity(0.06))
                                .padding(.leading, 64)
                        }
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .refreshable {
                await repo.fetch(mediaKey: mediaKey, force: true)
            }
        }
    }

    private var sortBar: some View {
        HStack(spacing: 10) {
            Text("\(comments.count)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())

            Spacer()

            Picker("Сортировка", selection: $sort.animation(.easeInOut(duration: 0.2))) {
                ForEach(MediaCommentSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }

    private var emptyState: some View {
        ScrollView {
            AppEmptyStateView(
                icon: "bubble.left.and.bubble.right",
                title: "Пока нет комментариев",
                description: "Поделитесь первым впечатлением — это займёт пару секунд.",
                action: .init(label: authRepo.isAuthenticated ? "Написать" : "Войти") {
                    if authRepo.isAuthenticated {
                        isComposerFocused = true
                    } else {
                        showAuthSheet = true
                    }
                }
            )
            .frame(minHeight: 420)
        }
        .refreshable {
            await repo.fetch(mediaKey: mediaKey, force: true)
        }
    }

    // MARK: - Comment Row

    private func commentRow(_ comment: MediaComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatarButton(for: comment)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(comment.authorName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let tag = comment.authorTag, !tag.isEmpty {
                        Text("@\(tag)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Text(comment.timeAgoFormatted)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                textBody(comment)

                HStack(spacing: 16) {
                    likeButton(comment)
                    Spacer()
                    menuButton(comment)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func avatarButton(for comment: MediaComment) -> some View {
        Button {
            openProfile(for: comment)
        } label: {
            avatarView(for: comment, size: 36)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(comment.authorName)
    }

    @ViewBuilder
    private func avatarView(for comment: MediaComment, size: CGFloat) -> some View {
        if let raw = comment.authorAvatar,
           let url = URL(string: raw),
           url.scheme != nil {
            AsyncCachedImage(url: url) {
                avatarFallback(comment, size: size)
            } content: { image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } fallback: {
                avatarFallback(comment, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            avatarFallback(comment, size: size)
        }
    }

    private func avatarFallback(_ comment: MediaComment, size: CGFloat) -> some View {
        Circle()
            .fill(Color.slooshAccent.opacity(0.18))
            .frame(width: size, height: size)
            .overlay(
                Text(comment.authorInitials)
                    .font(.system(size: size * 0.36, weight: .semibold))
                    .foregroundStyle(Color.slooshAccent)
            )
    }

    @ViewBuilder
    private func textBody(_ comment: MediaComment) -> some View {
        if comment.isSpoiler && !revealedSpoilers.contains(comment.id) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    _ = revealedSpoilers.insert(comment.id)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Спойлер — показать")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Показать спойлер")
        } else {
            Text(comment.text)
                .font(.system(size: 15))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }

    private func likeButton(_ comment: MediaComment) -> some View {
        let liked = comment.isLiked(by: authRepo.currentUser?.id)

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await repo.toggleLike(comment, mediaKey: mediaKey) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 14, weight: .semibold))
                    .symbolEffect(.bounce, value: liked)

                if comment.likesCount > 0 {
                    Text("\(comment.likesCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(liked ? Color.slooshAccent : Color.secondary)
            .frame(height: 30)
            .padding(.horizontal, 10)
            .background(Color.primary.opacity(0.001))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(liked ? "Убрать лайк" : "Поставить лайк")
    }

    private func menuButton(_ comment: MediaComment) -> some View {
        Menu {
            Button {
                UIPasteboard.general.string = comment.text
                ToastManager.shared.show(title: "Текст скопирован", icon: "doc.on.doc.fill")
            } label: {
                Label("Скопировать", systemImage: "doc.on.doc")
            }

            if isOwn(comment) {
                Button(role: .destructive) {
                    deleteTarget = comment
                } label: {
                    Label("Удалить", systemImage: "trash")
                }
            } else {
                Button {
                    reportTarget = comment
                } label: {
                    Label("Пожаловаться", systemImage: "flag")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
    }

    // MARK: - Composer

    @ViewBuilder
    private var composerBar: some View {
        if authRepo.isAuthenticated {
            VStack(spacing: 0) {
                if cooldownRemaining > 0 {
                    Text("Следующий комментарий через \(cooldownRemaining) сек.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 6)
                        .transition(.opacity)
                }

                HStack(alignment: .bottom, spacing: 10) {
                    composerAvatar

                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Оставьте комментарий…", text: $text, axis: .vertical)
                            .font(.system(size: 15))
                            .foregroundStyle(.primary)
                            .tint(.white)
                            .lineLimit(1...5)
                            .focused($isComposerFocused)

                        HStack(spacing: 8) {
                            spoilerToggle

                            Spacer()

                            if text.count > 800 {
                                Text("\(text.count)/\(MediaCommentLimits.maxLength)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(text.count > MediaCommentLimits.maxLength ? Color.red : Color.secondary)
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(
                        .regular.interactive(),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                    )

                    if !trimmedText.isEmpty {
                        sendButton
                            .transition(
                                .asymmetric(
                                    insertion: .scale(scale: 0.3).combined(with: .opacity),
                                    removal: .scale(scale: 0.3).combined(with: .opacity)
                                )
                            )
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, cooldownRemaining > 0 ? 10 : 6)
                .animation(.spring(response: 0.32, dampingFraction: 0.8), value: trimmedText.isEmpty)
            }
        } else {
            guestComposer
        }
    }

    @ViewBuilder
    private var composerAvatar: some View {
        if let user = authRepo.currentUser {
            SlooshAvatarView(
                avatarSource: user.photoURL,
                fallbackText: user.avatarInitials,
                size: 34
            )
        } else {
            Circle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 34, height: 34)
        }
    }

    private var spoilerToggle: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                isSpoiler.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: isSpoiler ? "eye.slash.fill" : "eye.slash")
                    .font(.system(size: 11, weight: .semibold))
                Text("Спойлер")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isSpoiler ? Color.white : Color.secondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                Capsule()
                    .fill(isSpoiler ? Color.slooshAccent.opacity(0.9) : Color.primary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpoiler ? "Снять пометку спойлера" : "Пометить как спойлер")
    }

    private var sendButton: some View {
        Button {
            send()
        } label: {
            Group {
                if isSending {
                    ProgressView()
                        .tint(.black)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                }
            }
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.white))
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .opacity(canSend ? 1 : 0.5)
        .accessibilityLabel("Отправить")
    }

    private var guestComposer: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showAuthSheet = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 15, weight: .semibold))
                Text("Войдите, чтобы комментировать")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .glassEffect(.regular.interactive(), in: Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .padding(.top, 6)
    }

    // MARK: - Actions

    private func isOwn(_ comment: MediaComment) -> Bool {
        guard let uid = authRepo.currentUser?.id else { return false }
        return comment.authorId == uid
    }

    private func openProfile(for comment: MediaComment) {
        guard comment.authorId != authRepo.currentUser?.id else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        authorProfile = SlooshUser(
            id: comment.authorId,
            displayName: comment.authorName,
            tag: comment.authorTag,
            avatarUrl: comment.authorAvatar
        )
    }

    private func send() {
        guard canSend else { return }
        let body = trimmedText
        isSending = true

        Task { @MainActor in
            defer { isSending = false }
            do {
                _ = try await repo.addComment(mediaKey: mediaKey, text: body, isSpoiler: isSpoiler)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                text = ""
                isSpoiler = false
                cooldownRemaining = repo.cooldownRemaining(mediaKey: mediaKey)
                startCooldownTickerIfNeeded()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                ToastManager.shared.show(
                    title: (error as? LocalizedError)?.errorDescription ?? "Не удалось отправить",
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .red
                )
            }
        }
    }

    private func delete(_ comment: MediaComment) {
        Task { @MainActor in
            do {
                try await repo.deleteComment(comment, mediaKey: mediaKey)
                ToastManager.shared.show(title: "Комментарий удалён", icon: "trash.fill")
            } catch {
                ToastManager.shared.show(
                    title: "Не удалось удалить",
                    icon: "exclamationmark.triangle.fill",
                    iconColor: .red
                )
            }
        }
    }

    private func sendReport(_ comment: MediaComment, reason: String) {
        Task { @MainActor in
            let ok = await repo.report(comment, mediaKey: mediaKey, reason: reason)
            ToastManager.shared.show(
                title: ok ? "Жалоба отправлена" : "Не удалось отправить жалобу",
                icon: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill",
                iconColor: ok ? nil : .red
            )
        }
    }

    private func startCooldownTickerIfNeeded() {
        guard cooldownRemaining > 0 else { return }
        cooldownTask?.cancel()
        cooldownTask = Task { @MainActor in
            while cooldownRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                cooldownRemaining = max(0, cooldownRemaining - 1)
            }
        }
    }
}
