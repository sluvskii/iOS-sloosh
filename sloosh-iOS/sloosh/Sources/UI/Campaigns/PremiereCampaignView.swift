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

/// Inline typography, not a card: the screen's own backdrop remains untouched.
private struct PremiereCampaignView: View {
    let campaign: RemoteCampaign
    let now: Date
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 36
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 11

    private var isCompleted: Bool {
        campaign.kind == .countdown && campaign.countdownTo.map { now >= $0 } == true
    }

    var body: some View {
        Group {
            if campaign.kind == .countdown, !isCompleted, let target = campaign.countdownTo {
                countdown(until: target)
            } else {
                // Preserve remote feature/completion messages without bringing
                // the old card decoration back into the countdown layout.
                Text(isCompleted ? (campaign.completedText ?? campaign.title) : campaign.title)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 14)
        .frame(maxWidth: 420)
    }

    private func countdown(until target: Date) -> some View {
        let value = CampaignCountdown(until: target, now: now, timeZone: TimeZone(identifier: campaign.timeZone) ?? .gmt)
        return HStack(alignment: .top, spacing: 0) {
            unit(value.months, kind: .months)
            separator
            unit(value.days, kind: .days)
            separator
            unit(value.hours, kind: .hours)
            separator
            unit(value.minutes, kind: .minutes)
            separator
            unit(value.seconds, kind: .seconds)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("До дня премьеры: \(value.spokenDescription)")
        // Stable columns prevent shifting at 10→09 and when labels change.
        // No live announcements every second; Reduce Motion disables rolling.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: value.seconds)
    }

    private var separator: some View {
        Text(":")
            .font(.system(size: min(digitSize, 50) * 0.65, weight: .semibold))
            .foregroundStyle(.white.opacity(0.45))
            .frame(width: 8, height: min(digitSize, 50) * 1.2)
            .accessibilityHidden(true)
    }

    private func unit(_ value: Int, kind: CampaignCountdown.Unit) -> some View {
        VStack(spacing: 6) {
            Text(String(format: "%02d", value))
                .font(.system(size: min(digitSize, 50), weight: .bold))
                .monospacedDigit()
                .tracking(-1)
                .contentTransition(.numericText(countsDown: true))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(height: min(digitSize, 50) * 1.2)
            Text(kind.label(for: value))
                .font(.system(size: min(labelSize, 16), weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Only digits roll. Noun changes should not slide or crossfade.
                .transaction { $0.animation = nil }
        }
        .frame(maxWidth: .infinity)
    }
}
