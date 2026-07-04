import SwiftUI

struct DownloadPosterImage: View {
    let localUrl: URL?
    let remoteUrl: String?
    
    var body: some View {
        Group {
            if let localUrl = localUrl, FileManager.default.fileExists(atPath: localUrl.path) {
                if let image = UIImage(contentsOfFile: localUrl.path) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    fallbackView
                }
            } else if let remoteUrl = remoteUrl, let url = URL(string: remoteUrl) {
                AsyncCachedImage(url: url) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .shimmer()
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } fallback: {
                    fallbackView
                }
            } else {
                fallbackView
            }
        }
    }
    
    private var fallbackView: some View {
        ZStack {
            Color.gray.opacity(0.12)
            Image(systemName: "film")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
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
                            movieRow(item: item)
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
            }
            .safeAreaBar(edge: .top, spacing: 0) {
                DownloadsCategoryTextTabs(selectedFilter: $selectedFilter)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
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
                    directStreamUrl: item.localPlayableUrl.absoluteString
                )
            }
        }
    }
    
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
    
    @ViewBuilder
    private func movieRow(item: DownloadItem) -> some View {
        HStack(spacing: 14) {
            DownloadPosterImage(localUrl: item.localPosterUrl, remoteUrl: item.posterUrl)
                .frame(width: 66, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
            
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                
                if let season = item.season, let episode = item.episode {
                    Text("\(season) сезон, \(episode) серия")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                }
                
                if let voice = item.translationName, !voice.isEmpty {
                    Text(voice)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                
                Spacer(minLength: 0)
                
                // Progress or Completed details
                if item.status == .downloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: item.progress)
                            .tint(Color.slooshAccent)
                            .scaleEffect(x: 1, y: 0.8, anchor: .center)
                        
                        Text("Скачивание... \(Int(item.progress * 100))%")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else if item.status == .pending {
                    Text("В очереди...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                } else if item.status == .completed {
                    Text(item.sizeString)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                } else if item.status == .failed {
                    Text(item.errorMessage ?? "Ошибка загрузки")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                }
            }
            .padding(.vertical, 4)
            
            Spacer()
            
            // Action button
            if item.status == .completed {
                Button(action: {
                    playerItem = item
                }) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.primary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else if item.status == .downloading || item.status == .pending {
                Button(action: {
                    DownloadManager.shared.pauseDownload(id: item.id)
                }) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.primary)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            } else if item.status == .failed {
                // Retry action
                Button(action: {
                    // Start resolved downloader through DetailsViewModel fetch or manager
                    // Since it requires MediaDetailsDto, the easiest way to download failed is deleting and doing it from details page, or simple restart if we store metadata. For simplicity, we can let user delete it or resume if it's paused.
                    if item.errorMessage == "Приостановлено" {
                        // Let's create dummy MediaDetailsDto from item data to resume
                        let details = MediaDetailsDto(
                            id: "kp_\(item.kpId)",
                            sourceId: String(item.kpId),
                            title: item.title,
                            name: item.title,
                            originalTitle: nil,
                            description: nil,
                            releaseDate: nil,
                            type: item.mediaType,
                            genres: nil,
                            rating: nil,
                            posterUrl: item.posterUrl,
                            backdropUrl: nil,
                            duration: nil,
                            country: nil,
                            language: nil,
                            externalIds: ExternalIdsDto(kp: item.kpId, tmdb: nil, imdb: nil)
                        )
                        DownloadManager.shared.startDownload(
                            details: details,
                            season: item.season,
                            episode: item.episode,
                            translation: AllohaTranslation(id: "", name: item.translationName ?? "", iframeUrl: item.iframeUrl, streamUrl: nil),
                            preferredQuality: .ask
                        )
                    } else {
                        DownloadManager.shared.deleteDownload(id: item.id)
                    }
                }) {
                    Image(systemName: item.errorMessage == "Приостановлено" ? "arrow.clockwise" : "trash.fill")
                        .font(.system(size: 15))
                        .foregroundColor(item.errorMessage == "Приостановлено" ? .primary : .red)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .glassEffect(in: RoundedRectangle(cornerRadius: 14))
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
