import SwiftUI

public struct PinnedPostBar: View {
    public let post: ChannelPost
    public let onTap: (String) -> Void
    public var onUnpin: (() -> Void)? = nil

    public init(
        post: ChannelPost,
        onTap: @escaping (String) -> Void,
        onUnpin: (() -> Void)? = nil
    ) {
        self.post = post
        self.onTap = onTap
        self.onUnpin = onUnpin
    }

    private var previewText: String {
        if let media = post.media {
            return "🎬 \(media.title)"
        }
        if let text = post.text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return "Сообщение"
    }

    public var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap(post.id)
        } label: {
            HStack(spacing: 10) {
                // Pin accent bar & icon
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Color.slooshAccent)
                    .frame(width: 3, height: 28)

                Image(systemName: "pin.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color.slooshAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Закрепленное сообщение")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.slooshAccent)

                    Text(previewText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if let onUnpin = onUnpin {
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        onUnpin()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                        .padding(.trailing, 2)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
