import SwiftUI
import UIKit

// MARK: - Media Comments Sheet (.clips-style)

/// Лист комментариев к фильму или сериалу.
/// Визуально повторяет шторку комментариев «Моментов»: кастомная шапка
/// с VariableBlur, стеклянные аватары, бесшовный ввод снизу.
struct MediaCommentsSheetView: View {
    let mediaKey: String
    let autoFocusComposer: Bool
    /// Открыть профиль автора. Родитель закрывает шторку и пушит экран профиля —
    /// ровно так же, как это делают комментарии «Моментов».
    let onSelectAuthor: ((SlooshUser) -> Void)?

    init(
        mediaKey: String,
        autoFocusComposer: Bool = false,
        onSelectAuthor: ((SlooshUser) -> Void)? = nil
    ) {
        self.mediaKey = mediaKey
        self.autoFocusComposer = autoFocusComposer
        self.onSelectAuthor = onSelectAuthor
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var repo = MediaCommentsRepository.shared
    @StateObject private var authRepo = AuthRepository.shared

    @State private var commentText: String = ""
    @State private var isSpoiler: Bool = false
    @State private var isSending: Bool = false
    @State private var sort: MediaCommentSort = .newest
    @State private var revealedSpoilers: Set<String> = []
    @State private var showEditProfileSheet: Bool = false
    @State private var showAuthSheet: Bool = false
    @State private var showSignOutAlert: Bool = false
    @State private var deleteTarget: MediaComment?
    @State private var reportTarget: MediaComment?
    @State private var cooldownRemaining: Int = 0
    @State private var cooldownTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    private var comments: [MediaComment] { repo.comments(for: mediaKey) }
    private var isLoading: Bool { repo.isLoading(mediaKey) }
    private var hasError: Bool { repo.errorByKey[mediaKey] != nil }

    private var hasTextToSending: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isExpandedInput: Bool {
        commentText.contains("\n") || commentText.count > 32
    }

    private var inputBarCornerRadius: CGFloat {
        isExpandedInput ? 20 : 22
    }

    private var inputBarHorizontalPadding: CGFloat {
        isInputFocused ? 16 : 36
    }

    private var inputBarBottomPadding: CGFloat {
        isInputFocused ? 8 : 4
    }

    private var blurOpacity: Double {
        let progress = max(0, scrollOffset) / 20.0
        return min(1.0, Double(progress))
    }

    @State private var scrollOffset: CGFloat = 0

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

    var body: some View {
        ZStack {
            if isLoading && comments.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if comments.isEmpty {
                statusStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(sortedComments) { comment in
                            commentRow(comment)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .scrollEdgeEffectStyle(.soft, for: .bottom)
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top
                } action: { _, newOffset in
                    scrollOffset = newOffset
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            headerBar
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .background(
                    VariableBlurView(tintColor: .clear, tintOpacity: 0.0)
                        .padding(.bottom, -30)
                        .ignoresSafeArea(edges: .top)
                        .opacity(blurOpacity)
                        .animation(.easeInOut(duration: 0.2), value: blurOpacity)
                )
        }
        .safeAreaInset(edge: .bottom) {
            composerBar
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .presentationDetents([.fraction(0.65), .large], selection: $sheetDetent)
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.65)))
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .onAppear {
            cooldownRemaining = repo.cooldownRemaining(mediaKey: mediaKey)
            startCooldownTickerIfNeeded()
            if autoFocusComposer, authRepo.isAuthenticated {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isInputFocused = true
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
        .sheet(isPresented: $showEditProfileSheet) {
            EditProfileSheet()
        }
        .fullScreenCover(isPresented: $showAuthSheet) {
            AuthView()
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
        .alert("Выйти из аккаунта?", isPresented: $showSignOutAlert) {
            Button("Выйти", role: .destructive) {
                authRepo.signOut()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    @State private var sheetDetent: PresentationDetent = .fraction(0.65)

    // MARK: - Header Bar

    @ViewBuilder
    private var headerBar: some View {
        ZStack {
            Text(comments.isEmpty ? "Комментарии" : "Комментарии (\(comments.count))")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: 240)
                .contentTransition(.numericText())

            HStack {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .buttonStyle(.glassPress)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Закрыть")

                Spacer()

                if comments.count > 1 {
                    Menu {
                        ForEach(MediaCommentSort.allCases) { option in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    sort = option
                                }
                            } label: {
                                if sort == option {
                                    Label(option.title, systemImage: "checkmark")
                                } else {
                                    Text(option.title)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.glassPress)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Сортировка")
                }
            }
        }
    }

    // MARK: - Empty / Error State

    @ViewBuilder
    private var statusStateView: some View {
        if hasError {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 38))
                    .foregroundStyle(.white.opacity(0.25))

                Text("Не удалось загрузить")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Text("Проверьте соединение и попробуйте снова")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                Button {
                    Task { await repo.fetch(mediaKey: mediaKey, force: true) }
                } label: {
                    Text("Повторить")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 20)
                        .frame(height: 40)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white.opacity(0.25))

                Text("Пока нет комментариев")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))

                Text("Будьте первым, кто поделится мнением об этом тайтле!")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)
            }
        }
    }

