import SwiftUI

struct ContinueView: View {
    @StateObject private var viewModel = ContinueViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.items.isEmpty && !viewModel.isLoading {
                    ContinueEmptyState()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.items) { item in
                                NavigationLink {
                                    DetailsView(
                                        movieId: item.detailsId,
                                        navigationTransitionID: nil,
                                        navigationTransitionNamespace: nil
                                    )
                                } label: {
                                    ContinueWatchingCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        await viewModel.reload(forceMetadataRefresh: true)
                    }
                }
            }
            .navigationTitle("Продолжить")
            .overlay {
                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                        .controlSize(.large)
                }
            }
            .onAppear {
                Task {
                    await viewModel.reload()
                }
            }
        }
    }
}

private struct ContinueWatchingItem: Identifiable {
    let record: PlaybackProgressRecord
    let metadata: PlaybackMediaMetadata?

    var id: String { record.mediaId }

    var kpId: Int { record.kpId }

    var detailsId: String {
        metadata?.detailsId ?? String(record.kpId)
    }

    var title: String {
        metadata?.title ?? "Без названия"
    }

    var posterUrl: String? {
        metadata?.posterUrl
    }

    var backdropUrl: String? {
        metadata?.backdropUrl
    }

    var progressFraction: Double {
        record.progressFraction
    }

    var episodeBadgeText: String? {
        guard let season = record.season, let episode = record.episode else { return nil }
        return "S\(season):E\(episode)"
    }

    var kindLabel: String {
        if isSeries { return "Сериал" }
        return "Фильм"
    }

    var subtitle: String {
        if let season = record.season, let episode = record.episode {
            return "Сезон \(season) • Серия \(episode)"
        }
        return kindLabel
    }

    var progressText: String {
        "\(ContinueTimeFormatter.playback(record.positionSec)) / \(ContinueTimeFormatter.playback(record.durationSec))"
    }

    var remainingText: String? {
        let remaining = max(record.durationSec - record.positionSec, 0)
        guard remaining > 60 else { return nil }
        return "Осталось \(ContinueTimeFormatter.shortDuration(remaining))"
    }

    var imageURL: URL? {
        URL(string: backdropUrl ?? posterUrl ?? "")
    }

    private var isSeries: Bool {
        if record.isEpisode { return true }
        let lowercasedType = metadata?.type?.lowercased()
        return lowercasedType == "tv" || lowercasedType == "series"
    }
}

@MainActor
private final class ContinueViewModel: ObservableObject {
    @Published var items: [ContinueWatchingItem] = []
    @Published var isLoading = false

    private let store = PlaybackProgressStore.shared
    private var metadataBackfillAttempted = Set<Int>()

    func reload(forceMetadataRefresh: Bool = false) async {
        if isLoading { return }

        isLoading = true
        defer { isLoading = false }

        let records = filteredRecords()
        let (initialItems, missingMetadataKpIds) = makeItems(from: records)
        items = initialItems

        let kpIdsToRefresh: Set<Int>
        if forceMetadataRefresh {
            kpIdsToRefresh = Set(initialItems.map(\.kpId))
        } else {
            kpIdsToRefresh = missingMetadataKpIds.subtracting(metadataBackfillAttempted)
        }

        guard !kpIdsToRefresh.isEmpty else { return }
        metadataBackfillAttempted.formUnion(kpIdsToRefresh)

        await backfillMetadata(for: kpIdsToRefresh)

        let (refreshedItems, _) = makeItems(from: records)
        items = refreshedItems
    }

    private func filteredRecords() -> [PlaybackProgressRecord] {
        store.listProgressRecords()
            .filter { !$0.watched }
            .filter { $0.updatedAtMs > 0 }
            .filter { $0.positionSec >= 30 }
            .filter { $0.durationSec >= 60 }
            .filter { $0.progressFraction >= 0.03 }
            .sorted { $0.updatedAtMs > $1.updatedAtMs }
    }

