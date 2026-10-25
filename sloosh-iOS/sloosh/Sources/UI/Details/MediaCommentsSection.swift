import SwiftUI
import UIKit

// MARK: - Media Comments Section (Details)

/// Секция «Комментарии» на экране фильма/сериала: счётчик, превью последних
/// и вход в полноценный лист комментариев.
struct MediaCommentsSection: View {
    let mediaKey: String

    @StateObject private var repo = MediaCommentsRepository.shared
    @ObservedObject private var authRepo = AuthRepository.shared
    @State private var showSheet: Bool = false
    @State private var focusComposer: Bool = false
    @State private var selectedAuthor: SlooshUser?

    private var comments: [MediaComment] { repo.comments(for: mediaKey) }
    private var previewComments: [MediaComment] { Array(comments.prefix(2)) }
    private var isLoading: Bool { repo.isLoading(mediaKey) }
    private var hasError: Bool { repo.errorByKey[mediaKey] != nil }

    var body: some View {
        Group {
            if mediaKey.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    header

                    if comments.isEmpty {
                        if hasError {
                            errorCard
                        } else {
                            emptyCard
                        }
                    } else {
                        previewCard
                    }
                }
            }
        }
        .task(id: mediaKey) {
            guard !mediaKey.isEmpty else { return }
            repo.primeFromDisk(mediaKey: mediaKey)
            await repo.fetch(mediaKey: mediaKey)
        }
        .sheet(isPresented: $showSheet) {
            MediaCommentsSheetView(
                mediaKey: mediaKey,
                autoFocusComposer: focusComposer
            ) { user in
                // Как в «Моментах»: закрываем лист и пушим профиль в навигацию.
                showSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    selectedAuthor = user
                }
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedAuthor != nil },
            set: { if !$0 { selectedAuthor = nil } }
        )) {
            if let user = selectedAuthor {
                UserProfileDetailView(user: user, chatContext: false)
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("Комментарии")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.primary)

            if !comments.isEmpty {
                Text("\(comments.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }

            Spacer()

            if !comments.isEmpty {
                Button {
                    openSheet(focus: false)
                } label: {
                    Text("Все")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Empty State Card

    private var emptyCard: some View {
        Button {
            openSheet(focus: true)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Пока нет комментариев")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Поделитесь первым впечатлением")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Error Card

    private var errorCard: some View {
        Button {
            Task { await repo.fetch(mediaKey: mediaKey, force: true) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 40, height: 40)
                    .glassEffect(.regular.interactive(), in: .circle)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Не удалось загрузить комментарии")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Нажмите, чтобы повторить")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.secondary)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    // MARK: - Preview Card
    private var previewCard: some View {
        Button {
            openSheet(focus: false)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(previewComments.enumerated()), id: \.element.id) { index, comment in
                    previewRow(comment)

                    if index < previewComments.count - 1 {
                        Divider()
                            .background(Color.primary.opacity(0.06))
                            .padding(.leading, 50)
                    }
                }

                Divider()
                    .background(Color.primary.opacity(0.06))
                    .padding(.leading, 14)
                    .padding(.trailing, 14)

                HStack(spacing: 6) {
                    Text(comments.count > 2 ? "Смотреть все \(comments.count)" : "Смотреть все")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.35))

                    Spacer()

                    if authRepo.isAuthenticated {
                        Text("Написать")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)
            }
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    private func previewRow(_ comment: MediaComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            avatarView(for: comment)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(comment.authorName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(1)

                    Spacer(minLength: 6)

                    Text(comment.timeAgoFormatted)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                }

                if comment.isSpoiler {
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 190, height: 8)
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 120, height: 8)
                    }
                    .shimmer()
                    .accessibilityLabel("Спойлер")
                } else {
                    Text(comment.text)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    private func avatarView(for comment: MediaComment) -> some View {
        if let raw = comment.authorAvatar,
           let url = URL(string: raw),
           url.scheme != nil {
            AsyncCachedImage(url: url) {
                avatarFallback(comment)
            } content: { image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } fallback: {
                avatarFallback(comment)
            }
            .frame(width: 26, height: 26)
            .clipShape(Circle())
        } else {
            avatarFallback(comment)
        }
    }

    private func avatarFallback(_ comment: MediaComment) -> some View {
        Circle()
            .fill(Color.white.opacity(0.12))
            .frame(width: 26, height: 26)
            .overlay(
                Text(comment.authorInitials)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            )
    }

    // MARK: - Actions

    private func openSheet(focus: Bool) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        focusComposer = focus && authRepo.isAuthenticated
        showSheet = true
    }
}