    // MARK: - Comment Row

    private func isOwn(_ comment: MediaComment) -> Bool {
        comment.authorId == authRepo.currentUser?.id
    }

    private func commentRow(_ comment: MediaComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            avatarButton(comment, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        selectAuthor(for: comment)
                    } label: {
                        Text(comment.authorName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    Text("• \(comment.timeAgoFormatted)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))

                    Spacer(minLength: 8)

                    likeButton(comment)

                    menuButton(comment)
                }

                textBody(comment)
            }
        }
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
                HStack(spacing: 6) {
                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Спойлер · показать")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.75))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .glassEffect(.regular.interactive(), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Показать спойлер")
        } else {
            Text(comment.text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.85))
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
            HStack(spacing: 4) {
                Image(systemName: liked ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                    .symbolEffect(.bounce, value: liked)

                if comment.likesCount > 0 {
                    Text("\(comment.likesCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .contentTransition(.numericText())
                }
            }
            .foregroundStyle(liked ? .white : .white.opacity(0.45))
            .frame(width: 30, height: 26)
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

            Button {
                selectAuthor(for: comment)
            } label: {
                Label("Открыть профиль", systemImage: "person.crop.circle")
            }

            Divider()

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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
                .frame(width: 24, height: 26)
                .contentShape(Rectangle())
        }
        .menuOrder(.priority)
    }

