import SwiftUI

public struct ChannelPostRowView: View {
    public let post: ChannelPost
    public let isAuthor: Bool
    public let currentUserId: String

    public var onOpenDetails: ((String) -> Void)? = nil
    public var onPlayDirectly: ((MediaCardPayload) -> Void)? = nil
    public var onToggleReaction: ((String) -> Void)? = nil
    public var onEditPost: (() -> Void)? = nil
    public var onTogglePin: (() -> Void)? = nil
    public var onDeletePost: (() -> Void)? = nil

    private let availableEmojis: [String] = ["🔥", "❤️", "🍿", "🎬", "👏", "😱", "⚡️", "⭐️"]

    public init(
        post: ChannelPost,
        isAuthor: Bool,
        currentUserId: String,
        onOpenDetails: ((String) -> Void)? = nil,
        onPlayDirectly: ((MediaCardPayload) -> Void)? = nil,
        onToggleReaction: ((String) -> Void)? = nil,
        onEditPost: (() -> Void)? = nil,
        onTogglePin: (() -> Void)? = nil,
        onDeletePost: (() -> Void)? = nil
    ) {
        self.post = post
        self.isAuthor = isAuthor
        self.currentUserId = currentUserId
        self.onOpenDetails = onOpenDetails
        self.onPlayDirectly = onPlayDirectly
        self.onToggleReaction = onToggleReaction
        self.onEditPost = onEditPost
        self.onTogglePin = onTogglePin
        self.onDeletePost = onDeletePost
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Main Post Bubble
            VStack(alignment: .leading, spacing: 10) {
                // Pinned indicator badge if post is pinned
                if post.isPinned {
                    HStack(spacing: 5) {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("Закреплено")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(Color.slooshAccent)
                    .padding(.bottom, 2)
                }

                // Post Text
                if let text = post.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(text)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Attached Media Card (if any)
                if let media = post.media {
                    ChannelMediaCardView(
                        media: media,
                        onOpenDetails: onOpenDetails,
                        onPlayDirectly: onPlayDirectly
                    )
                }

                // Footer Metadata: views, edited state, timestamp
                HStack(spacing: 8) {
                    // Views Count
                    HStack(spacing: 4) {
                        Image(systemName: "eye.fill")
                            .font(.system(size: 10))
                        Text(formatViews(post.viewsCount ?? 1))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(.secondary)

                    if post.isEdited == true {
                        Text("изменено")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text(formatTimestamp(post.timestampMs))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.top, 2)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contextMenu {
                contextMenuContent
            }

            // Reactions Bar
            reactionsBar
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    // MARK: - Reactions Bar

    private var reactionsBar: some View {
        let summaries = post.reactionSummary(currentUserId: currentUserId)

        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Existing Reaction Pills
                ForEach(summaries, id: \.emoji) { item in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onToggleReaction?(item.emoji)
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.emoji)
                                .font(.system(size: 13))
                            Text("\(item.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(item.isMine ? Color.slooshAccent : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(item.isMine ? Color.slooshAccent.opacity(0.22) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            Capsule()
                                .stroke(item.isMine ? Color.slooshAccent.opacity(0.6) : Color.clear, lineWidth: 1)
                        )
                        .glassEffect(.regular.interactive(), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                // Plus (+) Reaction Picker Button
                Menu {
                    ForEach(availableEmojis, id: \.self) { emoji in
                        Button {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onToggleReaction?(emoji)
                        } label: {
                            Text(emoji)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.06))
                        )
                        .glassEffect(.regular.interactive(), in: Circle())
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        // Quick reactions
        Menu {
            ForEach(availableEmojis, id: \.self) { emoji in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onToggleReaction?(emoji)
                } label: {
                    Text(emoji)
                }
            }
        } label: {
            Label("Реакция", systemImage: "face.smiling")
        }

        // Copy text
        if let text = post.text, !text.isEmpty {
            Button {
                UIPasteboard.general.string = text
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("Скопировать текст", systemImage: "doc.on.doc")
            }
        }

        // Share
        let shareText = post.media != nil ? "\(post.text ?? "") \(post.media!.title)" : (post.text ?? "")
        if !shareText.isEmpty {
            ShareLink(item: shareText) {
                Label("Поделиться", systemImage: "square.and.arrow.up")
            }
        }

        if isAuthor {
            Divider()

            // Pin / Unpin
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onTogglePin?()
            } label: {
                Label(
                    post.isPinned ? "Открепить" : "Закрепить",
                    systemImage: post.isPinned ? "pin.slash" : "pin"
                )
            }

            // Edit
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onEditPost?()
            } label: {
                Label("Редактировать", systemImage: "pencil")
            }

            // Delete
            Button(role: .destructive) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onDeletePost?()
            } label: {
                Label("Удалить", systemImage: "trash")
            }
        }
    }

    // MARK: - Formatting Helpers

    private func formatViews(_ views: Int) -> String {
        if views >= 1_000_000 {
            return String(format: "%.1fM", Double(views) / 1_000_000.0)
        } else if views >= 1_000 {
            return String(format: "%.1fK", Double(views) / 1_000.0)
        }
        return "\(views)"
    }

    private func formatTimestamp(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        if calendar.isDateInToday(date) {
            formatter.dateFormat = "HH:mm"
        } else {
            formatter.dateFormat = "d MMM, HH:mm"
        }
        return formatter.string(from: date)
    }
}
