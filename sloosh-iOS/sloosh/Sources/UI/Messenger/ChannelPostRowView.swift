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

    @State private var showReactionPicker: Bool = false

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
        HStack(alignment: .bottom, spacing: 6) {
            VStack(alignment: .leading, spacing: 5) {
                // Floating Reaction Picker
                if showReactionPicker {
                    ChannelReactionPickerView { emoji in
                        onToggleReaction?(emoji)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            showReactionPicker = false
                        }
                    }
                    .transition(.scale(scale: 0.35).combined(with: .opacity).combined(with: .move(edge: .bottom)))
                }

                // Bubble Container with reactions overlay
                ZStack(alignment: .bottomLeading) {
                    bubbleBody
                        .onTapGesture(count: 2) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onToggleReaction?("❤️")
                        }

                    if let postReactions = post.reactions, !postReactions.isEmpty {
                        reactionsOverlay(postReactions)
                    }
                }
                .padding(.bottom, (post.reactions?.isEmpty == false) ? 8 : 0)

                // Meta row: views, edited, time
                metaRow
            }

            Spacer(minLength: 40)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
        .animation(.spring(response: 0.32, dampingFraction: 0.78), value: showReactionPicker)
        .onAppear {
            MessengerRepository.shared.recordChannelPostView(channelId: post.channelId, postId: post.id)
        }
    }

    // MARK: - Bubble Body

    @ViewBuilder
    private var bubbleBody: some View {
        if let media = post.media {
            MediaMessageCardView(
                media: media,
                onOpenDetails: onOpenDetails,
                onPlayDirectly: onPlayDirectly
            )
            .contextMenu {
                contextMenuContent
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
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

                // Post Text
                if let text = post.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(text)
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
            .contextMenu {
                contextMenuContent
            }
        }
    }

    // MARK: - Meta Row

    private var metaRow: some View {
        HStack(spacing: 6) {
            HStack(spacing: 3) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 10))
                Text(formatViews(post.viewsCount ?? 1))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.secondary)

            if post.isEdited == true {
                Text("изм.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Text(formatTimestamp(post.timestampMs))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Reactions Overlay

    @ViewBuilder
    private func reactionsOverlay(_ reactionsDict: [String: String]) -> some View {
        let grouped = Dictionary(grouping: reactionsDict.values, by: { $0 })
        HStack(spacing: 4) {
            ForEach(grouped.map { ($0.key, $0.value.count) }, id: \.0) { emoji, count in
                let isMyReaction = (reactionsDict[currentUserId] == emoji)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onToggleReaction?(emoji)
                } label: {
                    HStack(spacing: 3) {
                        Text(emoji)
                            .font(.system(size: 12.5))
                        if count > 1 {
                            Text("\(count)")
                                .font(.system(size: 11.5, weight: .bold))
                                .foregroundColor(isMyReaction ? .black : .primary)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        isMyReaction ? Color.slooshAccent : Color(UIColor.secondarySystemGroupedBackground)
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(
                                isMyReaction ? Color.slooshAccent : Color(UIColor.separator).opacity(0.4),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: isMyReaction ? Color.slooshAccent.opacity(0.35) : Color.black.opacity(0.1),
                        radius: isMyReaction ? 4 : 2,
                        x: 0,
                        y: 1
                    )
                }
                .buttonStyle(PeakPressButtonStyle())
            }
        }
        .offset(y: 10)
        .padding(.horizontal, 8)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: reactionsDict)
    }

    // MARK: - Unified Context Menu

    @ViewBuilder
    private var contextMenuContent: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                showReactionPicker.toggle()
            }
        } label: {
            Label("Реакция...", systemImage: "face.smiling")
        }

        if let text = post.text, !text.isEmpty {
            Button {
                UIPasteboard.general.string = text
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("Скопировать текст", systemImage: "doc.on.doc")
            }
        }

        if isAuthor {
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

// MARK: - Channel Reaction Picker

private struct ChannelReactionPickerView: View {
    let onSelect: (String) -> Void
    private let emojis = ["❤️", "👍", "🔥", "😂", "🍿", "👏", "😢"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 24))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ChannelOpaquePressButtonStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: Capsule())
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
    }
}

private struct ChannelOpaquePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1.0)
            .opacity(1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.68), value: configuration.isPressed)
    }
}