    private func avatarButton(_ comment: MediaComment, size: CGFloat) -> some View {
        Button {
            selectAuthor(for: comment)
        } label: {
            avatarView(comment, size: size)
                .contentShape(Circle())
                .contentShape(.contextMenuPreview, Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(comment.authorName)
    }

    @ViewBuilder
    private func avatarView(_ comment: MediaComment, size: CGFloat) -> some View {
        if let avatarUrl = comment.authorAvatar, let url = URL(string: avatarUrl) {
            AsyncCachedImage(url: url) {
                avatarFallback(comment.authorInitials, size: size)
            } content: { img in
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } fallback: {
                avatarFallback(comment.authorInitials, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            avatarFallback(comment.authorInitials, size: size)
        }
    }

    private func avatarFallback(_ initials: String, size: CGFloat) -> some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .frame(width: size, height: size)
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.35, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            )
    }

    // MARK: - Composer

    @ViewBuilder
    private var composerBar: some View {
        VStack(spacing: 0) {
            if cooldownRemaining > 0 {
                Text("Следующий комментарий через \(cooldownRemaining) сек.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, inputBarHorizontalPadding)
                    .padding(.bottom, 4)
            }

            inputBar
        }
        .background(Color.clear)
    }

    private var inputBar: some View {
        HStack(alignment: isExpandedInput ? .bottom : .center, spacing: 10) {
            userAvatarButton

            VStack(alignment: .leading, spacing: isExpandedInput ? 8 : 4) {
                if authRepo.isAuthenticated {
                    TextField("Комментарий", text: $commentText, axis: .vertical)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .tint(Color.white)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .frame(minHeight: isExpandedInput ? 24 : 38)
                } else {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        showAuthSheet = true
                    } label: {
                        Text("Войдите, чтобы комментировать")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: isExpandedInput ? 24 : 38)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, isExpandedInput ? 6 : 2)
            .padding(.bottom, isExpandedInput ? 8 : 2)
            .padding(.horizontal, 14)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: inputBarCornerRadius, style: .continuous)
            )
            .animation(.easeInOut(duration: 0.2), value: isExpandedInput)


            if authRepo.isAuthenticated {
                if hasTextToSending {
                    sendButton
                        .disabled(isSending || cooldownRemaining > 0)
                        .opacity(cooldownRemaining > 0 ? 0.5 : 1)
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                                removal: .scale(scale: 0.3).combined(with: .opacity).combined(with: .move(edge: .trailing))
                            )
                        )
                } else {
                    spoilerComposerToggle
                }
            } else {
                Color.clear
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, inputBarHorizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, inputBarBottomPadding)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isInputFocused)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: hasTextToSending)
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
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                }
            }
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.white))
            .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.glassPress)
        .disabled(isSending)
        .accessibilityLabel("Отправить")
    }

    private var spoilerComposerToggle: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            isSpoiler.toggle()
            ToastManager.shared.show(
                title: isSpoiler ? "Комментарий будет скрыт как спойлер" : "Пометка спойлера снята",
                icon: isSpoiler ? "eye.slash.fill" : "eye",
                duration: 1.6
            )
        } label: {
            Image(systemName: isSpoiler ? "eye.slash.fill" : "eye.slash")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isSpoiler ? .white : .white.opacity(0.5))
                .frame(width: 40, height: 40)
                .background(
                    Circle().fill(isSpoiler ? Color.white.opacity(0.16) : Color.white.opacity(0.001))
                )
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSpoiler ? "Снять пометку спойлера" : "Пометить как спойлер")
    }

    @ViewBuilder
    private var userAvatarButton: some View {
        if authRepo.isAuthenticated, let user = authRepo.currentUser {
            Menu {
                Section {
                    let displayName = user.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let effectiveName = (displayName?.isEmpty == false) ? displayName! : (user.tag ?? "Пользователь")
                    Text(effectiveName)
                    if let tag = user.tag, !tag.isEmpty {
                        Text("@\(tag)")
                    }
                }

                Button {
                    showEditProfileSheet = true
                } label: {
                    Label("Редактировать профиль", systemImage: "pencil")
                }

                Divider()

                Button(role: .destructive) {
                    showSignOutAlert = true
                } label: {
                    Label("Выйти из аккаунта", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                SlooshAvatarView(userProfile: user, size: 38)
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .clipShape(Circle())
                    .contentShape(Circle())
                    .contentShape(.contextMenuPreview, Circle())
            }
            .menuOrder(.priority)
            .tint(.white)
            .buttonStyle(.plain)
            .frame(width: 38, height: isExpandedInput ? 38 : 42, alignment: .center)
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showAuthSheet = true
            } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 38, height: 38)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 38, height: isExpandedInput ? 38 : 42, alignment: .center)
        }
    }

    // MARK: - Actions

    /// Открыть профиль автора — всегда тем же экраном, что и везде в приложении.
    /// Родитель закрывает шторку и пушит `UserProfileDetailView`.
    private func selectAuthor(for comment: MediaComment) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let user = SlooshUser(
            id: comment.authorId,
            displayName: comment.authorName,
            tag: comment.authorTag,
            avatarUrl: comment.authorAvatar
        )
        onSelectAuthor?(user)
    }

    private func send() {
        guard canSendNow else { return }
        let body = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        isSending = true

        Task { @MainActor in
            defer { isSending = false }
            do {
                _ = try await repo.addComment(mediaKey: mediaKey, text: body, isSpoiler: isSpoiler)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                commentText = ""
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

    private var canSendNow: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isSending
            && cooldownRemaining == 0
            && commentText.count <= MediaCommentLimits.maxLength
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