    private func makeItems(from records: [PlaybackProgressRecord]) -> ([ContinueWatchingItem], Set<Int>) {
        let grouped = Dictionary(grouping: records, by: \.kpId)
        var missingMetadataKpIds = Set<Int>()

        let items = grouped.values.compactMap { group -> ContinueWatchingItem? in
            guard let latestRecord = group.max(by: { $0.updatedAtMs < $1.updatedAtMs }) else { return nil }
            let metadata = store.loadMetadata(kpId: latestRecord.kpId)
            if metadata == nil {
                missingMetadataKpIds.insert(latestRecord.kpId)
            }
            return ContinueWatchingItem(record: latestRecord, metadata: metadata)
        }
        .sorted { $0.record.updatedAtMs > $1.record.updatedAtMs }

        return (items, missingMetadataKpIds)
    }

    private func backfillMetadata(for kpIds: Set<Int>) async {
        for kpId in kpIds.sorted(by: >) {
            do {
                if let details = try await MoviesRepository.shared.getDetails(id: String(kpId)) {
                    store.saveMetadata(details: details)
                    continue
                }

                if let details = try await MoviesRepository.shared.getDetails(id: "kp_\(kpId)") {
                    store.saveMetadata(details: details)
                }
            } catch {
                continue
            }
        }
    }
}

private struct ContinueWatchingCard: View {
    let item: ContinueWatchingItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ContinueArtworkView(url: item.imageURL)

            LinearGradient(
                colors: [
                    .black.opacity(0.10),
                    .black.opacity(0.28),
                    .black.opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ContinuePill(title: item.kindLabel)

                    if let episodeBadgeText = item.episodeBadgeText {
                        ContinuePill(title: episodeBadgeText)
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(item.subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.74))
                        .lineLimit(1)
                }

                ContinueProgressBar(progress: item.progressFraction)

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(item.progressText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.92))

                    Spacer(minLength: 0)

                    if let remainingText = item.remainingText {
                        Text(remainingText)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.72))
                            .lineLimit(1)
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
    }
}

private struct ContinueArtworkView: View {
    let url: URL?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failure:
                ContinueArtworkPlaceholder()
            case .empty:
                Rectangle()
                    .fill(Color.gray.opacity(0.18))
                    .overlay {
                        Rectangle()
                            .fill(Color.gray.opacity(0.12))
                            .shimmer()
                    }
            @unknown default:
                ContinueArtworkPlaceholder()
            }
        }
        .background(Color(UIColor.secondarySystemFill))
    }
}

private struct ContinueArtworkPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(UIColor.secondarySystemFill),
                    Color(UIColor.tertiarySystemFill)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "play.rectangle.on.rectangle.fill")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ContinueProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.18))

                Capsule()
                    .fill(Color.slooshAccent)
                    .frame(width: geometry.size.width * max(0, min(progress, 1)))
            }
        }
        .frame(height: 5)
    }
}

private struct ContinuePill: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.22))
            .clipShape(Capsule())
    }
}

private struct ContinueEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "Пока нечего продолжать",
            systemImage: "clock.arrow.circlepath",
            description: Text("Фильмы и серии, которые ты уже начал смотреть, появятся здесь с прогрессом и временем.")
        )
    }
}

private enum ContinueTimeFormatter {
    static func playback(_ seconds: Double) -> String {
        let clamped = max(Int(seconds.rounded()), 0)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60
        let secs = clamped % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%d:%02d", minutes, secs)
    }

    static func shortDuration(_ seconds: Double) -> String {
        let clamped = max(Int(seconds.rounded()), 0)
        let hours = clamped / 3600
        let minutes = (clamped % 3600) / 60

        if hours > 0 {
            return minutes > 0 ? "\(hours) ч \(minutes) мин" : "\(hours) ч"
        }

        if minutes > 0 {
            return "\(minutes) мин"
        }

        return "\(max(clamped, 1)) сек"
    }
}
