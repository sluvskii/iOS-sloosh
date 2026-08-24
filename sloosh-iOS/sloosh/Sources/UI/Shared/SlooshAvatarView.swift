import SwiftUI
import UIKit

public struct SlooshAvatarView: View {
    public let avatarSource: String?
    public let fallbackText: String
    public let size: CGFloat
    public var accentColor: Color? = nil
    public var isChannel: Bool = false
    public var showOnline: Bool = false
    public var isOnline: Bool = false

    public init(
        avatarSource: String?,
        fallbackText: String,
        size: CGFloat,
        accentColor: Color? = nil,
        isChannel: Bool = false,
        showOnline: Bool = false,
        isOnline: Bool = false
    ) {
        self.avatarSource = avatarSource
        self.fallbackText = fallbackText
        self.size = size
        self.accentColor = accentColor
        self.isChannel = isChannel
        self.showOnline = showOnline
        self.isOnline = isOnline
    }

    public init(user: SlooshUser, size: CGFloat, showOnline: Bool = false) {
        self.init(
            avatarSource: user.avatarUrl,
            fallbackText: user.displayName.isEmpty ? (user.tag ?? "S") : user.displayName,
            size: size,
            accentColor: Color.slooshAccent,
            isChannel: false,
            showOnline: showOnline,
            isOnline: user.isOnline ?? false
        )
    }

    public init(channel: ChannelModel, size: CGFloat) {
        self.init(
            avatarSource: channel.avatarUrl,
            fallbackText: channel.name,
            size: size,
            accentColor: channel.displayAccentColor,
            isChannel: true,
            showOnline: false,
            isOnline: false
        )
    }

    public init(userProfile: UserProfile?, size: CGFloat) {
        self.init(
            avatarSource: userProfile?.photoURL,
            fallbackText: userProfile?.displayName ?? userProfile?.tag ?? "S",
            size: size,
            accentColor: Color.slooshAccent,
            isChannel: false,
            showOnline: false,
            isOnline: true
        )
    }

    public var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
                .frame(width: size, height: size)
                .clipShape(Circle())

            if isChannel {
                channelBadge
            } else if showOnline && isOnline {
                onlineBadge
            }
        }
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let decoded = AvatarImageProcessor.decodeImage(from: avatarSource) {
            Image(uiImage: decoded)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if let source = avatarSource, let url = URL(string: source), source.starts(with: "http") {
            AsyncCachedImage(url: url) {
                fallbackView
            } content: { img in
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } fallback: {
                fallbackView
            }
        } else {
            fallbackView
        }
    }

    private var fallbackView: some View {
        ZStack {
            Circle()
                .fill((accentColor ?? Color.slooshAccent).opacity(0.16))

            Text(initialLetter)
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundColor(accentColor ?? Color.slooshAccent)
        }
        .frame(width: size, height: size)
        .glassEffect(.regular.interactive(), in: Circle())
    }

    private var initialLetter: String {
        let trimmed = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = trimmed.first {
            return String(first).uppercased()
        }
        return "S"
    }

    private var channelBadge: some View {
        Circle()
            .fill(Color(UIColor.systemBackground))
            .frame(width: max(16, size * 0.32), height: max(16, size * 0.32))
            .overlay(
                Circle()
                    .fill(Color.slooshAccent)
                    .frame(width: max(13, size * 0.26), height: max(13, size * 0.26))
                    .overlay(
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: max(7, size * 0.11), weight: .bold))
                            .foregroundColor(.black)
                    )
            )
            .offset(x: 2, y: 2)
    }

    private var onlineBadge: some View {
        Circle()
            .fill(Color(UIColor.systemBackground))
            .frame(width: max(14, size * 0.28), height: max(14, size * 0.28))
            .overlay(
                Circle()
                    .fill(Color.green)
                    .frame(width: max(11, size * 0.22), height: max(11, size * 0.22))
            )
            .offset(x: 1, y: 1)
    }
}
