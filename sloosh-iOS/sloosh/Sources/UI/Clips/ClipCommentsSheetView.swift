import SwiftUI

public struct ClipCommentsSheetView: View {
    let clip: MovieClip

    @Environment(\.dismiss) private var dismiss
    @StateObject private var clipsRepo = ClipsRepository.shared
    @StateObject private var authRepo = AuthRepository.shared

    @State private var comments: [ClipComment] = []
    @State private var isLoading: Bool = true
    @State private var commentText: String = ""
    @State private var isSending: Bool = false
    @FocusState private var isFocused: Bool

    public init(clip: MovieClip) {
        self.clip = clip
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                        Spacer()
                    } else if comments.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40))
                                .foregroundStyle(.white.opacity(0.3))
                            Text("Пока нет комментариев")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            Text("Будьте первым, кто поделится мнением об этом моменте!")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 16) {
                                ForEach(comments) { comment in
                                    commentRow(comment)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }

                    Divider()
                        .background(Color.white.opacity(0.12))

                    // Comment Input Bar
                    HStack(spacing: 10) {
                        TextField("Оставить комментарий...", text: $commentText)
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Capsule())
                            .focused($isFocused)
                            .submitLabel(.send)
                            .onSubmit {
                                sendComment()
                            }

                        Button {
                            sendComment()
                        } label: {
                            if isSending {
                                ProgressView()
                                    .tint(.black)
                                    .frame(width: 36, height: 36)
                            } else {
                                Image(systemName: "arrow.up")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 36, height: 36)
                                    .background(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.3) : Color.slooshAccent)
                                    .clipShape(Circle())
                            }
                        }
                        .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black)
                }
            }
            .navigationTitle("Комментарии (\(comments.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            .task {
                await loadComments()
            }
        }
        .presentationDetents([.fraction(0.65), .large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
        .environment(\.colorScheme, .dark)
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
                self.comments.append(newComment)
                self.commentText = ""
                self.isSending = false
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                self.isSending = false
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                ToastManager.shared.show("Не удалось отправить комментарий", type: .error)
            }
        }
    }
}
