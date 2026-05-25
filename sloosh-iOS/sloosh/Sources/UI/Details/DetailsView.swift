import SwiftUI

struct RemoteBackdropView: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
            } else {
                Rectangle().fill(Color.gray.opacity(0.2))
                    .frame(width: width, height: height)
                    .shimmer()
            }
        }
        .task(id: url) {
            guard let url = url, image == nil else { return }
            isLoading = true
            do {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
                let (data, _) = try await URLSession.shared.data(for: request)
                if let uiImg = UIImage(data: data) {
                    self.image = uiImg
                }
            } catch {
                // Ignore error, just keep placeholder
            }
            isLoading = false
        }
    }
}

struct DetailsView: View {
    let movieId: String
    @StateObject private var viewModel = DetailsViewModel()
    
    @State private var showPlayer = false
    @State private var selectedIframeUrl: String? = nil
    @Namespace private var transition
    
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    ProgressView("Загрузка...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                } else if let details = viewModel.details {
                    // Stretchy Backdrop
                    GeometryReader { geometry in
                        let minY = geometry.frame(in: .global).minY
                        let isScrollingDown = minY > 0
                        let height = isScrollingDown ? 450 + minY : 450
                        let offset = isScrollingDown ? -minY : 0

                        RemoteBackdropView(
                            url: URL(string: details.displayBackdropUrl ?? details.displayPosterUrl ?? ""),
                            width: geometry.size.width,
                            height: height
                        )
                        .offset(y: offset)
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    .clear,
                                    .clear,
                                    Color(UIColor.systemBackground).opacity(0.6),
                                    Color(UIColor.systemBackground)
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .offset(y: offset)
                        )
                    }
                    .frame(height: 450)
                    
                    VStack(alignment: .center, spacing: 12) {
                        Text(details.title ?? details.name ?? "Без названия")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        DetailsPrimaryMetadataRow(details: details)
                        
                        // Play Button
                        Button(action: {
                            Task {
                                if let kpId = details.externalIds?.kp {
                                    await viewModel.fetchSources(kpId: kpId, title: details.title ?? details.name ?? "")
                                }
                            }
                        }) {
                            HStack {
                                if viewModel.isFetchingSources {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(UIColor.systemBackground)))
                                        .padding(.trailing, 8)
                                } else {
                                    Image(systemName: "play.fill")
                                }
                                Text(viewModel.isFetchingSources ? "Загрузка..." : "Смотреть")
                                    .font(.system(size: 18, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.primary)
                            .foregroundColor(Color(UIColor.systemBackground))
                            .clipShape(Capsule())
                        }
                        .disabled(viewModel.isFetchingSources)
                        .matchedTransitionSource(id: "playBtn", in: transition)
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                        DetailsInfoSection(details: details)
                            .padding(.top, 20)
                            .padding(.horizontal)
                    }
                    .offset(y: -80)
                } else {
                    Text("Не удалось загрузить данные.")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 100)
                }
            }
        }
        .edgesIgnoringSafeArea(.top)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadDetails(id: movieId)
        }
        .sheet(item: $viewModel.sourceResultWrapper) { wrapper in
            if wrapper.mode == .alloha, let result = wrapper.allohaResult {
                SourceSelectionView(result: result) { iframeUrl in
                    selectedIframeUrl = iframeUrl
                    showPlayer = true
                }
                .presentationDetents([.medium, .large])
                .navigationTransition(.zoom(sourceID: "playBtn", in: transition))
            } else if wrapper.mode == .collaps {
                let isSerial = wrapper.collapsSeasons != nil && !(wrapper.collapsSeasons?.isEmpty ?? true)
                CollapsSelectionView(
                    result: wrapper.collapsSeasons ?? [],
                    movieResult: wrapper.collapsMovie,
                    isSerial: isSerial,
                    title: viewModel.details?.title ?? viewModel.details?.name ?? "",
                    onPlay: { url in
                        // Collaps returns direct HLS/MPD urls
                        selectedIframeUrl = url // we use this state variable for the URL
                        showPlayer = true
                    }
                )
                .presentationDetents([.medium, .large])
                .navigationTransition(.zoom(sourceID: "playBtn", in: transition))
            } else {
                Text("Нет доступных источников")
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let url = selectedIframeUrl, let details = viewModel.details {
                let mode = SourceManager.shared.currentMode
                if mode == .alloha {
                    PlayerView(iframeUrl: url, fallbackTitle: details.title ?? details.name ?? "")
                } else {
                    PlayerView(directVideoUrl: url, fallbackTitle: details.title ?? details.name ?? "")
                }
            }
        }
    }
}

