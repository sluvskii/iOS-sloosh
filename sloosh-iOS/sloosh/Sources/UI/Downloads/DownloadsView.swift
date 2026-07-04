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

struct GroupedShow: Identifiable {
    var id: Int { kpId }
    let kpId: Int
    let title: String
    let posterUrl: String?
    let localDirectory: String
    let items: [DownloadItem]
}

struct DownloadsView: View {
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var selectedFilter = 0 // 0 = Все, 1 = Фильмы, 2 = Сериалы
    @State private var playerItem: DownloadItem? = nil
    
    private var filteredMovies: [DownloadItem] {
        downloadManager.downloads.filter { $0.mediaType == "movie" && !isCartoonByTitle($0.title) }
    }
    
    private var filteredCartoonsMovies: [DownloadItem] {
        downloadManager.downloads.filter { $0.mediaType == "movie" && isCartoonByTitle($0.title) }
    }
    
    private var groupedShows: [GroupedShow] {
        let seriesItems = downloadManager.downloads.filter { $0.mediaType == "tv" && !isCartoonByTitle($0.title) }
        return groupSeries(seriesItems)
    }
    
    private var groupedCartoonsShows: [GroupedShow] {
        let seriesItems = downloadManager.downloads.filter { $0.mediaType == "tv" && isCartoonByTitle($0.title) }
        return groupSeries(seriesItems)
    }
    
    private func groupSeries(_ seriesItems: [DownloadItem]) -> [GroupedShow] {
        let grouped = Dictionary(grouping: seriesItems, by: { $0.kpId })
        return grouped.map { kpId, items -> GroupedShow in
            let first = items.first!
            return GroupedShow(
                kpId: kpId,
                title: first.title,
                posterUrl: first.posterUrl,
                localDirectory: first.localDirectory,
                items: items.sorted(by: {
                    if $0.season != $1.season { return ($0.season ?? 0) < ($1.season ?? 0) }
                    return ($0.episode ?? 0) < ($1.episode ?? 0)
                })
            )
        }.sorted(by: { $0.title < $1.title })
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 22) {
                        ForEach(Array(["Все", "Фильмы", "Сериалы", "Мультфильмы"].enumerated()), id: \.offset) { index, title in
                            let isSelected = selectedFilter == index
                            let isFirst = index == 0
                            let isLast = index == 3
                            
                            Button(action: {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.prepare()
                                generator.impactOccurred()
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.78, blendDuration: 0.1)) {
                                    selectedFilter = index
                                }
                            }) {
                                Text(title)
                                    .font(.system(size: 24, weight: isSelected ? .bold : .semibold))
                                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(DownloadsTabScaleButtonStyle())
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .padding(.leading, isFirst ? 16 : 0)
                            .padding(.trailing, isLast ? 16 : 0)
                        }
                    }
                }
                .padding(.top, 16)
                .padding(.bottom, 12)
                
                if downloadManager.downloads.isEmpty {
                    emptyView
                } else {
                    List {
                        // 1. Movies Section (not cartoons)
                        if selectedFilter == 0 || selectedFilter == 1 {
                            if !filteredMovies.isEmpty {
                                Section(selectedFilter == 0 ? "Фильмы" : "") {
                                    ForEach(filteredMovies) { item in
                                        movieRow(item: item)
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        
                        // 2. Cartoon Movies Section
                        if selectedFilter == 0 || selectedFilter == 3 {
                            if !filteredCartoonsMovies.isEmpty {
                                Section(selectedFilter == 0 ? "Мультфильмы" : "Мультфильмы (фильмы)") {
                                    ForEach(filteredCartoonsMovies) { item in
                                        movieRow(item: item)
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        
                        // 3. Shows Section (not cartoons)
                        if selectedFilter == 0 || selectedFilter == 2 {
                            if !groupedShows.isEmpty {
                                Section(selectedFilter == 0 ? "Сериалы" : "") {
                                    ForEach(groupedShows) { show in
                                        showRow(show: show)
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                        
                        // 4. Cartoon Series Section
                        if selectedFilter == 0 || selectedFilter == 3 {
                            if !groupedCartoonsShows.isEmpty {
                                Section(selectedFilter == 0 ? "Мультсериалы" : "Мультсериалы") {
                                    ForEach(groupedCartoonsShows) { show in
                                        showRow(show: show)
                                    }
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollIndicators(.hidden)
                }
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
    
    @ViewBuilder
    private func showRow(show: GroupedShow) -> some View {
        NavigationLink(destination: DownloadedShowEpisodesView(show: show)) {
            HStack(spacing: 14) {
                DownloadPosterImage(localUrl: show.items.first?.localPosterUrl, remoteUrl: show.posterUrl)
                    .frame(width: 66, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(show.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text("\(show.items.count) \(pluralizeEpisodes(show.items.count))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(show.items.first?.translationName ?? "")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.trailing, 4)
            }
            .padding(10)
            .glassEffect(in: RoundedRectangle(cornerRadius: 14))
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                withAnimation {
                    for item in show.items {
                        DownloadManager.shared.deleteDownload(id: item.id)
                    }
                }
            } label: {
                Label("Удалить все", systemImage: "trash.fill")
            }
        }
    }
    
    private func pluralizeEpisodes(_ count: Int) -> String {
        let remainder10 = count % 10
        let remainder100 = count % 100
        
        if remainder100 >= 11 && remainder100 <= 19 {
            return "серий"
        }
        if remainder10 == 1 {
            return "серия"
        }
        if remainder10 >= 2 && remainder10 <= 4 {
            return "серии"
        }
        return "серий"
    }
}

struct DownloadedShowEpisodesView: View {
    let show: GroupedShow
    @ObservedObject private var downloadManager = DownloadManager.shared
    @State private var playerItem: DownloadItem? = nil
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(show.items) { item in
                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.episodeTitle ?? "Эпизод")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                            
                            if let voice = item.translationName, !voice.isEmpty {
                                Text(voice)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack(spacing: 8) {
                                Text(item.sizeString)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.secondary)
                                
                                if item.status == .downloading {
                                    Text("• Скачивание...")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(Color.slooshAccent)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Play Button
                        if item.status == .completed {
                            Button(action: {
                                playerItem = item
                            }) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.primary)
                                    .frame(width: 38, height: 38)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 12))
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
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .navigationTitle(show.title)
        .navigationBarTitleDisplayMode(.inline)
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

struct DownloadsTabScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
