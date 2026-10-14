import SwiftUI
import UIKit

public struct ClipCommentsSheetView: View {
    let clip: MovieClip

    @Environment(\.dismiss) private var dismiss
    @StateObject private var clipsRepo = ClipsRepository.shared
    @StateObject private var authRepo = AuthRepository.shared

    @State private var comments: [ClipComment] = []
    @State private var isLoading: Bool = true
    @State private var commentText: String = ""
    @State private var isSending: Bool = false
    @State private var scrollOffset: CGFloat = 0
    @FocusState private var isInputFocused: Bool

    @State private var sheetDetent: PresentationDetent = .fraction(0.65)
    @State private var showEditProfileSheet: Bool = false
    @State private var showAuthSheet: Bool = false
    @State private var showSignOutAlert: Bool = false
    @State private var selectedAuthorUser: SlooshUser? = nil

    public init(clip: MovieClip) {
        self.clip = clip
    }

    private var hasTextToSending: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isMultilineInput: Bool {
        commentText.contains("\n") || commentText.count > 32
    }

    private var isExpandedInput: Bool {
        isMultilineInput
    }

    private var inputBarCornerRadius: CGFloat {
        isExpandedInput ? 20 : 22
    }

    private var blurOpacity: Double {
        let progress = max(0, scrollOffset) / 20.0
        return min(1.0, Double(progress))
    }

    private var inputBarHorizontalPadding: CGFloat {
        isInputFocused ? 16 : 36
    }

    private var inputBarBottomPadding: CGFloat {
        isInputFocused ? 8 : 4
    }

    public var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if comments.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(comments) { comment in
                            commentRow(comment)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
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
            inputBar
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .presentationDetents([.fraction(0.65)], selection: $sheetDetent)
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.65)))
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .task {
            await loadComments()
        }
        .sheet(isPresented: $showEditProfileSheet) {
            EditProfileSheet()
        }
        .sheet(item: $selectedAuthorUser) { user in
            NavigationStack {
                UserProfileDetailView(user: user, chatContext: false)
            }
        }
        .fullScreenCover(isPresented: $showAuthSheet) {
            AuthView()
        }
        .alert("Выйти из аккаунта?", isPresented: $showSignOutAlert) {
            Button("Выйти", role: .destructive) {
                authRepo.signOut()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: - Header Bar (Styled like SourceSelectionView)

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
            }
        }
    }

    // MARK: - Input Bar (Directly from ChatDetailView messenger)

    private var inputBar: some View {
        HStack(alignment: isExpandedInput ? .bottom : .center, spacing: 10) {
            // User Avatar Indicator Button (Shows which account is commenting)
            userAvatarButton

            // Floating Glass Text Field Capsule / Morphing Box (Telegram-style inline reply/edit)
            VStack(alignment: .leading, spacing: isExpandedInput ? 8 : 4) {
                TextField("Сообщение", text: $commentText, axis: .vertical)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .tint(Color.white)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .frame(minHeight: isExpandedInput ? 24 : 38)
            }
            .padding(.top, isExpandedInput ? 6 : 2)
            .padding(.bottom, isExpandedInput ? 8 : 2)
            .padding(.horizontal, 14)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: inputBarCornerRadius, style: .continuous)
            )
            .animation(.easeInOut(duration: 0.2), value: isMultilineInput)

            // Telegram-style Animated Sliding/Popping Send Button (from ChatDetailView)
            if hasTextToSending {
                Button {
                    sendComment()
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.white)
                        )
                        .glassEffect(.regular.interactive(), in: .circle)
                }
                .buttonStyle(.glassPress)
                .frame(width: 40, height: isExpandedInput ? 40 : 42, alignment: .center)
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                        removal: .scale(scale: 0.3).combined(with: .opacity).combined(with: .move(edge: .trailing))
                    )
                )
                .disabled(isSending)
            }
        }
        .padding(.horizontal, inputBarHorizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, inputBarBottomPadding)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isInputFocused)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: hasTextToSending)
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

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white.opacity(0.25))

            Text("Пока нет комментариев")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            Text("Будьте первым, кто поделится мнением об этом моменте!")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
    }

    // MARK: - Comment Row

    private func commentRow(_ comment: ClipComment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar (tappable to view author profile)
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                selectedAuthorUser = SlooshUser(
                    id: comment.authorId,
                    displayName: comment.authorName,
                    tag: nil,
                    avatarUrl: comment.authorAvatar
                )
            } label: {
                if let avatarUrl = comment.authorAvatar, let url = URL(string: avatarUrl) {
                    AsyncCachedImage(url: url) {
                        avatarFallback(comment.authorInitials)
                    } content: { img in
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } fallback: {
                        avatarFallback(comment.authorInitials)
                    }
                    .frame(width: 34, height: 34)
                    .clipShape(Circle())
                } else {
                    avatarFallback(comment.authorInitials)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        selectedAuthorUser = SlooshUser(
                            id: comment.authorId,
                            displayName: comment.authorName,
                            tag: nil,
                            avatarUrl: comment.authorAvatar
                        )
                    } label: {
                        Text(comment.authorName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)

                    Text("• \(comment.timeAgoFormatted)")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))

                    Spacer()
                }

                Text(comment.text)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func avatarFallback(_ initials: String) -> some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 34, height: 34)
            .overlay(
                Text(initials)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            )
    }

    // MARK: - Actions

    private func loadComments() async {
        isLoading = true
        let fetched = await clipsRepo.fetchComments(for: clip.id)
        self.comments = fetched
        self.isLoading = false
    }

    private func sendComment() {
        let cleanText = commentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty && !isSending else { return }

        isSending = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                let newComment = try await clipsRepo.addComment(clipId: clip.id, text: cleanText)
                withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                    self.comments.append(newComment)
                }
                self.commentText = ""
                self.isSending = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.isSending = false
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                ToastManager.shared.show(title: "Не удалось отправить комментарий", icon: "exclamationmark.triangle.fill", iconColor: .red)
            }
        }
    }
}