private struct DetailsPrimaryMetadataRow: View {
    let details: MediaDetailsDto

    var body: some View {
        HStack(spacing: 8) {
            if let rating = details.rating, rating > 0 {
                Label(String(format: "%.1f", rating), systemImage: "star.fill")
                    .foregroundColor(.orange)
            }

            if let year = details.releaseDate?.prefix(4), !year.isEmpty {
                Text(String(year))
            }

            if let type = details.type?.uppercased(), !type.isEmpty {
                Text(type == "TV" ? "Сериал" : "Фильм")
            }

            if let duration = details.duration, duration > 0 {
                Text("\(duration) мин")
            }
        }
        .font(.system(size: 15, weight: .semibold, design: .rounded))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
}

private struct DetailsInfoSection: View {
    let details: MediaDetailsDto

    private var genres: [String] {
        details.genres?
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    private var infoItems: [(String, String)] {
        var items: [(String, String)] = []

        if let originalTitle = details.originalTitle, !originalTitle.isEmpty, originalTitle != details.title {
            items.append(("Оригинальное название", originalTitle))
        }

        if let country = details.country, !country.isEmpty {
            items.append(("Страна", country))
        }

        if let language = details.language, !language.isEmpty {
            items.append(("Язык", language))
        }

        if let sourceId = details.sourceId, !sourceId.isEmpty {
            items.append(("ID источника", sourceId))
        }

        if let imdb = details.externalIds?.imdb, !imdb.isEmpty {
            items.append(("IMDb", imdb))
        }

        if let tmdb = details.externalIds?.tmdb {
            items.append(("TMDb", "\(tmdb)"))
        }

        if let kp = details.externalIds?.kp {
            items.append(("Кинопоиск", "\(kp)"))
        }

        return items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !genres.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Жанры")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    FlowLayout(spacing: 8) {
                        ForEach(genres, id: \.self) { genre in
                            Text(genre)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Описание")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                Text(details.description ?? "Описание отсутствует.")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
                    .lineSpacing(4)
            }

            if !infoItems.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Информация")
                        .font(.system(size: 18, weight: .bold, design: .rounded))

                    VStack(spacing: 10) {
                        ForEach(infoItems, id: \.0) { item in
                            HStack(alignment: .top, spacing: 12) {
                                Text(item.0)
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .frame(width: 140, alignment: .leading)

                                Text(item.1)
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(16)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    )
                }
            }

            HStack(spacing: 10) {
                Label(SourceManager.shared.currentMode.displayName, systemImage: "antenna.radiowaves.left.and.right")
                if let type = details.type, !type.isEmpty {
                    Label(type == "tv" ? "Сериал" : "Фильм", systemImage: "film")
                }
            }
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .foregroundColor(.secondary)
        }
    }
}

// Обертка для Identifiable, чтобы использовать в .sheet(item:)
struct SourceResultWrapper: Identifiable {
    let id = UUID()
    let mode: SourceMode
    var allohaResult: AllohaApiResult?
    var collapsSeasons: [CollapsSeason]?
    var collapsMovie: CollapsMovie?
}

@MainActor
class DetailsViewModel: ObservableObject {
    @Published var details: MediaDetailsDto?
    @Published var isLoading = true
    
    @Published var isFetchingSources = false
    @Published var sourceResultWrapper: SourceResultWrapper?
    
    func loadDetails(id: String) async {
        if details != nil && (details?.id == id || details?.sourceId == id || details?.externalIds?.kp?.description == id.replacingOccurrences(of: "kp_", with: "")) {
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            details = try await MoviesRepository.shared.getDetails(id: id)
        } catch {
            print("Error loading details: \(error)")
        }
    }
    
    func fetchSources(kpId: Int, title: String) async {
        isFetchingSources = true
        defer { isFetchingSources = false }
        
        let mode = SourceManager.shared.currentMode
        do {
            switch mode {
            case .alloha:
                let result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId)
                self.sourceResultWrapper = SourceResultWrapper(mode: .alloha, allohaResult: result)
            case .collaps:
                let seasons = try await CollapsRepository.shared.getSeasonsByKpId(kpId: kpId)
                if seasons.isEmpty {
                    let movie = try await CollapsRepository.shared.getMovieByKpId(kpId: kpId)
                    self.sourceResultWrapper = SourceResultWrapper(mode: .collaps, collapsMovie: movie)
                } else {
                    self.sourceResultWrapper = SourceResultWrapper(mode: .collaps, collapsSeasons: seasons)
                }
            }
        } catch {
            print("Error fetching sources: \(error)")
        }
    }
}
