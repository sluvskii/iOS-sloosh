import SwiftUI

private struct DownloadArtworkView: View {
    let localUrl: URL?
    let remoteUrl: String?

    var body: some View {
        Group {
            if let local = localUrl, let image = UIImage(contentsOfFile: local.path) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let remote = remoteUrl, let normalized = normalizeImageUrl(path: remote), let url = URL(string: normalized) {
                AsyncCachedImage(url: url) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.18))
                        .overlay {
                            Rectangle()
                                .fill(Color.gray.opacity(0.12))
                                .shimmer()
                        }
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } fallback: {
                    DownloadArtworkPlaceholder()
                }
            } else {
                DownloadArtworkPlaceholder()
            }
        }
        .background(Color(UIColor.secondarySystemFill))
    }
}

private struct DownloadArtworkPlaceholder: View {
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

            Image(systemName: "film")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

struct DownloadsView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var selectedFilter = 0 // 0 = Все, 1 = Фильмы, 2 = Сериалы
    @State private var playerItem: DownloadItem? = nil
    
    private var listItems: [DownloadItem] {
        downloadManager.downloads.filter { item in
            let isCartoon = isCartoonByTitle(item.title)
            switch selectedFilter {
            case 0: return true
            case 1: return item.mediaType == "movie" && !isCartoon
            case 2: return item.mediaType == "tv" && !isCartoon
            case 3: return isCartoon
            default: return true
            }
        }.sorted(by: { $0.addedAt > $1.addedAt })
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if downloadManager.downloads.isEmpty {
                    emptyView
                } else {
                    List {
                        ForEach(listItems) { item in
                            Button {
                                if item.status == .completed {
                                    playerItem = item
                                }
                            } label: {
                                DownloadRowView(item: item)
                            }
                            .buttonStyle(DownloadCardScaleButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.hidden)
                    .contentMargins(.top, 16, for: .scrollContent)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                DownloadsCategoryTextTabs(selectedFilter: $selectedFilter)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
                    .background(VariableBlurView().ignoresSafeArea(edges: .top))
            }
            .navigationTitle("Загрузки")
            .toolbar(.hidden, for: .navigationBar)
            .background(Color(UIColor.systemBackground))
            .fullScreenCover(item: $playerItem) { item in
                PlayerView(
                    fallbackTitle: item.title,
                    kpId: item.kpId,
                    season: item.season,
                    episode: item.episode,
                    selectedVoiceover: item.translationName,
                    directStreamUrl: item.localPlayableUrl?.absoluteString
                )
            }
        }
    }
    
    @ViewBuilder
    private var emptyView: some View {
        VStack {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 56, weight: .thin))
                .foregroundColor(.secondary)
                .padding(.bottom, 8)
            Text("Нет загрузок")
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Text("Скачивайте фильмы и сериалы для\nпросмотра без интернета")
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DownloadCardScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct DownloadRowView: View {
    let item: DownloadItem
    
    var body: some View {
        HStack(spacing: 16) {
            DownloadArtworkView(localUrl: item.localPosterUrl, remoteUrl: item.posterUrl)
                .frame(width: 100, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                
                if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                if item.status == .downloading {
                    DownloadProgressBar(progress: item.progress)
                        .padding(.top, 4)
                    HStack {
                        Text("Скачивание...")
                        Spacer()
                        Text("\(Int(item.progress * 100))%")
                    }
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                } else if item.status == .pending {
                    Text("В очереди...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if item.status == .failed {
                    Text(item.errorMessage ?? "Ошибка загрузки")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                } else if item.status == .completed {
                    Text(item.sizeString)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)

            statusBadge
        }
        .frame(height: 150)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation {
                    DownloadManager.shared.deleteDownload(id: item.id)
                }
            } label: {
                Label("Удалить", systemImage: "trash.fill")
            }
        }
    }

    private var subtitleText: String? {
        var parts: [String] = []
        if let season = item.season, let episode = item.episode {
            parts.append("\(season) сезон, \(episode) серия")
        }
        if let voice = item.translationName, !voice.isEmpty {
            parts.append(voice)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    @ViewBuilder
    private var statusBadge: some View {
        if item.status == .downloading || item.status == .pending {
            Button(action: { DownloadManager.shared.pauseDownload(id: item.id) }) {
                Image(systemName: "pause.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color(UIColor.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
        } else if item.status == .failed || item.status == .paused {
            Button(action: {
                if item.status == .paused {
                    DownloadManager.shared.resumeDownload(id: item.id)
                } else {
                    DownloadManager.shared.deleteDownload(id: item.id)
                }
            }) {
                Image(systemName: item.status == .paused ? "play.fill" : "trash.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 32, height: 32)
                    .background(Color(UIColor.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct DownloadProgressBar: View {
    let progress: Double
    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.white.opacity(0.2))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.slooshAccent)
                        .frame(width: max(0, geo.size.width * progress))
                }
        }
        .frame(height: 4)
    }
}

private struct DownloadsTabScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct DownloadsCategoryTextTabs: View {
    @Binding var selectedFilter: Int
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 25

    private let titleHeight: CGFloat = 31
    private let titles = ["Все", "Фильмы", "Сериалы", "Мульты"]

    private var tabSpacing: CGFloat {
        horizontalSizeClass == .regular ? 28 : 22
    }

    private var edgeContentInset: CGFloat {
        horizontalSizeClass == .regular ? 18 : 16
    }

    private var tabScrollAnimation: Animation {
        .spring(response: 0.35, dampingFraction: 0.75, blendDuration: 0.1)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: tabSpacing) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                        let isSelected = selectedFilter == index
                        let isFirst = index == 0
                        let isLast = index == titles.count - 1

                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            withAnimation(tabScrollAnimation) {
                                selectedFilter = index
                            }
                        } label: {
                            Text(title)
                                .font(.system(size: titleSize, weight: isSelected ? .bold : .semibold))
                                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .frame(height: titleHeight, alignment: .center)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(DownloadsTabScaleButtonStyle())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .id(index)
                        .padding(.leading, isFirst ? edgeContentInset : 0)
                        .padding(.trailing, isLast ? edgeContentInset : 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollTargetLayout()
            }
            .frame(height: titleHeight + 4, alignment: .topLeading)
            .scrollClipDisabled()
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .animation(tabScrollAnimation, value: selectedFilter)
            .onAppear {
                scrollProxy.scrollTo(selectedFilter, anchor: .center)
            }
            .onChange(of: selectedFilter) { _, newFilter in
                withAnimation(tabScrollAnimation) {
                    scrollProxy.scrollTo(newFilter, anchor: .center)
                }
            }
        }
    }
}
