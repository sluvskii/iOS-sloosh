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

    private let availableEmojis: [String] = ["❤️", "👍", "🔥", "😂", "🍿", "👏"]

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
        VStack(alignment: .leading, spacing: 6) {
            // Main Post Bubble Container (matches chat bubble style)
            VStack(alignment: .leading, spacing: 8) {
                // Pinned indicator badge
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

                // Attached Media Card (if any)
                if let media = post.media {
                    MediaMessageCardView(
                        media: media,
                        onOpenDetails: onOpenDetails,
                        onPlayDirectly: onPlayDirectly
                    )
                }

                // Post Text
                if let text = post.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(text)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Footer Metadata: views, edited, time
                HStack(spacing: 8) {
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
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            )
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture(count: 2) {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onToggleReaction?("❤️")
            }
            .contextMenu {
                contextMenuContent
            }

            // Reactions Bar (Liquid Glass Capsules)
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
                ForEach(summaries) { summary in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onToggleReaction?(summary.emoji)
                    } label: {
                        HStack(spacing: 4) {
                            Text(summary.emoji)
                                .font(.system(size: 13))
                            Text("\(summary.count)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(summary.hasReacted ? Color.slooshAccent : .primary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(summary.hasReacted ? Color.slooshAccent.opacity(0.18) : Color.primary.opacity(0.06))
                        )
                        .glassEffect(in: Capsule())
                    }
                    .buttonStyle(PeakPressButtonStyle())
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        // Emoji quick reactions
        Menu {
            ForEach(availableEmojis, id: \.self) { emoji in
                Button {
                    onToggleReaction?(emoji)
                } label: {
                    Text(emoji)
                }
            }
        } label: {
            Label("Реакция", systemImage: "face.smiling")
        }

        if let text = post.text, !text.isEmpty {
            Button {
                UIPasteboard.general.string = text
            } label: {
                Label("Скопировать текст", systemImage: "doc.on.doc")
            }
        }

        if isAuthor {
            Divider()

            Button {
                onTogglePin?()
            } label: {
                Label(post.isPinned ? "Открепить" : "Закрепить", systemImage: "pin")
            }

            Button {
                onEditPost?()
            } label: {
                Label("Редактировать", systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDeletePost?()
            } label: {
                Label("Удалить пост", systemImage: "trash")
            }
        }
    }

    private func formatViews(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        }
        return "\(count)"
    }

    private func formatTimestamp(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}
