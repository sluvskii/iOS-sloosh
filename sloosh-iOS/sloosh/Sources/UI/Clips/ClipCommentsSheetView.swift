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
    @FocusState private var isInputFocused: Bool

    public init(clip: MovieClip) {
        self.clip = clip
    }

    private var hasTextToSending: Bool {
        !commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var body: some View {
        NavigationStack {
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
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                headerBar
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .background(
                        VariableBlurView(tintColor: .clear, tintOpacity: 0.0)
                            .padding(.bottom, -30)
                            .ignoresSafeArea(edges: .top)
                    )
            }
            .safeAreaInset(edge: .bottom) {
                inputBar
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .presentationDetents([.fraction(0.65), .large])
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
        .task {
            await loadComments()
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
        HStack(alignment: .bottom, spacing: 8) {
            // Floating Glass Text Field Capsule (Telegram-style from ChatDetailView)
            TextField("Комментарий...", text: $commentText, axis: .vertical)
                .font(.system(size: 16))
                .foregroundColor(.primary)
                .tint(Color.white)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .frame(minHeight: 38)
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
                .glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )

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
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.3).combined(with: .opacity).combined(with: .move(edge: .trailing)),
                        removal: .scale(scale: 0.3).combined(with: .opacity).combined(with: .move(edge: .trailing))
                    )
                )
                .disabled(isSending)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            VariableBlurView(tintColor: .clear, tintOpacity: 0.0, direction: .blurredBottomClearTop)
                .padding(.top, -16)
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isInputFocused)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: hasTextToSending)
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
            // Avatar
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

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))

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
