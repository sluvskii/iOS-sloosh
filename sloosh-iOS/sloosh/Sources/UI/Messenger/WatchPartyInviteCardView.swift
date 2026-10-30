import SwiftUI

// MARK: - Watch Party Invite Card in Messenger

struct WatchPartyInviteCardView: View {
    let payload: WatchPartyInvitePayload
    let isFromMe: Bool
    let onJoin: (WatchPartyInvitePayload) -> Void

    @Environment(\.colorScheme) private var colorScheme

    private var subtitleText: String? {
        var parts: [String] = []
        if let s = payload.season, let e = payload.episode {
            parts.append("Сезон \(s), Серия \(e)")
        }
        if let tr = payload.translationName, !tr.isEmpty {
            parts.append(tr)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header badge
            HStack(spacing: 6) {
                Image(systemName: "shareplay")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(payload.status == .active ? Color.green : Color.secondary)

                Text(payload.status == .active ? "Совместный просмотр" : "Просмотр завершён")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(payload.status == .active ? (colorScheme == .dark ? .white : .primary) : .secondary)

                Spacer()

                if payload.status == .active {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                }
            }

            // Media row: poster + title/details
            HStack(spacing: 10) {
                if let posterUrl = payload.posterUrl, let url = URL(string: posterUrl) {
                    AsyncCachedImage(url: url) {
                        Rectangle().fill(Color.white.opacity(0.1))
                    } content: { image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(2/3, contentMode: .fill)
                    } fallback: {
                        Rectangle().fill(Color.white.opacity(0.08))
                            .overlay {
                                Image(systemName: "film")
                                    .font(.system(size: 16))
                                    .foregroundColor(.secondary)
                            }
                    }
                    .frame(width: 48, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(payload.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(colorScheme == .dark ? .white : .primary)
                        .lineLimit(2)

                    if let subtitle = subtitleText {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }

            // Action button
            if payload.status == .active {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onJoin(payload)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Присоединиться")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(maxWidth: 290)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
