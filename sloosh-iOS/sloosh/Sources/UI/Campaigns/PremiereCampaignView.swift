import SwiftUI

/// Mounted ONLY in the existing unreleased-title slot on Details. Other films
/// render their original capsule and do not even start a countdown clock.
struct PremiereCampaignSlot<Fallback: View>: View {
    let details: MediaDetailsDto
    let mediaType: String?
    @ViewBuilder let fallback: () -> Fallback
    @ObservedObject private var store = RemoteCampaignStore.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false
    @State private var now = Date()

    private func selectedCampaign(at date: Date) -> RemoteCampaign? {
        store.detailsCampaign(
            id: details.id, type: details.type ?? mediaType,
            tmdbId: details.externalIds?.tmdb ?? details.ids?.tmdb, at: date
        )
    }

    private var shouldTick: Bool {
        isVisible && scenePhase == .active && selectedCampaign(at: now) != nil
    }

    var body: some View {
        Group {
            if let campaign = selectedCampaign(at: now) {
                content(campaign, at: now)
            } else {
                fallback()
            }
        }
        .onAppear { now = Date(); isVisible = true }
        .onDisappear { isVisible = false }
        .onScrollVisibilityChange(threshold: 0.05) { isVisible = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        .onReceive(store.$campaigns) { _ in
            now = Date()
        }
        .task(id: shouldTick) {
            guard shouldTick else { return }
            // One local clock in this small slot, not in DetailsView's body.
            // Cancellation is tied to visibility, scene activity and expiry.
            while !Task.isCancelled {
                now = Date()
                guard let campaign = selectedCampaign(at: now) else { return }
                let untilStart = campaign.startsAt.timeIntervalSince(now)
                let interval = untilStart > 0 ? min(60, max(0.1, untilStart)) : 1
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch { return }
            }
        }
    }

    @ViewBuilder
    private func content(_ campaign: RemoteCampaign, at now: Date) -> some View {
        if store.isFresh(at: now) && campaign.isActive(at: now) {
            PremiereCampaignView(campaign: campaign, now: now)
                .padding(.horizontal, 16)
        } else {
            // Expiry/kill switch restores the exact original premiere capsule.
            // It never enables playback or changes the backend release state.
            fallback()
        }
    }
}

private struct PremiereCampaignView: View {
    let campaign: RemoteCampaign
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title) private var digitSize: CGFloat = 30

    private var tint: Color {
        switch campaign.theme {
        case .emerald: return Color(red: 0.60, green: 0.88, blue: 0.49)
        case .crimson: return Color(red: 0.95, green: 0.44, blue: 0.40)
        case .neutral: return .white
        }
    }

    private var isCompleted: Bool {
        campaign.kind == .countdown && campaign.countdownTo.map { now >= $0 } == true
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: isCompleted ? "sparkle" : "hourglass")
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(isCompleted ? (campaign.completedText ?? campaign.title) : campaign.title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(0.4)
                    .multilineTextAlignment(.center)
            }

            if campaign.kind == .countdown, !isCompleted, let target = campaign.countdownTo {
                countdown(until: target)
            }

            VStack(spacing: 4) {
                Text(campaign.subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                if campaign.kind == .countdown {
                    Text(campaign.premiereDateLabel())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                }
                if let disclaimer = campaign.disclaimer {
                    Text(disclaimer)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.60))
                        .padding(.top, 2)
                }
            }
            .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .padding(.vertical, 18)
        .padding(.horizontal, 16)
        .frame(maxWidth: 460)
        .background {
            artwork
                .overlay(Color.black.opacity(0.72))
                .overlay {
                    LinearGradient(colors: [tint.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .clipShape(.rect(cornerRadius: 22))
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(LinearGradient(colors: [tint.opacity(0.35), .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var artwork: some View {
        if let value = campaign.artworkURL, let url = URL(string: value) {
            GeometryReader { geometry in
                AsyncCachedImage(url: url) {
                    tint.opacity(0.10)
                } content: { image in
                    Image(uiImage: image).resizable().scaledToFill()
                } fallback: {
                    tint.opacity(0.10)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
        } else if campaign.bundledArtwork == "doomsday" {
            GeometryReader { geometry in
                Image("CampaignDoomsday")
                    .resizable().scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
            }
        } else {
            tint.opacity(0.08)
        }
    }

    private func countdown(until target: Date) -> some View {
        let value = CampaignCountdown(until: target, now: now)
        return HStack(alignment: .top, spacing: 0) {
            unit(value.days, label: "ДНИ")
            separator
            unit(value.hours, label: "ЧАСЫ")
            separator
            unit(value.minutes, label: "МИНУТЫ")
            separator
            unit(value.seconds, label: "СЕКУНДЫ")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("До дня премьеры: \(value.days) дн., \(value.hours) ч., \(value.minutes) мин.")
        // No live announcement every second; VoiceOver reads the current value
        // only when focused. Reduce Motion removes numeric rolling transitions.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value.seconds)
    }

    private func unit(_ value: Int, label: String) -> some View {
        VStack(spacing: 5) {
            Text(String(format: "%02d", value))
                .font(.system(size: min(digitSize, 44), weight: .light))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.60))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: min(digitSize, 44), weight: .ultraLight))
            .foregroundStyle(tint.opacity(0.6))
            .accessibilityHidden(true)
    }
}
