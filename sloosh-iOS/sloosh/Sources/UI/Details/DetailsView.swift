import SwiftUI
import Photos
import ImageIO

struct BackdropFadeMask: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .black.opacity(0.4), location: 0.06),
                .init(color: .black.opacity(0.85), location: 0.12),
                .init(color: .black, location: 0.18),
                .init(color: .black, location: 0.35),
                .init(color: .black.opacity(0.80), location: 0.50),
                .init(color: .black.opacity(0.45), location: 0.68),
                .init(color: .black.opacity(0.20), location: 0.82),
                .init(color: .black.opacity(0.06), location: 0.93),
                .init(color: .clear, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct RemoteBackdropView: View {
    let url: URL?
    let fallbackUrl: URL?
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        AsyncCachedImage(url: url, fallbackUrl: fallbackUrl) {
            Color.black.opacity(0.3)
                .frame(width: width, height: height)
        } content: { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .clipped()
        } fallback: {
            Color.black.opacity(0.3)
                .frame(width: width, height: height)
        }
        .frame(width: width, height: height)
    }
}

struct BackdropCarouselView: View {
    let urls: [String]
    let fallbackUrl: URL?
    let width: CGFloat
    let height: CGFloat
    @Binding var selectedIndex: Int
    @Binding var timerProgress: CGFloat
    var isHeaderVisible: Bool = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if urls.count <= 1 {
                let firstUrl = urls.first.flatMap { URL(string: $0) }
                RemoteBackdropView(
                    url: firstUrl,
                    fallbackUrl: fallbackUrl,
                    width: width,
                    height: height
                )
            } else {
                BackdropPagingRepresentable(
                    urls: urls,
                    fallbackUrl: fallbackUrl,
                    selectedIndex: $selectedIndex,
                    timerProgress: $timerProgress,
                    isHeaderVisible: isHeaderVisible,
                    scenePhase: scenePhase
                )
            }
        }
        .frame(width: width, height: height)
        .mask(BackdropFadeMask())
    }
}

private struct BackdropPagingRepresentable: UIViewControllerRepresentable {
    let urls: [String]
    let fallbackUrl: URL?
    @Binding var selectedIndex: Int
    @Binding var timerProgress: CGFloat
    var isHeaderVisible: Bool
    var scenePhase: ScenePhase

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pageVC = UIPageViewController(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [UIPageViewController.OptionsKey.interPageSpacing: 0]
        )
        pageVC.view.backgroundColor = .clear
        pageVC.dataSource = context.coordinator
        pageVC.delegate = context.coordinator

        if let scrollView = pageVC.view.subviews.first(where: { $0 is UIScrollView }) as? UIScrollView {
            scrollView.delegate = context.coordinator
        }

        context.coordinator.pageViewController = pageVC
        let initialIndex = (selectedIndex >= 0 && selectedIndex < urls.count) ? selectedIndex : 0
        context.coordinator.currentIndex = initialIndex
        let initialVC = context.coordinator.makeSlideVC(index: initialIndex)
        pageVC.setViewControllers([initialVC], direction: .forward, animated: false)

        // Запускаем таймер на следующем тике runloop, когда вью уже смонтирована в окно
        DispatchQueue.main.async { [weak coordinator = context.coordinator] in
            coordinator?.startTimer()
        }
        return pageVC
    }

    func updateUIViewController(_ pageVC: UIPageViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        let count = urls.count
        guard count > 1 else { return }

        // Если selectedIndex изменился извне (например, по тапу на полоску индикатора)
        if !coordinator.isUserDragging && !coordinator.isTransitioning {
            let targetIndex = selectedIndex % count
            if targetIndex != coordinator.currentIndex {
                let direction: UIPageViewController.NavigationDirection = targetIndex >= coordinator.currentIndex ? .forward : .reverse
                coordinator.currentIndex = targetIndex
                let targetVC = coordinator.makeSlideVC(index: targetIndex)
                coordinator.isTransitioning = true
                pageVC.setViewControllers([targetVC], direction: direction, animated: true) { [weak coordinator] _ in
                    coordinator?.isTransitioning = false
                }
                coordinator.startTimer()
            }
        }

        let isAppActive = scenePhase == .active
        if !isHeaderVisible || !isAppActive {
            coordinator.stopTimer()
        } else if coordinator.timerTask == nil && !coordinator.isUserDragging && !coordinator.isTransitioning {
            DispatchQueue.main.async { [weak coordinator] in
                coordinator?.startTimer()
            }
        }
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate, UIScrollViewDelegate {
        var parent: BackdropPagingRepresentable
        weak var pageViewController: UIPageViewController?
        var currentIndex: Int = 0
        var isUserDragging: Bool = false
        var isTransitioning: Bool = false
        var timerTask: Task<Void, Never>?

        init(_ parent: BackdropPagingRepresentable) {
            self.parent = parent
            self.currentIndex = (parent.selectedIndex >= 0 && parent.selectedIndex < parent.urls.count) ? parent.selectedIndex : 0
        }

        func makeSlideVC(index: Int) -> BackdropSlideViewController {
            let safeIndex = ((index % parent.urls.count) + parent.urls.count) % parent.urls.count
            return BackdropSlideViewController(
                index: safeIndex,
                urlString: parent.urls[safeIndex],
                fallbackUrl: parent.fallbackUrl
            )
        }

        // MARK: - UIPageViewControllerDataSource (Infinite Looping)
        func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let slideVC = viewController as? BackdropSlideViewController, parent.urls.count > 1 else { return nil }
            let prevIndex = (slideVC.index - 1 + parent.urls.count) % parent.urls.count
            return makeSlideVC(index: prevIndex)
        }

        func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let slideVC = viewController as? BackdropSlideViewController, parent.urls.count > 1 else { return nil }
            let nextIndex = (slideVC.index + 1) % parent.urls.count
            return makeSlideVC(index: nextIndex)
        }

        // MARK: - UIPageViewControllerDelegate
        func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {
            isTransitioning = false
            if let currentVC = pageViewController.viewControllers?.first as? BackdropSlideViewController {
                let actualIndex = currentVC.index
                currentIndex = actualIndex
                if parent.selectedIndex != actualIndex {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        parent.selectedIndex = actualIndex
                    }
                }
            }
            startTimer()
        }

        // MARK: - UIScrollViewDelegate (Real-time gesture & drag tracking)
        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            isUserDragging = true
            stopTimer()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard isUserDragging, !isTransitioning else { return }
            let width = scrollView.bounds.width
            guard width > 0, parent.urls.count > 1 else { return }
            let count = parent.urls.count
            let offset = scrollView.contentOffset.x
            let delta = offset - width

            // Как только пользователь перетянул задник более чем на 45% ширины экрана,
            // капсула мгновенно переключается на новый задник прямо под пальцем
            if delta > width * 0.45 {
                let nextIndex = (currentIndex + 1) % count
                if parent.selectedIndex != nextIndex {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        parent.selectedIndex = nextIndex
                    }
                }
            } else if delta < -width * 0.45 {
                let prevIndex = (currentIndex - 1 + count) % count
                if parent.selectedIndex != prevIndex {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        parent.selectedIndex = prevIndex
                    }
                }
            } else if abs(delta) < width * 0.35 {
                // Если пользователь вернул палец обратно к центру
                if parent.selectedIndex != currentIndex {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        parent.selectedIndex = currentIndex
                    }
                }
            }
        }

        func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
            let width = scrollView.bounds.width
            guard width > 0, parent.urls.count > 1 else { return }
            let count = parent.urls.count
            let targetX = targetContentOffset.pointee.x

            // В момент отрыва пальца UIKit уже точно знает целевую страницу:
            // мгновенно переключаем капсулу, не дожидаясь окончания замедления
            let targetIndex: Int
            if targetX > width * 1.4 {
                targetIndex = (currentIndex + 1) % count
            } else if targetX < width * 0.6 {
                targetIndex = (currentIndex - 1 + count) % count
            } else {
                targetIndex = currentIndex
            }

            if parent.selectedIndex != targetIndex {
                withAnimation(.easeInOut(duration: 0.2)) {
                    parent.selectedIndex = targetIndex
                }
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            if !decelerate {
                isUserDragging = false
                startTimer()
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            isUserDragging = false
            startTimer()
        }

        // MARK: - Timer & Progress
        func stopTimer() {
            timerTask?.cancel()
            timerTask = nil
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                parent.timerProgress = 0.0
            }
        }

        func startTimer() {
            stopTimer()
            guard parent.urls.count > 1, parent.isHeaderVisible, parent.scenePhase == .active, !isUserDragging else { return }

            // Prefetch adjacent backdrops
            let count = parent.urls.count
            let nextIdx = (currentIndex + 1) % count
            let prevIdx = (currentIndex - 1 + count) % count
            let prefetchUrls = [parent.urls[nextIdx], parent.urls[prevIdx]].compactMap { URL(string: $0) }
            ImageCache.prefetch(urls: prefetchUrls)

            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                parent.timerProgress = 0.0
            }

            withAnimation(.linear(duration: 5.0)) {
                parent.timerProgress = 1.0
            }

            timerTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self = self, !Task.isCancelled else { return }
                guard self.parent.isHeaderVisible, self.parent.scenePhase == .active, !self.isUserDragging, !self.isTransitioning else { return }
                guard let pageVC = self.pageViewController, self.parent.urls.count > 1 else { return }

                let count = self.parent.urls.count
                let nextIndex = (self.currentIndex + 1) % count
                let nextVC = self.makeSlideVC(index: nextIndex)

                // 1. Сразу обновляем индекс, чтобы капсула начала сужаться в точку синхронно со стартом перелистывания
                self.currentIndex = nextIndex
                withAnimation(.easeInOut(duration: 0.35)) {
                    if self.parent.selectedIndex != nextIndex {
                        self.parent.selectedIndex = nextIndex
                    }
                }

                // 2. Запускаем анимацию перелистывания в UIPageViewController
                self.isTransitioning = true
                pageVC.setViewControllers([nextVC], direction: .forward, animated: true) { [weak self] completed in
                    guard let self = self else { return }
                    self.isTransitioning = false
                    if !completed {
                        if let currentVC = self.pageViewController?.viewControllers?.first as? BackdropSlideViewController {
                            self.currentIndex = currentVC.index
                            if self.parent.selectedIndex != currentVC.index {
                                self.parent.selectedIndex = currentVC.index
                            }
                        }
                    }
                }

                // 3. Сразу запускаем таймер прогресса для новой активной полоски
                self.startTimer()
            }
        }

        deinit {
            stopTimer()
        }
    }
}

private final class BackdropSlideViewController: UIViewController {
    let index: Int
    let urlString: String
    let fallbackUrl: URL?
    private let imageView = UIImageView()
    private var loadTask: Task<Void, Never>?

    init(index: Int, urlString: String, fallbackUrl: URL?) {
        self.index = index
        self.urlString = urlString
        self.fallbackUrl = fallbackUrl
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        loadImage()
    }

    private func loadImage() {
        guard let url = URL(string: urlString) else {
            loadFallback()
            return
        }

        let effectiveUrl = ImageCache.resolveEffectiveUrl(url)
        let key = effectiveUrl?.absoluteString ?? url.absoluteString

        // 1. Instant check from RAM cache
        if let cached = ImageCache.shared.image(forKey: key) ?? ImageCache.shared.image(forKey: url.absoluteString) {
            self.imageView.image = cached
            return
        }

        // 2. Asynchronous background load
        loadTask = Task { [weak self] in
            guard let self = self else { return }
            let targetUrl = effectiveUrl ?? url
            var request = URLRequest(url: targetUrl, cachePolicy: .returnCacheDataElseLoad)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")

            if let cached = URLCache.shared.cachedResponse(for: request),
               let img = UIImage(data: cached.data) {
                let decoded = await img.byPreparingForDisplay() ?? img
                ImageCache.shared.insertImage(decoded, forKey: key)
                ImageCache.shared.insertImage(decoded, forKey: url.absoluteString)
                if !Task.isCancelled {
                    await MainActor.run {
                        self.imageView.image = decoded
                    }
                }
                return
            }

            do {
                let (data, resp) = try await URLSession.shared.data(for: request)
                if Task.isCancelled { return }
                if let http = resp as? HTTPURLResponse, http.statusCode == 200,
                   let img = UIImage(data: data) {
                    let cachedResponse = CachedURLResponse(response: http, data: data)
                    URLCache.shared.storeCachedResponse(cachedResponse, for: request)
                    let decoded = await img.byPreparingForDisplay() ?? img
                    ImageCache.shared.insertImage(decoded, forKey: key)
                    ImageCache.shared.insertImage(decoded, forKey: url.absoluteString)
                    if !Task.isCancelled {
                        await MainActor.run {
                            self.imageView.image = decoded
                        }
                    }
                    return
                }
            } catch {
                if Task.isCancelled { return }
            }

            if !Task.isCancelled {
                await MainActor.run {
                    self.loadFallback()
                }
            }
        }
    }

    private func loadFallback() {
        guard let fallback = fallbackUrl else { return }
        let effectiveFallback = ImageCache.resolveEffectiveUrl(fallback)
        let key = effectiveFallback?.absoluteString ?? fallback.absoluteString
        if let cached = ImageCache.shared.image(forKey: key) ?? ImageCache.shared.image(forKey: fallback.absoluteString) {
            self.imageView.image = cached
        }
    }

    deinit {
        loadTask?.cancel()
    }
}

struct BackdropPageIndicator: View {
    let count: Int
    @Binding var selectedIndex: Int
    let progress: CGFloat
    
    private let activeWidth: CGFloat = 18
    private let inactiveWidth: CGFloat = 5
    private let pillHeight: CGFloat = 4.5
    
    var body: some View {
        if count > 1 {
            HStack(spacing: 5) {
                ForEach(0..<min(count, 8), id: \.self) { idx in
                    let isSelected = idx == selectedIndex
                    let currentWidth = isSelected ? activeWidth : inactiveWidth
                    
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.32))
                        
                        if isSelected {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: activeWidth * max(0.0, min(1.0, progress)))
                        }
                    }
                    .frame(width: currentWidth, height: pillHeight)
                    .clipShape(Capsule())
                    .animation(.easeInOut(duration: 0.25), value: isSelected)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            selectedIndex = idx
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .glassEffect(in: Capsule())
            .padding(.bottom, 2)
        }
    }
}

struct RemoteLogoView: View {
    let url: URL?
    let fallbackTitle: String
    var alignment: Alignment = .center
    var isTopBar: Bool = false
    
    var body: some View {
        AsyncCachedImage(url: url) {
            Text(fallbackTitle)
                .font(.system(size: isTopBar ? 17 : 30, weight: isTopBar ? .bold : .heavy))
                .lineLimit(isTopBar ? 1 : 2)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .padding(.horizontal, alignment == .center ? (isTopBar ? 0 : 16) : 0)
                .shimmer()
                .frame(maxWidth: isTopBar ? nil : 300, maxHeight: isTopBar ? 32 : 110, alignment: alignment)
                .frame(maxWidth: .infinity, alignment: alignment)
        } content: { image in
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: isTopBar ? nil : 300, maxHeight: isTopBar ? 32 : 110, alignment: alignment)
                .padding(.horizontal, alignment == .center ? (isTopBar ? 0 : 16) : 0)
                .shadow(color: .black.opacity(isTopBar ? 0.0 : 0.35), radius: 8, x: 0, y: 4)
                .frame(maxWidth: .infinity, alignment: alignment)
        } fallback: {
            Text(fallbackTitle)
                .font(.system(size: isTopBar ? 17 : 30, weight: isTopBar ? .bold : .heavy))
                .lineLimit(isTopBar ? 1 : 2)
                .multilineTextAlignment(alignment == .leading ? .leading : .center)
                .padding(.horizontal, alignment == .center ? (isTopBar ? 0 : 16) : 0)
                .frame(maxWidth: isTopBar ? nil : 300, maxHeight: isTopBar ? 32 : 110, alignment: alignment)
                .frame(maxWidth: .infinity, alignment: alignment)
                .foregroundStyle(Color.white)
                .shadow(color: .black.opacity(0.8), radius: 6, x: 0, y: 3)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}

struct DetailsView: View {
    let movieId: String
    let mediaType: String?
    let navigationTransitionID: String?
    let navigationTransitionNamespace: Namespace.ID?
    let initialStudio: StudioBrand?
    @StateObject private var viewModel: DetailsViewModel
    @State private var isContentRevealed: Bool = false
    
    init(
        movieId: String,
        mediaType: String? = nil,
        navigationTransitionID: String? = nil,
        navigationTransitionNamespace: Namespace.ID? = nil,
        initialStudio: StudioBrand? = nil
    ) {
        self.movieId = movieId
        self.mediaType = mediaType
        self.navigationTransitionID = navigationTransitionID
        self.navigationTransitionNamespace = navigationTransitionNamespace
        self.initialStudio = initialStudio
        let vm = DetailsViewModel(id: movieId, type: mediaType)
        _viewModel = StateObject(wrappedValue: vm)
    }

    init(
        movieId: String,
        navigationTransitionID: String? = nil,
        navigationTransitionNamespace: Namespace.ID? = nil,
        initialStudio: StudioBrand? = nil
    ) {
        self.init(
            movieId: movieId,
            mediaType: nil,
            navigationTransitionID: navigationTransitionID,
            navigationTransitionNamespace: navigationTransitionNamespace,
            initialStudio: initialStudio
        )
    }
    
    @State private var showPlayer = false
    @State private var pendingPlayerLaunch = false
    @State private var showSourceSheet = false
    @State private var selectedIframeUrl: String? = nil
    @State private var sourceSheetTitle = ""
    @State private var sourceFetchTask: Task<Void, Never>?
    @State private var sourceSheetMode: SourceSelectionMode = .play
    @Namespace private var transition
    @State private var sourceSheetSourceID: String = "playBtn"
    
    @State private var playerKpId: Int?
    @State private var playerTmdbId: Int?
    @State private var playerMediaKey: String?
    @State private var playerSeason: Int?
    @State private var playerEpisode: Int?
    @State private var playerVoiceover: String?
    @State private var playerStreamUrl: String?
    @State private var playerVoices: [String] = []
    @State private var playerSubtitles: [PlaybackSubtitle] = []
    @State private var playerQuality: VideoQualityPreference? = nil
    @State private var playerSeriesResult: AllohaApiResult?
    @State private var playerCustomHeaders: [String: String]? = nil
    @State private var playerStreamSource: MediaStreamSource = .source1
    @State private var playerEpisodeSubtitles: [EpisodeKey: [PlaybackSubtitle]] = [:]
    @State private var favoriteBounce = false
    @State private var movieToDelete: DownloadItem? = nil
    @State private var showDeleteMovieAlert = false
    @State private var showShareToFriendSheet = false
    @State private var directPlaybackMovie: MediaDto? = nil
    @State private var pendingDirectPlayerConfig: PlayerConfig? = nil
    @State private var directPlaybackTitle: String? = nil
    @State private var selectedTrailer: TrailerVideoDto? = nil

    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss

    @State private var dominantBackdropColor: UIColor? = nil
    @State private var dominantPosterColor: UIColor? = nil
    @State private var selectedBackdropIndex: Int = 0
    @State private var backdropTimerProgress: CGFloat = 0.0

    private func currentBackdropUrl(for details: MediaDetailsDto) -> String? {
        let urls = details.displayBackdropUrls
        if !urls.isEmpty && selectedBackdropIndex >= 0 && selectedBackdropIndex < urls.count {
            return urls[selectedBackdropIndex]
        }
        return details.displayBackdropUrl
    }

    @ViewBuilder
    private func backdropContextMenu(for details: MediaDetailsDto) -> some View {
        let activeBackdrop = currentBackdropUrl(for: details)
        let allBackdrops = details.displayBackdropUrls
        let currentIndex = (selectedBackdropIndex >= 0 && selectedBackdropIndex < allBackdrops.count) ? selectedBackdropIndex : 0

        Button {
            Task { await saveImage(from: activeBackdrop, label: "обложка") }
        } label: {
            Label(
                allBackdrops.count > 1 ? "Сохранить текущую обложку (\(currentIndex + 1) из \(allBackdrops.count))" : "Сохранить обложку",
                systemImage: "photo.badge.arrow.down"
            )
        }

        if allBackdrops.count > 1 {
            Menu {
                Button {
                    Task {
                        for (i, urlStr) in allBackdrops.enumerated() {
                            await saveImage(from: urlStr, label: "обложка \(i + 1)")
                        }
                    }
                } label: {
                    Label("Сохранить все (\(allBackdrops.count))", systemImage: "square.and.arrow.down.on.square.fill")
                }

                Divider()

                ForEach(Array(allBackdrops.enumerated()), id: \.offset) { idx, urlStr in
                    Button {
                        Task { await saveImage(from: urlStr, label: "обложка \(idx + 1)") }
                    } label: {
                        if idx == currentIndex {
                            Label("Обложка \(idx + 1) (текущая)", systemImage: "checkmark.circle.fill")
                        } else {
                            Label("Обложка \(idx + 1)", systemImage: "photo")
                        }
                    }
                }
            } label: {
                Label("Выбрать из всех обложек", systemImage: "photo.stack")
            }
        }

        Button {
            Task { await saveImage(from: details.displayPosterUrl, label: "постер") }
        } label: {
            Label("Сохранить постер", systemImage: "photo")
        }

        if details.displayLogoUrl != nil {
            Button {
                Task { await saveImage(from: details.displayLogoUrl, label: "логотип") }
            } label: {
                Label("Сохранить логотип", systemImage: "text.below.photo")
            }
        }

        Divider()

        Button {
            shareImages(posterUrl: details.displayPosterUrl, backdropUrl: activeBackdrop)
        } label: {
            Label("Поделиться", systemImage: "square.and.arrow.up")
        }
    }

    @ViewBuilder
    private func backdropContextMenuPreview(for details: MediaDetailsDto) -> some View {
        let activeBackdrop = currentBackdropUrl(for: details)
        AsyncCachedImage(url: URL(string: activeBackdrop ?? details.displayPosterUrl ?? ""),
                         fallbackUrl: URL(string: details.displayPosterUrl ?? "")) {
            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 300, height: 200)
        } content: { image in
            Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 300, height: 200).clipped()
        } fallback: {
            Rectangle().fill(Color.gray.opacity(0.3)).frame(width: 300, height: 200)
        }
    }

    @AppStorage("hasSeenSourceSelectionTooltip") private var hasSeenSourceSelectionTooltip = false
    @AppStorage("showOriginalTitle") private var showOriginalTitle = true
    @State private var showTooltip = false

    private var detailsBaseBackgroundColor: UIColor {
        UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    }

    private var effectiveBackgroundColor: Color {
        let background = detailsBaseBackgroundColor
        if let dominant = dominantBackdropColor ?? dominantPosterColor {
            return Color(dominant.blended(with: background, fraction: 0.35))
        } else {
            return Color(background)
        }
    }

    nonisolated(unsafe) private static var dominantColorCache: [String: UIColor] = [:]
    nonisolated(unsafe) private static let dominantColorCacheLock = NSLock()

    private func fetchAverageColor(from url: URL?) async -> UIColor? {
        guard let url else { return nil }
        let key = url.absoluteString

        // 1. Проверяем кеш уже вычисленных цветов
        let cachedColor: UIColor? = Self.dominantColorCacheLock.withLock {
            Self.dominantColorCache[key]
        }
        if let cachedColor { return cachedColor }

        // 2. Проверяем наличие UIImage в оперативной памяти (мгновенно, без сети!)
        let effectiveUrl = ImageCache.resolveEffectiveUrl(url)
        if let ramImage = ImageCache.shared.image(forKey: key) ?? effectiveUrl.flatMap({ ImageCache.shared.image(forKey: $0.absoluteString) }) {
            if let avg = ramImage.averageColor {
                Self.dominantColorCacheLock.withLock {
                    Self.dominantColorCache[key] = avg
                }
                return avg
            }
        }

        // 3. Если изображения нет в памяти — загружаем из кеша URLSession со сверхбыстрым даунсемплингом
        return await Task.detached(priority: .userInitiated) {
            do {
                let targetUrl = effectiveUrl ?? url
                var request = URLRequest(url: targetUrl, cachePolicy: .returnCacheDataElseLoad)
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    return nil
                }

                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 32
                ]

                var avg: UIColor? = nil
                if let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let thumbCg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    avg = UIImage(cgImage: thumbCg).averageColor
                } else if let image = UIImage(data: data) {
                    avg = image.averageColor
                }

                if let avg {
                    Self.dominantColorCacheLock.withLock {
                        Self.dominantColorCache[key] = avg
                    }
                }
                return avg
            } catch {
                return nil
            }
        }.value
    }

    private func preloadAllBackdropColors(for details: MediaDetailsDto) {
        Task.detached(priority: .utility) {
            // Даем 1.5 секунды приоритета плавной анимации перехода на экран
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled { return }
            for urlStr in details.displayBackdropUrls {
                if Task.isCancelled { return }
                if let url = URL(string: urlStr) {
                    _ = await self.fetchAverageColor(from: url)
                }
            }
        }
    }

    private func preloadDominantColor(for details: MediaDetailsDto) async {
        async let backdropColor = fetchAverageColor(from: URL(string: details.previewBackdropUrl ?? ""))
        async let posterColor = fetchAverageColor(from: URL(string: details.displayPosterUrl ?? ""))
        
        let (backdrop, poster) = await (backdropColor, posterColor)
        
        if Task.isCancelled { return }
        
        await MainActor.run {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.dominantBackdropColor = backdrop
                self.dominantPosterColor = poster
            }
        }
    }
    
    @State private var isLogoAtTop: Bool = false
    @State private var isSavingImage: Bool = false
    @Namespace private var actorTransitionNamespace
    @Namespace private var crewTransitionNamespace
    
    var body: some View {
        ZStack {
            detailsContent
        }
            .optionalMovieNavigationTransition(
                sourceID: navigationTransitionID,
                in: navigationTransitionNamespace
            )
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea(edges: .top)
            .hideNavigationBarWithRestore()
            .safeAreaInset(edge: .top, spacing: 0) {
                ZStack {
                    if let details = viewModel.details {
                        RemoteLogoView(
                            url: URL(string: details.displayLogoUrl ?? ""),
                            fallbackTitle: details.title ?? details.originalTitle ?? "Без названия",
                            alignment: .center,
                            isTopBar: true
                        )
                        .frame(height: 32)
                        .padding(.horizontal, 68)
                        .opacity(isLogoAtTop ? 1.0 : 0.0)
                        .scaleEffect(isLogoAtTop ? 1.0 : 0.85, anchor: .center)
                        .blur(radius: isLogoAtTop ? 0 : 8)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isLogoAtTop)
                        .allowsHitTesting(false)
                    }
                    
                    HStack {
                        TelegramGlassIconButton(systemName: "chevron.left") {
                            dismiss()
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 0) {
                            // Кнопка «Избранное» (слева, как было изначально)
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.prepare()
                                generator.impactOccurred()
                                favoriteBounce.toggle()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0.5)) {
                                    viewModel.toggleFavorite()
                                }
                            } label: {
                                Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                                    .font(.system(size: 21, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.details == nil)
                            .accessibilityLabel(viewModel.isFavorite ? "Убрать из избранного" : "Добавить в избранное")
                            .frame(width: 44, height: 44)

                            // Кнопка «Поделиться» (справа, растворяется с блюром)
                            Button {
                                let generator = UIImpactFeedbackGenerator(style: .medium)
                                generator.prepare()
                                generator.impactOccurred()
                                showShareToFriendSheet = true
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .blur(radius: isLogoAtTop ? 12 : 0)
                                    .opacity(isLogoAtTop ? 0 : 1)
                                    .scaleEffect(isLogoAtTop ? 0.4 : 1.0)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(viewModel.details == nil || isLogoAtTop)
                            .accessibilityLabel("Поделиться фильмом")
                            .frame(width: isLogoAtTop ? 0 : 44, height: 44)
                            .clipped()
                            .allowsHitTesting(!isLogoAtTop)
                        }
                        .padding(.horizontal, isLogoAtTop ? 0 : 2)
                        .frame(width: isLogoAtTop ? 44 : 92, height: 44)
                        .clipShape(Capsule())
                        .glassEffect(.regular.interactive(), in: .capsule)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isLogoAtTop)
                    }

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                .background(
                    VariableBlurView(tintColor: effectiveBackgroundColor, tintOpacity: 1.0)
                        .padding(.bottom, -60)
                        .ignoresSafeArea(edges: .top)
                        .opacity(isLogoAtTop ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.25), value: isLogoAtTop)
                        .allowsHitTesting(false)
                )
                .opacity(isContentRevealed ? 1.0 : 0.0)
                .animation(.easeOut(duration: 0.28), value: isContentRevealed)
            }
            .task {
                await viewModel.loadDetails(id: movieId, type: mediaType, studio: initialStudio)
            }
            .task(id: viewModel.details?.id) {
                guard let details = viewModel.details else { return }
                selectedBackdropIndex = 0
                ImageCache.prefetch(urls: details.displayBackdropUrls.compactMap { URL(string: $0) })
                preloadAllBackdropColors(for: details)
                await preloadDominantColor(for: details)
            }
            .onChange(of: selectedBackdropIndex) { _, newIndex in
                guard let details = viewModel.details else { return }
                let urls = details.displayBackdropUrls
                guard newIndex >= 0 && newIndex < urls.count else { return }
                Task {
                    if let newColor = await fetchAverageColor(from: URL(string: urls[newIndex])) {
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.6)) {
                                self.dominantBackdropColor = newColor
                            }
                        }
                    }
                }
            }
            .onAppear {
                CloudSyncService.shared.syncAllData()
                if viewModel.details != nil && !isContentRevealed {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        isContentRevealed = true
                    }
                }
                if !hasSeenSourceSelectionTooltip {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        showTooltip = true
                    }
                }
            }
            .onChange(of: viewModel.isLoading) { _, loading in
                if !loading && viewModel.details != nil && !isContentRevealed {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        isContentRevealed = true
                    }
                }
            }
            .onChange(of: showTooltip) { _, newValue in
                if !newValue {
                    hasSeenSourceSelectionTooltip = true
                }
            }
            .sheet(isPresented: $showSourceSheet, onDismiss: {
                sourceFetchTask?.cancel()
                sourceFetchTask = nil
                sourceSheetTitle = ""
                viewModel.resetSourceSheet()
                if pendingPlayerLaunch {
                    pendingPlayerLaunch = false
                    DispatchQueue.main.async {
                        showPlayer = true
                    }
                }
            }) {
                SourceSelectionView(
                    mode: sourceSheetMode,
                    isLoading: viewModel.isFetchingSources || !viewModel.hasFinishedSourceFetch,
                    source1Result: viewModel.sourceResultWrapper?.allohaResult,
                    source2Result: viewModel.sourceResultWrapper?.collapsResult,
                    kpId: viewModel.sourceResultWrapper?.kpId,
                    details: viewModel.details,
                    fallbackTitle: sourceSheetTitle
                ) { translation, season, episode, quality, source, subs, headers in
                    let effectiveWrapper = viewModel.sourceResultWrapper
                    if sourceSheetMode == .play {
                        let effectiveKp = ((effectiveWrapper?.kpId ?? 0) > 0 ? effectiveWrapper?.kpId : nil)
                            ?? viewModel.details?.ids?.kp
                            ?? viewModel.details?.externalIds?.kp
                        let effectiveTmdb = viewModel.details?.externalIds?.tmdb
                            ?? viewModel.details?.ids?.tmdb
                            ?? Int(viewModel.details?.id ?? "")
                        let resolvedKey = (effectiveKp.flatMap { $0 > 0 ? "kp_\($0)" : nil }) ?? (viewModel.details?.id ?? "tmdb_\(effectiveTmdb ?? 0)")

                        playerKpId = effectiveKp
                        playerTmdbId = effectiveTmdb
                        playerMediaKey = resolvedKey
                        playerSeason = season
                        playerEpisode = episode
                        playerQuality = quality
                        
                        if source == .source2, let collaps = effectiveWrapper?.collapsResult {
                            playerStreamSource = .source2
                            playerEpisodeSubtitles = collaps.episodeSubtitles
                            playerSeriesResult = collaps.apiResult
                            playerVoices = collaps.apiResult.allTranslationNames
                            playerSubtitles = subs
                            playerCustomHeaders = headers
                        } else if let alloha = effectiveWrapper?.allohaResult {
                            playerStreamSource = .source1
                            playerEpisodeSubtitles = [:]
                            playerSeriesResult = alloha
                            playerVoices = alloha.allTranslationNames
                            playerSubtitles = []
                            playerCustomHeaders = nil
                        }
                        
                        selectedIframeUrl = translation.iframeUrl.isEmpty ? nil : translation.iframeUrl
                        playerVoiceover = translation.name
                        playerStreamUrl = (translation.streamUrl?.isEmpty == false) ? translation.streamUrl : nil
                        
                        pendingPlayerLaunch = true
                        showSourceSheet = false
                        viewModel.saveAllohaTranslation(translation.name)
                    } else {
                        if let details = viewModel.details {
                            let directUrl = (source == .source2) ? ((translation.streamUrl?.isEmpty == false) ? translation.streamUrl : nil) : nil
                            let headers = (source == .source2) ? CollapsRepository.streamHeaders : nil
                            DownloadManager.shared.startDownload(
                                details: details,
                                season: season,
                                episode: episode,
                                translation: translation,
                                preferredQuality: quality,
                                directStreamUrl: directUrl,
                                customHeaders: headers
                            )
                        }
                        showSourceSheet = false
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .fullScreenCover(isPresented: $showPlayer, onDismiss: {
                showPlayer = false
                AppDelegate.lockToPortrait()
                selectedIframeUrl = nil
                directPlaybackTitle = nil
                playerKpId = nil
                playerTmdbId = nil
                playerMediaKey = nil
                playerSeason = nil
                playerEpisode = nil
                playerVoiceover = nil
                playerStreamUrl = nil
                playerVoices = []
                playerSubtitles = []
                playerQuality = nil
                playerSeriesResult = nil
                playerCustomHeaders = nil
                playerStreamSource = .source1
                playerEpisodeSubtitles = [:]
            }) {
                if let details = viewModel.details {
                    let fallbackTitle = directPlaybackTitle ?? details.title ?? details.originalTitle ?? ""
                    if let iframeUrl = selectedIframeUrl {
                        PlayerView(
                            iframeUrl: iframeUrl,
                            fallbackTitle: fallbackTitle,
                            kpId: playerKpId,
                            season: playerSeason,
                            episode: playerEpisode,
                            selectedVoiceover: playerVoiceover,
                            directStreamUrl: playerStreamUrl,
                            voices: playerVoices,
                            subtitles: playerSubtitles,
                            initialQuality: playerQuality,
                            seriesResult: playerSeriesResult,
                            customHeaders: playerCustomHeaders,
                            mediaKey: playerMediaKey,
                            tmdbId: playerTmdbId,
                            posterUrl: details.displayPosterUrl,
                            backdropUrl: details.displayBackdropUrl ?? details.displayPosterUrl,
                            logoUrl: details.displayLogoUrl,
                            streamSource: playerStreamSource,
                            episodeSubtitles: playerEpisodeSubtitles
                        )
                    } else if let streamUrl = playerStreamUrl {
                        PlayerView(
                            iframeUrl: "",
                            fallbackTitle: fallbackTitle,
                            kpId: playerKpId,
                            season: playerSeason,
                            episode: playerEpisode,
                            selectedVoiceover: playerVoiceover,
                            directStreamUrl: streamUrl,
                            voices: playerVoices,
                            subtitles: playerSubtitles,
                            initialQuality: playerQuality,
                            seriesResult: playerSeriesResult,
                            customHeaders: playerCustomHeaders,
                            mediaKey: playerMediaKey,
                            tmdbId: playerTmdbId,
                            posterUrl: details.displayPosterUrl,
                            backdropUrl: details.displayBackdropUrl ?? details.displayPosterUrl,
                            logoUrl: details.displayLogoUrl,
                            streamSource: playerStreamSource,
                            episodeSubtitles: playerEpisodeSubtitles
                        )
                    } else {
                        ZStack {
                            Color.black.ignoresSafeArea()
                            VStack(spacing: 20) {
                                Text("Видео не найдено")
                                    .foregroundColor(.white)
                                    .font(.headline)
                                Button("Закрыть") {
                                    showPlayer = false
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
            }
        .alert("Удалить фильм?", isPresented: $showDeleteMovieAlert) {
            Button("Отмена", role: .cancel) {}
            Button("Удалить", role: .destructive) {
                if let movie = movieToDelete {
                    DownloadManager.shared.deleteDownload(id: movie.id)
                }
            }
        } message: {
            Text("Вы действительно хотите удалить этот фильм из памяти устройства?")
        }
        .sheet(isPresented: $showShareToFriendSheet) {
            if let details = viewModel.details {
                ShareToFriendSheet(movie: details)
            }
        }
        .sheet(item: $selectedTrailer) { trailer in
            TrailerPlayerSheetView(trailer: trailer)
        }
        .sheet(item: $directPlaybackMovie, onDismiss: {
            if let pending = pendingDirectPlayerConfig {
                pendingDirectPlayerConfig = nil
                DispatchQueue.main.async {
                    directPlaybackTitle = pending.title
                    selectedIframeUrl = pending.iframeUrl
                    playerKpId = pending.kpId
                    playerTmdbId = pending.tmdbId
                    playerMediaKey = pending.mediaKey
                    playerSeason = pending.season
                    playerEpisode = pending.episode
                    playerVoiceover = pending.voiceover
                    playerStreamUrl = pending.streamUrl
                    playerVoices = pending.voices
                    playerSubtitles = pending.subtitles
                    playerQuality = pending.quality
                    playerSeriesResult = pending.seriesResult
                    playerCustomHeaders = pending.customHeaders
                    playerStreamSource = pending.source
                    playerEpisodeSubtitles = pending.episodeSubtitles
                    showPlayer = true
                }
            }
        }) { movie in
            HomeDirectPlayWrapper(
                movieId: movie.id,
                fallbackTitle: movie.title ?? movie.name ?? movie.originalTitle ?? "",
                initialKpId: movie.externalIds?.kp
            ) { config in
                pendingDirectPlayerConfig = config
                directPlaybackMovie = nil
            }
        }



        .preferredColorScheme(.dark)
    }



    private func handlePlayAction(details: MediaDetailsDto) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()

        let kpId = details.ids?.kp ?? details.externalIds?.kp ?? 0
        let tmdbId = details.externalIds?.tmdb ?? details.ids?.tmdb ?? Int(details.id ?? "")
        let imdbId = details.externalIds?.imdb ?? details.ids?.imdb
        let title = details.title ?? details.originalTitle ?? ""
        guard kpId > 0 || (tmdbId ?? 0) > 0 || imdbId != nil || !title.isEmpty else { return }

        sourceSheetSourceID = "playBtn"
        sourceSheetTitle = title
        sourceSheetMode = .play
        viewModel.prepareSourceSheet(kpId: kpId, tmdbId: tmdbId)
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(
                kpId: kpId,
                tmdbId: tmdbId,
                imdbId: imdbId,
                title: sourceSheetTitle,
                originalTitle: details.originalTitle,
                year: details.year
            )
        }
    }

    private func handleEpisodeSelection(details: MediaDetailsDto, season: Int, episode: Int) {
        let kpId = details.ids?.kp ?? details.externalIds?.kp ?? 0
        let tmdbId = details.externalIds?.tmdb ?? details.ids?.tmdb ?? Int(details.id ?? "")
        let imdbId = details.externalIds?.imdb ?? details.ids?.imdb
        let title = details.title ?? details.originalTitle ?? ""
        guard kpId > 0 || (tmdbId ?? 0) > 0 || imdbId != nil || !title.isEmpty else { return }

        PlaybackProgressStore.shared.saveLastPlayed(
            kpId: kpId > 0 ? kpId : (tmdbId ?? 0),
            season: season,
            episode: episode
        )

        sourceSheetSourceID = "playBtn"
        sourceSheetTitle = title
        sourceSheetMode = .play
        viewModel.prepareSourceSheet(kpId: kpId, tmdbId: tmdbId)
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(
                kpId: kpId,
                tmdbId: tmdbId,
                imdbId: imdbId,
                title: sourceSheetTitle,
                originalTitle: details.originalTitle,
                year: details.year
            )
        }
    }

    @ViewBuilder
    private func playAndDownloadRow(for details: MediaDetailsDto) -> some View {
        if details.isUnreleased {
            unreleasedButton(for: details)
        } else {
            HStack(spacing: 8) {
                playButton(for: details)
                    .tooltip(text: "Нажмите для выбора перевода", isVisible: $showTooltip, isTailTop: false)
                downloadButton(for: details)
            }
        }
    }

    private func unreleasedButton(for details: MediaDetailsDto) -> some View {
        let labelText: String = {
            if let dateStr = details.formattedReleaseDate {
                return "Премьера: \(dateStr)"
            }
            return "Скоро в кино"
        }()
        
        return HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 17, weight: .semibold))
            Text(labelText)
                .font(.system(size: 16, weight: .bold))
        }
        .foregroundStyle(Color.primary.opacity(0.85))
        .padding(.horizontal, 22)
        .frame(height: 50)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
    }


    private var buttonAmbientTintColor: Color {
        if let dominant = dominantBackdropColor ?? dominantPosterColor {
            return Color(uiColor: dominant)
        } else {
            return effectiveBackgroundColor
        }
    }

    private func playButton(for details: MediaDetailsDto) -> some View {
        Button {
            handlePlayAction(details: details)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.system(size: 18, weight: .black))
                Text("Смотреть")
                    .font(.system(size: 19, weight: .heavy))
            }
            .foregroundStyle(Color.black)
            .padding(.horizontal, 26)
            .frame(height: 50)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.94))
            )
            .glassEffect(.regular.interactive(), in: .capsule)
            .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
        }
        .buttonStyle(.glassPress)
    }

    @ViewBuilder
    private func downloadButton(for details: MediaDetailsDto) -> some View {
        let kpId = details.ids?.kp ?? 0
        let item = DownloadManager.shared.getDownloadItem(kpId: kpId, season: nil, episode: nil)
        
        Button {
            handleDownloadAction(details: details, item: item)
        } label: {
            Group {
                if let item = item, item.status == .downloading {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                            .frame(width: 20, height: 20)
                        Circle()
                            .trim(from: 0.0, to: item.progress)
                            .stroke(Color.slooshAccent, lineWidth: 2)
                            .frame(width: 20, height: 20)
                            .rotationEffect(Angle(degrees: -90))
                        Image(systemName: "square.fill")
                            .font(.system(size: 6))
                    }
                } else if let item = item, item.status == .pending {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 22))
                        .foregroundColor(.primary)
                }
            }
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
            .glassEffect(.regular.interactive(), in: .circle)
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.glassPress)
    }

    private func handleDownloadAction(details: MediaDetailsDto, item: DownloadItem?) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        sourceSheetSourceID = "downloadBtn"
        
        if let item = item {
            switch item.status {
            case .downloading, .pending:
                DownloadManager.shared.pauseDownload(id: item.id)
            case .paused:
                DownloadManager.shared.resumeDownload(id: item.id)
            default:
                startDownloadWithPreferredTranslation(details: details, season: nil, episode: nil)
            }
        } else {
            startDownloadWithPreferredTranslation(details: details, season: nil, episode: nil)
        }
    }

    private func startDownloadWithPreferredTranslation(details: MediaDetailsDto, season: Int?, episode: Int?) {
        let kpId = details.ids?.kp ?? details.externalIds?.kp ?? 0
        let tmdbId = details.externalIds?.tmdb ?? details.ids?.tmdb ?? Int(details.id ?? "")
        let imdbId = details.externalIds?.imdb ?? details.ids?.imdb
        let title = details.title ?? details.originalTitle ?? ""
        guard kpId > 0 || (tmdbId ?? 0) > 0 || imdbId != nil || !title.isEmpty else { return }
        
        sourceSheetTitle = title
        sourceSheetMode = .download
        viewModel.prepareSourceSheet(kpId: kpId, tmdbId: tmdbId)
        showSourceSheet = true

        sourceFetchTask?.cancel()
        sourceFetchTask = Task {
            await viewModel.fetchSources(
                kpId: kpId,
                tmdbId: tmdbId,
                imdbId: imdbId,
                title: sourceSheetTitle,
                originalTitle: details.originalTitle,
                year: details.year
            )
        }
    }

    private var detailsContent: some View {
        Group {
            if verticalSizeClass == .compact {
                landscapeDetailsContent
            } else {
                portraitDetailsContent
            }
        }
    }

    // MARK: - Image Saving & Sharing

    @MainActor
    private func saveImage(from urlString: String?, label: String) async {
        guard let urlString, let url = URL(string: urlString) else { return }
        isSavingImage = true
        defer { isSavingImage = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else {
                ToastManager.shared.show(title: "Не удалось загрузить \(label)", icon: "xmark.circle")
                return
            }
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                ToastManager.shared.show(title: "Нет доступа к Фото", icon: "lock")
                return
            }
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            ToastManager.shared.show(title: "Сохранено в Фото", icon: "checkmark.circle.fill")
        } catch {
            ToastManager.shared.show(title: "Ошибка: \(label) не сохранён", icon: "xmark.circle")
        }
    }

    private func shareImages(posterUrl: String?, backdropUrl: String?) {
        var items: [Any] = []
        if let str = backdropUrl, let url = URL(string: str),
           let data = URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data,
           let img = UIImage(data: data) {
            items.append(img)
        } else if let str = posterUrl, let url = URL(string: str),
           let data = URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data,
           let img = UIImage(data: data) {
            items.append(img)
        }
        if items.isEmpty {
            if let str = backdropUrl ?? posterUrl { items.append(str) }
        }
        guard !items.isEmpty else { return }

        let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first,
           let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            var topVC = rootVC
            while let presented = topVC.presentedViewController { topVC = presented }
            av.popoverPresentationController?.sourceView = topVC.view
            topVC.present(av, animated: true)
        }
    }

    private var portraitDetailsContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if viewModel.isLoading {
                    DetailsSkeletonView(backgroundColor: effectiveBackgroundColor)
                        .transition(.opacity)
                } else if let details = viewModel.details {
                    // Stretchy Backdrop
                    let baseHeight: CGFloat = 365
                    
                    GeometryReader { geometry in
                        let minY = geometry.frame(in: .global).minY
                        let isScrollingDown = minY > 0
                        let height = isScrollingDown ? baseHeight + minY : baseHeight
                        let offset = isScrollingDown ? -minY : 0
                        let isHeaderVisible = minY > -250

                        BackdropCarouselView(
                            urls: details.displayBackdropUrls,
                            fallbackUrl: URL(string: details.displayPosterUrl ?? ""),
                            width: geometry.size.width,
                            height: height,
                            selectedIndex: $selectedBackdropIndex,
                            timerProgress: $backdropTimerProgress,
                            isHeaderVisible: isHeaderVisible
                        )
                        .offset(y: offset)
                    }
                    .frame(height: baseHeight)
                    .contextMenu {
                        backdropContextMenu(for: details)
                    } preview: {
                        backdropContextMenuPreview(for: details)
                    }

                    VStack(alignment: .center, spacing: 12) {
                        BackdropPageIndicator(
                            count: details.displayBackdropUrls.count,
                            selectedIndex: $selectedBackdropIndex,
                            progress: backdropTimerProgress
                        )
                        .opacity(isContentRevealed ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.25), value: isContentRevealed)

                        RemoteLogoView(
                            url: URL(string: details.displayLogoUrl ?? ""),
                            fallbackTitle: details.title ?? details.originalTitle ?? "Без названия",
                            alignment: .center
                        )
                        .opacity(isContentRevealed ? (isLogoAtTop ? 0.0 : 1.0) : 0.0)
                        .scaleEffect(isContentRevealed ? (isLogoAtTop ? 0.85 : 1.0) : 0.94, anchor: .center)
                        .blur(radius: isLogoAtTop ? 8 : (isContentRevealed ? 0 : 4))
                        .animation(.spring(response: 0.4, dampingFraction: 0.84), value: isContentRevealed)
                        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isLogoAtTop)
                        .padding(.bottom, 8)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .onChange(of: geo.frame(in: .global).midY) { _, midY in
                                        guard midY > 0 else { return }
                                        let isAtTop = midY < 80
                                        if isLogoAtTop != isAtTop {
                                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                isLogoAtTop = isAtTop
                                            }
                                        }
                                    }
                                    .onAppear {
                                        let midY = geo.frame(in: .global).midY
                                        if midY > 0 {
                                            isLogoAtTop = midY < 80
                                        }
                                    }
                            }
                        )

                        if showOriginalTitle, let originalTitle = details.originalTitle, !originalTitle.isEmpty, originalTitle != details.title {
                            Text(originalTitle)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                                .padding(.top, -8)
                                .opacity(isContentRevealed ? 1.0 : 0.0)
                                .offset(y: isContentRevealed ? 0 : 6)
                                .animation(.spring(response: 0.42, dampingFraction: 0.85).delay(0.03), value: isContentRevealed)
                        }

                        DetailsPrimaryMetadataRow(details: details, alignment: .center)
                            .opacity(isContentRevealed ? 1.0 : 0.0)
                            .offset(y: isContentRevealed ? 0 : 8)
                            .animation(.spring(response: 0.42, dampingFraction: 0.85).delay(0.06), value: isContentRevealed)

                        playAndDownloadRow(for: details)
                            .padding(.top, 8)
                            .padding(.bottom, -4)
                            .opacity(isContentRevealed ? 1.0 : 0.0)
                            .scaleEffect(isContentRevealed ? 1.0 : 0.94, anchor: .center)
                            .offset(y: isContentRevealed ? 0 : 10)
                            .animation(.spring(response: 0.42, dampingFraction: 0.85).delay(0.09), value: isContentRevealed)

                        DetailsInfoSection(details: details, backgroundColor: effectiveBackgroundColor, studio: initialStudio)
                            .padding(.top, 20)
                            .padding(.horizontal)
                            .opacity(isContentRevealed ? 1.0 : 0.0)
                            .offset(y: isContentRevealed ? 0 : 12)
                            .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.12), value: isContentRevealed)

                        if let cast = details.cast, !cast.isEmpty {
                            ActorsSection(cast: cast, namespace: actorTransitionNamespace)
                                .padding(.top, 16)
                                .opacity(isContentRevealed ? 1.0 : 0.0)
                                .offset(y: isContentRevealed ? 0 : 14)
                                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.15), value: isContentRevealed)
                        }

                        if let crew = details.crew, !crew.isEmpty {
                            CrewSection(crew: crew, namespace: crewTransitionNamespace)
                                .padding(.top, 16)
                                .opacity(isContentRevealed ? 1.0 : 0.0)
                                .offset(y: isContentRevealed ? 0 : 14)
                                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.18), value: isContentRevealed)
                        }

                        if let trailers = details.trailers, !trailers.isEmpty {
                            TrailersSection(trailers: trailers) { trailer in
                                selectedTrailer = trailer
                            }
                            .padding(.top, 16)
                            .opacity(isContentRevealed ? 1.0 : 0.0)
                            .offset(y: isContentRevealed ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.20), value: isContentRevealed)
                        }

                        if details.type == "tv" {
                            InlineEpisodesSection(viewModel: viewModel, details: details) { season, episode in
                                handleEpisodeSelection(details: details, season: season, episode: episode)
                            }
                            .padding(.top, 16)
                            .opacity(isContentRevealed ? 1.0 : 0.0)
                            .offset(y: isContentRevealed ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.22), value: isContentRevealed)
                        }

                        if let collection = viewModel.movieCollection ?? details.collection {
                            FranchiseCollectionSection(collection: collection, onDirectPlay: { movie in
                                directPlaybackMovie = movie
                            })
                            .padding(.top, 16)
                            .opacity(isContentRevealed ? 1.0 : 0.0)
                            .offset(y: isContentRevealed ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.24), value: isContentRevealed)
                        }

                        if let similar = details.similar, !similar.isEmpty {
                            SimilarMediaSection(
                                title: details.type == "tv" ? "Похожие сериалы" : "Похожие фильмы",
                                items: similar,
                                onDirectPlay: { movie in
                                    directPlaybackMovie = movie
                                }
                            )
                            .padding(.top, 16)
                            .opacity(isContentRevealed ? 1.0 : 0.0)
                            .offset(y: isContentRevealed ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.26), value: isContentRevealed)
                        }

                        if let relatedStudio = viewModel.relatedStudio, let items = relatedStudio.items, !items.isEmpty {
                            RelatedStudioSection(response: relatedStudio, onDirectPlay: { movie in
                                directPlaybackMovie = movie
                            })
                            .padding(.top, 16)
                            .opacity(isContentRevealed ? 1.0 : 0.0)
                            .offset(y: isContentRevealed ? 0 : 14)
                            .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.28), value: isContentRevealed)
                        }
                    }
                    .offset(y: -25)
                    .padding(.bottom, 28)
                    .transition(.opacity)
                } else {
                    Text("Не удалось загрузить данные.")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 100)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: viewModel.isLoading)
        }
        .scrollIndicators(.hidden)
        .background {
            effectiveBackgroundColor
                .animation(.easeInOut(duration: 0.4), value: effectiveBackgroundColor)
                .ignoresSafeArea()
        }
        .refreshable {
            await viewModel.loadDetails(id: movieId, type: mediaType, force: true, studio: initialStudio)
        }
    }

    private var landscapeDetailsContent: some View {
        GeometryReader { outerGeometry in
            ScrollView {
                VStack(spacing: 0) {
                    if viewModel.isLoading {
                        DetailsSkeletonView(backgroundColor: effectiveBackgroundColor)
                            .transition(.opacity)
                    } else if let details = viewModel.details {
                        let baseHeight: CGFloat = 280
                        
                        GeometryReader { geometry in
                            let minY = geometry.frame(in: .global).minY
                            let isScrollingDown = minY > 0
                            let height = isScrollingDown ? baseHeight + minY : baseHeight
                            let offset = isScrollingDown ? -minY : 0
                            let isHeaderVisible = minY > -200

                            BackdropCarouselView(
                                urls: details.displayBackdropUrls,
                                fallbackUrl: URL(string: details.displayPosterUrl ?? ""),
                                width: geometry.size.width,
                                height: height,
                                selectedIndex: $selectedBackdropIndex,
                                timerProgress: $backdropTimerProgress,
                                isHeaderVisible: isHeaderVisible
                            )
                            .offset(y: offset)
                        }
                        .frame(height: baseHeight)
                        .contextMenu {
                            backdropContextMenu(for: details)
                        } preview: {
                            backdropContextMenuPreview(for: details)
                        }

                        VStack(spacing: 0) {
                            VStack(alignment: .center, spacing: 12) {
                                BackdropPageIndicator(
                                    count: details.displayBackdropUrls.count,
                                    selectedIndex: $selectedBackdropIndex,
                                    progress: backdropTimerProgress
                                )
                                .opacity(isContentRevealed ? 1.0 : 0.0)
                                .animation(.easeOut(duration: 0.25), value: isContentRevealed)

                                RemoteLogoView(
                                    url: URL(string: details.displayLogoUrl ?? ""),
                                    fallbackTitle: details.title ?? details.originalTitle ?? "Без названия",
                                    alignment: .center
                                )
                                .opacity(isContentRevealed ? (isLogoAtTop ? 0.0 : 1.0) : 0.0)
                                .scaleEffect(isContentRevealed ? (isLogoAtTop ? 0.85 : 1.0) : 0.94, anchor: .center)
                                .blur(radius: isLogoAtTop ? 8 : (isContentRevealed ? 0 : 4))
                                .animation(.spring(response: 0.4, dampingFraction: 0.84), value: isContentRevealed)
                                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isLogoAtTop)
                                .padding(.bottom, 8)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .onChange(of: geo.frame(in: .global).midY) { _, midY in
                                                guard midY > 0 else { return }
                                                let isAtTop = midY < 80
                                                if isLogoAtTop != isAtTop {
                                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                                        isLogoAtTop = isAtTop
                                                    }
                                                }
                                            }
                                            .onAppear {
                                                let midY = geo.frame(in: .global).midY
                                                if midY > 0 {
                                                    isLogoAtTop = midY < 80
                                                }
                                            }
                                    }
                                )

                                if showOriginalTitle, let originalTitle = details.originalTitle, !originalTitle.isEmpty, originalTitle != details.title {
                                    Text(originalTitle)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                        .padding(.top, -8)
                                        .opacity(isContentRevealed ? 1.0 : 0.0)
                                        .offset(y: isContentRevealed ? 0 : 6)
                                        .animation(.spring(response: 0.42, dampingFraction: 0.85).delay(0.03), value: isContentRevealed)
                                }

                                DetailsPrimaryMetadataRow(details: details, alignment: .center)
                                    .opacity(isContentRevealed ? 1.0 : 0.0)
                                    .offset(y: isContentRevealed ? 0 : 8)
                                    .animation(.spring(response: 0.42, dampingFraction: 0.85).delay(0.06), value: isContentRevealed)

                                playAndDownloadRow(for: details)
                                    .padding(.top, 8)
                                    .padding(.bottom, -4)
                                    .opacity(isContentRevealed ? 1.0 : 0.0)
                                    .scaleEffect(isContentRevealed ? 1.0 : 0.94, anchor: .center)
                                    .offset(y: isContentRevealed ? 0 : 10)
                                    .animation(.spring(response: 0.42, dampingFraction: 0.85).delay(0.09), value: isContentRevealed)

                                DetailsInfoSection(details: details, backgroundColor: effectiveBackgroundColor, studio: initialStudio)
                                    .padding(.top, 20)
                                    .padding(.horizontal)
                                    .opacity(isContentRevealed ? 1.0 : 0.0)
                                    .offset(y: isContentRevealed ? 0 : 12)
                                    .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.12), value: isContentRevealed)
                            }
                            .frame(maxWidth: 550)
                            .frame(maxWidth: .infinity, alignment: .center)

                            if let cast = details.cast, !cast.isEmpty {
                                ActorsSection(cast: cast, namespace: actorTransitionNamespace)
                                    .padding(.top, 16)
                                    .opacity(isContentRevealed ? 1.0 : 0.0)
                                    .offset(y: isContentRevealed ? 0 : 14)
                                    .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.15), value: isContentRevealed)
                            }

                            if let crew = details.crew, !crew.isEmpty {
                                CrewSection(crew: crew, namespace: crewTransitionNamespace)
                                    .padding(.top, 16)
                                    .opacity(isContentRevealed ? 1.0 : 0.0)
                                    .offset(y: isContentRevealed ? 0 : 14)
                                    .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.18), value: isContentRevealed)
                            }

                            if let trailers = details.trailers, !trailers.isEmpty {
                                TrailersSection(trailers: trailers) { trailer in
                                    selectedTrailer = trailer
                                }
                                .padding(.top, 16)
                                .opacity(isContentRevealed ? 1.0 : 0.0)
                                .offset(y: isContentRevealed ? 0 : 14)
                                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.20), value: isContentRevealed)
                            }

                            if details.type == "tv" {
                                let paddingVal = max(16, (outerGeometry.size.width - 550) / 2 + 16)
                                InlineEpisodesSection(
                                    viewModel: viewModel,
                                    details: details,
                                    horizontalPadding: paddingVal
                                ) { season, episode in
                                    handleEpisodeSelection(details: details, season: season, episode: episode)
                                }
                                .padding(.top, 16)
                                .opacity(isContentRevealed ? 1.0 : 0.0)
                                .offset(y: isContentRevealed ? 0 : 14)
                                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.22), value: isContentRevealed)
                            }

                            if let collection = viewModel.movieCollection ?? details.collection {
                                FranchiseCollectionSection(collection: collection, onDirectPlay: { movie in
                                    directPlaybackMovie = movie
                                })
                                .padding(.top, 16)
                                .opacity(isContentRevealed ? 1.0 : 0.0)
                                .offset(y: isContentRevealed ? 0 : 14)
                                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.24), value: isContentRevealed)
                            }

                            if let similar = details.similar, !similar.isEmpty {
                                SimilarMediaSection(
                                    title: details.type == "tv" ? "Похожие сериалы" : "Похожие фильмы",
                                    items: similar,
                                    onDirectPlay: { movie in
                                        directPlaybackMovie = movie
                                    }
                                )
                                .padding(.top, 16)
                                .opacity(isContentRevealed ? 1.0 : 0.0)
                                .offset(y: isContentRevealed ? 0 : 14)
                                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.26), value: isContentRevealed)
                            }

                            if let relatedStudio = viewModel.relatedStudio, let items = relatedStudio.items, !items.isEmpty {
                                RelatedStudioSection(response: relatedStudio, onDirectPlay: { movie in
                                    directPlaybackMovie = movie
                                })
                                .padding(.top, 16)
                                .opacity(isContentRevealed ? 1.0 : 0.0)
                                .offset(y: isContentRevealed ? 0 : 14)
                                .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(0.28), value: isContentRevealed)
                            }
                        }
                        .offset(y: -60)
                        .padding(.bottom, 28)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .background {
                effectiveBackgroundColor
                    .animation(.easeInOut(duration: 0.4), value: effectiveBackgroundColor)
                    .ignoresSafeArea()
            }
            .refreshable {
                await viewModel.loadDetails(id: movieId, type: mediaType, force: true, studio: initialStudio)
            }
        }.ignoresSafeArea()
    }
}

private struct OptionalMovieNavigationTransitionModifier: ViewModifier {
    let sourceID: String?
    let namespace: Namespace.ID?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let sourceID, let namespace {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content
        }
    }
}

private extension View {
    func optionalMovieNavigationTransition(sourceID: String?, in namespace: Namespace.ID?) -> some View {
        modifier(OptionalMovieNavigationTransitionModifier(sourceID: sourceID, namespace: namespace))
    }
}

private struct DetailsSkeletonView: View {
    let backgroundColor: Color
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    var body: some View {
        let baseHeight: CGFloat = verticalSizeClass == .compact ? 280 : 365
        
        VStack(spacing: 0) {
            // Backdrop
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: baseHeight)
                .shimmer()
                .mask(BackdropFadeMask())
            
            VStack(alignment: .center, spacing: 12) {
                // Logo placeholder
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 220, height: 38)
                    .padding(.bottom, 8)
                    .shimmer()
                
                // Metadata row placeholder
                HStack(spacing: 16) {
                    ForEach(0..<4) { _ in
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 40, height: 16)
                            .cornerRadius(4)
                    }
                }
                .shimmer()
                .padding(.bottom, 4)
                
                // Play Button placeholder
                Capsule()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 180, height: 50)
                    .shimmer()
                    .padding(.top, 8)
                    .padding(.bottom, -4)
                
                // Info Section placeholder
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 80, height: 20)
                            .cornerRadius(4)
                        
                        HStack(spacing: 8) {
                            ForEach(0..<3) { i in
                                Capsule()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: CGFloat(60 + i * 20), height: 32)
                            }
                        }
                    }
                    .shimmer()
                    
                    VStack(alignment: .leading, spacing: 10) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 20)
                            .cornerRadius(4)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)
                                .cornerRadius(4)
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)
                                .cornerRadius(4)
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 16)
                                .cornerRadius(4)
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 200, height: 16)
                                .cornerRadius(4)
                        }
                    }
                    .shimmer()
                }
                .padding(.top, 20)
                .padding(.horizontal)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: verticalSizeClass == .compact ? 550 : .infinity)
            .frame(maxWidth: .infinity, alignment: .center)
            .offset(y: verticalSizeClass == .compact ? -50 : -25)
        }
    }
}

private struct DetailsPrimaryMetadataRow: View {
    let details: MediaDetailsDto
    var alignment: HorizontalAlignment = .center

    var body: some View {
        HStack(spacing: 8) {
            if let rating = details.ratings?.kp ?? details.ratings?.imdb ?? details.ratings?.tmdb, rating > 0 {
                Text(String(format: "%.1f", rating))
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.rating(rating))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            if let ageRating = details.ageRating, !ageRating.isEmpty {
                Text(ageRating)
                    .fontWeight(.bold)
                    .foregroundColor(Color.ageRating(ageRating))
            }

            if let year = details.year, year > 0 {
                Text(String(year))
            }

            if let country = details.countries?.first, !country.isEmpty {
                Text(CountryLocalizer.format(country))
            }

            if let duration = details.duration, duration > 0 {
                Text("\(duration) мин")
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.secondary)
        .multilineTextAlignment(alignment == .leading ? .leading : .center)
        .padding(.horizontal, alignment == .center ? 16 : 0)
        .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
    }
}

private struct DetailsInfoSection: View {
    let details: MediaDetailsDto
    let backgroundColor: Color
    var studio: StudioBrand? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isDescriptionExpanded = false
    @State private var canExpand = false
    @State private var fullHeight: CGFloat = 0
    @State private var visibleHeight: CGFloat = 0

    private var genres: [String] {
        details.genres?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !genres.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Жанры")
                        .font(.system(size: 18, weight: .bold))

                    FlowLayout(spacing: 8) {
                        ForEach(genres, id: \.self) { genre in
                            NavigationLink(destination: GenreCatalogView(genre: genre, mediaType: details.type)) {
                                HStack(spacing: 6) {
                                    Text(genre)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .glassEffect(.regular.interactive(), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            let companies = details.productionCompanies ?? []
            let networks = details.networks ?? []
            if !companies.isEmpty || !networks.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(details.type == "tv" && !networks.isEmpty ? "Платформа" : "Студия")
                        .font(.system(size: 18, weight: .bold))

                    FlowLayout(spacing: 8) {
                        if !companies.isEmpty {
                            ForEach(companies) { company in
                                let brand = StudioBrand.find(by: company.name)
                                NavigationLink(destination: StudioCatalogView(studioId: brand?.id ?? String(company.id), studioName: company.name)) {
                                    Text(company.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .glassEffect(.regular.interactive(), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !networks.isEmpty {
                            ForEach(networks) { net in
                                let brand = StudioBrand.find(by: net.name)
                                NavigationLink(destination: StudioCatalogView(studioId: brand?.id ?? String(net.id), studioName: net.name)) {
                                    Text(net.name)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .glassEffect(.regular.interactive(), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else if let brand = details.identifiedStudio ?? studio {
                VStack(alignment: .leading, spacing: 10) {
                    Text(brand.isNetwork ? "Платформа" : "Студия")
                        .font(.system(size: 18, weight: .bold))

                    FlowLayout(spacing: 8) {
                        NavigationLink(destination: StudioCatalogView(studioId: brand.id, studioName: brand.name)) {
                            Text(brand.name)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            let budget = details.formattedBudget
            let revenue = details.formattedRevenue
            if budget != nil || revenue != nil {
                VStack(alignment: .leading, spacing: 10) {
                    Text(budget != nil && revenue != nil ? "Бюджет и сборы" : (budget != nil ? "Бюджет" : "Сборы"))
                        .font(.system(size: 18, weight: .bold))

                    HStack(spacing: 8) {
                        if let b = budget {
                            HStack(spacing: 4) {
                                Text("Бюджет:")
                                    .foregroundColor(.secondary)
                                Text(b)
                                    .fontWeight(.semibold)
                            }
                        }
                        if budget != nil && revenue != nil {
                            Text("•")
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        if let r = revenue {
                            HStack(spacing: 4) {
                                Text("Сборы:")
                                    .foregroundColor(.secondary)
                                Text(r)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .font(.system(size: 14))
                }
            }

            if let description = details.description, !description.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Описание")
                        .font(.system(size: 18, weight: .bold))

                    ZStack(alignment: .bottomLeading) {
                        Text(description)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(.primary.opacity(0.85))
                            .lineSpacing(4)
                            .lineLimit(isDescriptionExpanded ? nil : 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            visibleHeight = geo.size.height
                                            checkTruncation()
                                        }
                                        .onChange(of: geo.size.height) { _, newHeight in
                                            visibleHeight = newHeight
                                            checkTruncation()
                                        }
                                }
                            )
                            .mask(
                                Group {
                                    if canExpand && !isDescriptionExpanded {
                                        LinearGradient(
                                            gradient: Gradient(stops: [
                                                .init(color: .black, location: 0.0),
                                                .init(color: .black, location: 0.4),
                                                .init(color: .clear, location: 1.0)
                                            ]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    } else {
                                        Color.black
                                    }
                                }
                            )
                    }
                    .background(
                        Text(description)
                            .font(.system(size: 15, weight: .regular))
                            .lineSpacing(4)
                            .lineLimit(nil)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .opacity(0)
                            .allowsHitTesting(false)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            fullHeight = geo.size.height
                                            checkTruncation()
                                        }
                                        .onChange(of: geo.size.height) { _, newHeight in
                                            fullHeight = newHeight
                                            checkTruncation()
                                        }
                                }
                            )
                    )
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isDescriptionExpanded)

                    if canExpand {
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                                isDescriptionExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 6) {
                                Text(isDescriptionExpanded ? "Свернуть" : "Читать далее")
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 11, weight: .heavy))
                                    .rotationEffect(.degrees(isDescriptionExpanded ? 180 : 0))
                            }
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, isDescriptionExpanded ? 12 : -28)
                        .zIndex(1)
                    }
                }
                .onChange(of: details.description) { _, _ in
                    isDescriptionExpanded = false
                    canExpand = false
                }
            }
        }
    }

    private func checkTruncation() {
        if !isDescriptionExpanded {
            canExpand = fullHeight > visibleHeight + 2
        }
    }
}

struct EpisodeDetailsSheetItem: Identifiable {
    let id = UUID()
    let movieId: String
    let season: Int
    let episode: Int
    let meta: TvEpisodeDetailsDto?
    let seasonEpisode: TvSeasonEpisodeDto?
    let fallbackTitle: String
    let isAvailable: Bool

    init(
        movieId: String,
        season: Int,
        episode: Int,
        meta: TvEpisodeDetailsDto? = nil,
        seasonEpisode: TvSeasonEpisodeDto? = nil,
        fallbackTitle: String = "Серия",
        isAvailable: Bool = true
    ) {
        self.movieId = movieId
        self.season = season
        self.episode = episode
        self.meta = meta
        self.seasonEpisode = seasonEpisode
        self.fallbackTitle = fallbackTitle
        self.isAvailable = isAvailable
    }
}

struct EpisodeDetailsSheet: View {
    let item: EpisodeDetailsSheetItem
    var details: MediaDetailsDto? = nil
    var viewModel: DetailsViewModel? = nil
    let onPlay: () -> Void
    let onWatchedToggle: (Bool) -> Void
    
    @State private var isWatched: Bool = false
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Still Image (Edge-to-edge)
                    let previewUrl: URL? = {
                        if let still = item.seasonEpisode?.stillPath ?? item.meta?.stillPath, !still.isEmpty {
                            if still.hasPrefix("http") {
                                return URL(string: still)
                            } else {
                                return URL(string: "\(MoviesApi.activeImagesBaseURL)/api/v1/images/tmdb/w500\(still)")
                            }
                        }
                        if let backdrop = details?.previewBackdropUrl ?? details?.displayBackdropUrl ?? details?.backdrop, !backdrop.isEmpty {
                            if backdrop.hasPrefix("http") {
                                return URL(string: backdrop)
                            } else {
                                return URL(string: "\(MoviesApi.activeImagesBaseURL)/api/v1/images/tmdb/w500\(backdrop)")
                            }
                        }
                        return nil
                    }()
                    
                    AsyncCachedImage(url: previewUrl) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.15))
                            .aspectRatio(16/9, contentMode: .fill)
                            .shimmer()
                    } content: { image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } fallback: {
                        ZStack {
                            LinearGradient(
                                colors: [Color(white: 0.16), Color(white: 0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: item.isAvailable ? "play.circle.fill" : "calendar.badge.clock")
                                .font(.system(size: 36))
                                .foregroundColor(.white.opacity(0.35))
                        }
                        .aspectRatio(16/9, contentMode: .fill)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipped()
                    
                    // Content
                    VStack(alignment: .leading, spacing: 14) {
                        // Title
                        let rawTitle = item.seasonEpisode?.name ?? item.meta?.name ?? (item.episode == 0 ? "Пилотная серия" : item.fallbackTitle)
                        let title: String = {
                            if item.episode == 0 {
                                return rawTitle
                            }
                            return rawTitle.hasPrefix("\(item.episode).") ? rawTitle : "\(item.episode). \(rawTitle)"
                        }()
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.primary)
                        
                        // Metadata: Rating & Date
                        HStack(spacing: 12) {
                            let ratingVal: Double? = {
                                if let v = item.seasonEpisode?.voteAverage, v > 0 { return v }
                                if let v = item.meta?.ratings?.tmdb ?? item.meta?.ratings?.imdb, v > 0 { return v }
                                return nil
                            }()
                            if let rating = ratingVal {
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 12, weight: .heavy))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(Color.rating(rating))
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            } else if item.episode == 0 {
                                Text("Пилот")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.clear.glassEffect(in: RoundedRectangle(cornerRadius: 8, style: .continuous)))
                            }
                            
                            let airDate = item.seasonEpisode?.airDate ?? item.meta?.airDate ?? (item.episode == 0 ? (details?.releaseDate) : nil)
                            if let airDate = airDate, !airDate.isEmpty {
                                Text(formatAirDate(airDate))
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }

                            if let duration = item.seasonEpisode?.duration, duration > 0 {
                                Text("\(duration) мин")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.bottom, 2)
                        
                        // Description / Overview
                        let overview = item.seasonEpisode?.overview ?? item.meta?.overview ?? (item.episode == 0 ? (details?.description ?? "Пилотный выпуск сериала.") : nil)
                        if let overview = overview, !overview.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Описание серии")
                                    .font(.system(size: 16, weight: .bold))
                                
                                Text(overview)
                                    .font(.system(size: 15))
                                    .foregroundColor(.primary.opacity(0.85))
                                    .lineSpacing(4)
                            }
                        } else {
                            Text("Описание для этой серии отсутствует.")
                                .font(.system(size: 15))
                                .foregroundColor(.secondary)
                                .italic()
                        }
                        
                        // Bottom action: Play button or Release status
                        if item.isAvailable {
                            HStack(spacing: 12) {
                                Button(action: {
                                    dismiss()
                                    onPlay()
                                }) {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Смотреть серию")
                                    }
                                    .font(.system(size: 17, weight: .bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.large)
                                .buttonBorderShape(.capsule)
                                .tint(.primary)
                                .foregroundStyle(Color(UIColor.systemBackground))
                            }
                            .padding(.top, 8)
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 22, weight: .semibold))
                                    .foregroundColor(Color.slooshAccent)
                                
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Ожидается премьера")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primary)
                                    
                                    let airDate = item.seasonEpisode?.airDate ?? item.meta?.airDate
                                    if let airDate = airDate, !airDate.isEmpty {
                                        Text("Дата выхода: \(formatAirDate(airDate))")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("Дата выхода пока не объявлена")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color.clear.glassEffect(in: RoundedRectangle(cornerRadius: 16, style: .continuous)))
                            .padding(.top, 8)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("\(item.season) сезон, \(item.episode) серия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .buttonStyle(.plain)
                }
                
                if item.isAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.prepare()
                            generator.impactOccurred()
                            isWatched.toggle()
                            onWatchedToggle(isWatched)
                        } label: {
                            Image(systemName: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(isWatched ? Color.slooshAccent : .primary)
                        }
                    }
                }
            }
        }
        .onAppear {
            guard item.isAvailable else { return }
            let root = item.movieId.hasPrefix("kp_") || item.movieId.hasPrefix("tmdb_") ? item.movieId : "kp_\(item.movieId)"
            let progressKey = "\(root)_s\(item.season)_e\(item.episode)"
            let progressFraction = PlaybackProgressStore.shared.normalizedProgress(mediaId: progressKey)
            isWatched = PlaybackProgressStore.shared.loadWatched(mediaId: progressKey) || (progressFraction ?? 0) >= 0.9
        }
    }
    
    private func formatAirDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func handleEpisodeDownload(kpId: Int, details: MediaDetailsDto, item: DownloadItem?) {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        
        if let item = item {
            switch item.status {
            case .downloading, .pending:
                DownloadManager.shared.pauseDownload(id: item.id)
            case .paused:
                DownloadManager.shared.resumeDownload(id: item.id)
            case .failed:
                startDownload(kpId: kpId, details: details)
            case .completed:
                DownloadManager.shared.deleteDownload(id: item.id)
            }
        } else {
            startDownload(kpId: kpId, details: details)
        }
    }
    
    private func startDownload(kpId: Int, details: MediaDetailsDto) {
        guard let vm = viewModel else { return }
        Task {
            let title = details.title ?? details.originalTitle ?? ""
            let tmdbId = details.externalIds?.tmdb ?? details.ids?.tmdb ?? Int(details.id ?? "")
            let imdbId = details.externalIds?.imdb ?? details.ids?.imdb
            await vm.fetchSources(
                kpId: kpId,
                tmdbId: tmdbId,
                imdbId: imdbId,
                title: title,
                originalTitle: details.originalTitle,
                year: details.year
            )
            guard let result = vm.sourceResultWrapper?.allohaResult else { return }
            
            let savedVoiceover = PlaybackProgressStore.shared.loadLastVoiceover(kpId: kpId, source: "alloha")
            let globalVoiceover = UserDefaults.standard.string(forKey: "alloha_last_translation_name")
            
            guard let seasonObj = result.seasons.first(where: { $0.season == item.season }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == item.episode }) else { return }
            
            guard let translation = bestTranslation(in: epObj.translations, preferredName: savedVoiceover ?? globalVoiceover) else { return }
            
            let preferredQuality = VideoQualityPreference(rawValue: UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? "Спрашивать каждый раз") ?? .ask
            DownloadManager.shared.startDownload(
                details: details,
                season: item.season,
                episode: item.episode,
                translation: translation,
                preferredQuality: preferredQuality
            )
        }
    }
}

struct EpisodeCellView: View {
    let movieId: String
    let season: Int
    let episode: Int
    let fallbackTitle: String
    var seasonEpisode: TvSeasonEpisodeDto? = nil
    var details: MediaDetailsDto? = nil
    var isAvailable: Bool = true
    var isLastPlayed: Bool = false
    let onPlayTap: () -> Void
    let onUpdate: () -> Void
    let onInfoTap: (TvEpisodeDetailsDto?, TvSeasonEpisodeDto?) -> Void
    
    @State private var meta: TvEpisodeDetailsDto?
    @State private var isLoading = false
    
    @State private var progressFractionState: Double?
    @State private var isWatchedState: Bool = false
    
    @ObservedObject private var downloadManager = DownloadManager.shared
    
    init(
        movieId: String,
        season: Int,
        episode: Int,
        fallbackTitle: String = "Серия",
        seasonEpisode: TvSeasonEpisodeDto? = nil,
        details: MediaDetailsDto? = nil,
        isAvailable: Bool = true,
        isLastPlayed: Bool = false,
        onPlayTap: @escaping () -> Void = {},
        onUpdate: @escaping () -> Void = {},
        onInfoTap: @escaping (TvEpisodeDetailsDto?, TvSeasonEpisodeDto?) -> Void = { _, _ in }
    ) {
        self.movieId = movieId
        self.season = season
        self.episode = episode
        self.fallbackTitle = fallbackTitle
        self.seasonEpisode = seasonEpisode
        self.details = details
        self.isAvailable = isAvailable
        self.isLastPlayed = isLastPlayed
        self.onPlayTap = onPlayTap
        self.onUpdate = onUpdate
        self.onInfoTap = onInfoTap

        let root: String
        if let kp = details?.ids?.kp ?? details?.externalIds?.kp, kp > 0 {
            root = "kp_\(kp)"
        } else if movieId.hasPrefix("kp_") || movieId.hasPrefix("tmdb_") {
            root = movieId
        } else if let intVal = Int(movieId) {
            root = "kp_\(intVal)"
        } else {
            root = movieId
        }
        let progressKey = "\(root)_s\(season)_e\(episode)"
        let prog = PlaybackProgressStore.shared.normalizedProgress(mediaId: progressKey)
        let watched = PlaybackProgressStore.shared.loadWatched(mediaId: progressKey) || (prog ?? 0) >= 0.9
        _progressFractionState = State(initialValue: prog)
        _isWatchedState = State(initialValue: watched)
    }

    var previewUrl: URL? {
        if let still = seasonEpisode?.stillPath ?? meta?.stillPath, !still.isEmpty {
            if still.hasPrefix("http") {
                return URL(string: still)
            } else {
                return URL(string: "\(MoviesApi.activeImagesBaseURL)/api/v1/images/tmdb/w500\(still)")
            }
        }
        let backdrop = details?.previewBackdropUrl ?? details?.displayBackdropUrl ?? details?.backdrop
        if let backdrop = backdrop, !backdrop.isEmpty {
            if backdrop.hasPrefix("http") {
                return URL(string: backdrop)
            } else {
                return URL(string: "\(MoviesApi.activeImagesBaseURL)/api/v1/images/tmdb/w500\(backdrop)")
            }
        }
        return nil
    }
    
    private var progressKey: String {
        let root: String
        let effectiveDetails = details
        if let kp = effectiveDetails?.ids?.kp ?? effectiveDetails?.externalIds?.kp, kp > 0 {
            root = "kp_\(kp)"
        } else if movieId.hasPrefix("kp_") || movieId.hasPrefix("tmdb_") {
            root = movieId
        } else if let intVal = Int(movieId) {
            root = "kp_\(intVal)"
        } else {
            root = movieId
        }
        return "\(root)_s\(season)_e\(episode)"
    }
    
    private func updateProgressState() {
        guard isAvailable else { return }
        progressFractionState = PlaybackProgressStore.shared.normalizedProgress(mediaId: progressKey)
        isWatchedState = PlaybackProgressStore.shared.loadWatched(mediaId: progressKey) || (progressFractionState ?? 0) >= 0.9
    }
    
    private func formatEpisodeAirDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private func formatShortAirDate(_ dateStr: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dateStr) else { return dateStr }
        
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                // Background Card
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(UIColor.tertiarySystemFill))
                    .frame(width: 160, height: 90)
                
                // Preview Image
                AsyncCachedImage(url: previewUrl) {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 160, height: 90)
                        .shimmer()
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 160, height: 90)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .opacity(isAvailable ? 1.0 : 0.85)
                } fallback: {
                    ZStack {
                        LinearGradient(
                            colors: [Color(white: 0.16), Color(white: 0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        Image(systemName: isAvailable ? "play.circle.fill" : "calendar.badge.clock")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.35))
                    }
                    .frame(width: 160, height: 90)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .animation(.easeInOut(duration: 0.25), value: previewUrl)
                
                // Dark gradient overlay
                VStack {
                    Spacer()
                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.35)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 24)
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .allowsHitTesting(false)
                
                // Progress Bar (Bottom Aligned, only if available)
                if isAvailable, let progress = progressFractionState, progress > 0.02 {
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle()
                                .fill(.white.opacity(0.2))
                                .frame(height: 3)
                            
                            Rectangle()
                                .fill(isWatchedState ? Color.gray : Color.slooshAccent)
                                .frame(width: 160 * CGFloat(progress), height: 3)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                
                // Rating overlay on top-left of the card (Unified with design system, only if available)
                if isAvailable {
                    let ratingVal: Double? = {
                        if let v = seasonEpisode?.voteAverage, v > 0 { return v }
                        if let v = meta?.ratings?.tmdb ?? meta?.ratings?.imdb, v > 0 { return v }
                        return nil
                    }()
                    if let rating = ratingVal {
                        VStack {
                            HStack {
                                Text(String(format: "%.1f", rating))
                                    .font(.system(size: 10, weight: .heavy))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 3)
                                    .background(Color.rating(rating))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .padding(6)
                                Spacer()
                            }
                            Spacer()
                        }
                    } else if episode == 0 {
                        VStack {
                            HStack {
                                Text("Пилот")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.clear.glassEffect(in: RoundedRectangle(cornerRadius: 6, style: .continuous)))
                                    .padding(6)
                                Spacer()
                            }
                            Spacer()
                        }
                    }
                } else {
                    // Unreleased badge on top-left of the card
                    VStack {
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                    .font(.system(size: 9, weight: .semibold))
                                let rawDate = seasonEpisode?.airDate ?? meta?.airDate
                                Text(rawDate.map { formatShortAirDate($0) } ?? "Скоро")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.clear.glassEffect(in: RoundedRectangle(cornerRadius: 6, style: .continuous)))
                            .padding(6)
                            Spacer()
                        }
                        Spacer()
                    }
                }
                
                // Watched Checkmark Badge (Top-Right, only if available)
                if isAvailable && isWatchedState {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundColor(Color.slooshAccent)
                                .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                                .padding([.top, .trailing], 8)
                        }
                        Spacer()
                    }
                }
                
                // Download Badge (Top-Right, shifted left if watched is present, only if available)
                if isAvailable, let kpIdInt = Int(movieId) {
                    let downloadItem = downloadManager.getDownloadItem(kpId: kpIdInt, season: season, episode: episode)
                    if let dlItem = downloadItem {
                        VStack {
                            HStack {
                                Spacer()
                                if dlItem.status == .completed {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 16))
                                        .foregroundColor(Color.slooshAccent)
                                        .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                                        .padding([.top, .trailing], 8)
                                        .padding(.trailing, isWatchedState ? 20 : 0) // Shift left if checkmark is there
                                } else if dlItem.status == .downloading {
                                    ZStack {
                                        Circle()
                                            .stroke(Color.black.opacity(0.4), lineWidth: 1.5)
                                            .frame(width: 14, height: 14)
                                        Circle()
                                            .trim(from: 0.0, to: dlItem.progress)
                                            .stroke(Color.slooshAccent, lineWidth: 1.5)
                                            .frame(width: 14, height: 14)
                                            .rotationEffect(Angle(degrees: -90))
                                    }
                                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                                    .padding([.top, .trailing], 8)
                                    .padding(.trailing, isWatchedState ? 20 : 0)
                                }
                            }
                            Spacer()
                        }
                    }
                }

                // Last Played Border (Centered, matches size, no clipping, only if available)
                if isAvailable && isLastPlayed {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.slooshAccent, lineWidth: 2)
                }
            }
            .frame(width: 160, height: 90)
            .contextMenu {
                if isAvailable {
                    Button {
                        onPlayTap()
                    } label: {
                        Label("Смотреть", systemImage: "play.fill")
                    }
                }
                
                Button {
                    onInfoTap(meta, seasonEpisode)
                } label: {
                    Label("О серии", systemImage: "info.circle")
                }
                
                if isAvailable {
                    Divider()
                    
                    if isWatchedState {
                        Button(role: .destructive) {
                            PlaybackProgressStore.shared.setWatched(mediaId: progressKey, watched: false)
                            updateProgressState()
                            onUpdate()
                        } label: {
                            Label("Сбросить прогресс", systemImage: "arrow.counterclockwise")
                        }
                    } else {
                        Button {
                            PlaybackProgressStore.shared.markAsWatched(mediaId: progressKey)
                            updateProgressState()
                            onUpdate()
                        } label: {
                            Label("Отметить как просмотренную", systemImage: "checkmark.circle")
                        }
                    }
                }
            }
            
            let rawTitle = seasonEpisode?.name ?? meta?.name ?? (episode == 0 ? "Пилотная серия" : fallbackTitle)
            let displayTitle: String = {
                if episode == 0 {
                    return rawTitle
                }
                return rawTitle.hasPrefix("\(episode).") ? rawTitle : "\(episode). \(rawTitle)"
            }()
            
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayTitle)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    let airDate = seasonEpisode?.airDate ?? meta?.airDate ?? (episode == 0 ? (details?.releaseDate) : nil)
                    if let airDate = airDate, !airDate.isEmpty {
                        Text(formatEpisodeAirDate(airDate))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.prepare()
                    generator.impactOccurred()
                    onInfoTap(meta, seasonEpisode)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 15))
                        .foregroundColor(.secondary.opacity(0.8))
                        .padding(.leading, 4)
                }
                .buttonStyle(.plain)
            }
            .frame(width: 160)
        }
        .animation(.easeInOut(duration: 0.25), value: isLoading)
        .task(id: "\(season)-\(episode)") {
            updateProgressState()
            if seasonEpisode != nil { return }
            if isLoading { return }
            // Brief pause so season-level getSeason can finish, avoiding redundant individual network calls
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled || seasonEpisode != nil || isLoading { return }
            isLoading = true
            meta = nil
            do {
                var fetchedMeta: TvEpisodeDetailsDto? = nil
                let candidateIds = [movieId].compactMap { $0 }.filter { !$0.isEmpty }
                
                for candidateId in candidateIds {
                    do {
                        let result = try await MoviesRepository.shared.getEpisodeDetails(id: candidateId, season: season, episode: episode)
                        if result?.name != nil || result?.overview != nil || result?.ratings?.tmdb != nil || result?.ratings?.imdb != nil {
                            fetchedMeta = result
                            break
                        }
                    } catch {
                        continue
                    }
                }
                
                if let fetchedMeta = fetchedMeta {
                    meta = fetchedMeta
                } else {
                    meta = try await MoviesRepository.shared.getEpisodeDetails(id: movieId, season: season, episode: episode)
                }
            } catch {
                // Ignore
            }
            isLoading = false
        }
    }
}

struct InlineEpisodesSection: View {
    @ObservedObject var viewModel: DetailsViewModel
    let details: MediaDetailsDto
    var horizontalPadding: CGFloat = 16
    let onEpisodeTap: (Int, Int) -> Void

    @State private var selectedSeason: Int = 1
    @State private var selectedEpisodeForSheet: EpisodeDetailsSheetItem? = nil
    @State private var fullyWatchedSeasons: Set<Int> = []
    @State private var redrawTrigger: Bool = false
    @State private var currentSeasonData: TvSeasonDto? = nil

    var allSeasons: [Int] {
        let streamSeasons = viewModel.inlineSourceWrapper?.allohaResult?.seasons.map { $0.season } ?? []
        let metaSeasons = details.seasons?.compactMap { $0.seasonNumber }.filter { $0 > 0 } ?? []
        let combined = Array(Set(streamSeasons + metaSeasons)).sorted()
        return combined.isEmpty ? streamSeasons : combined
    }

    var rawId: String {
        details.ids?.kp?.description ?? details.id?.replacingOccurrences(of: "kp_", with: "") ?? ""
    }

    var tvSeriesId: String {
        if let tmdb = details.externalIds?.tmdb ?? details.ids?.tmdb, tmdb > 0 {
            return String(tmdb)
        }
        if let kp = details.ids?.kp ?? details.externalIds?.kp, kp > 0 {
            return "kp_\(kp)"
        }
        return details.id ?? rawId
    }

    var episodesForSelectedSeason: [Int] {
        let streamEpisodes = viewModel.inlineSourceWrapper?.allohaResult?.seasons.first(where: { $0.season == selectedSeason })?.episodes.map { $0.episode } ?? []
        let metaEpisodes = currentSeasonData?.episodes?.compactMap { $0.episodeNumber } ?? []
        let combined = Array(Set(streamEpisodes + metaEpisodes)).sorted()
        return combined.isEmpty ? streamEpisodes : combined
    }

    private func isEpisodeAvailable(_ episode: Int) -> Bool {
        guard let seasonObj = viewModel.inlineSourceWrapper?.allohaResult?.seasons.first(where: { $0.season == selectedSeason }) else {
            return false
        }
        return seasonObj.episodes.contains(where: { $0.episode == episode })
    }

    private func episodesCount(for seasonNum: Int) -> Int {
        let streamCount = viewModel.inlineSourceWrapper?.allohaResult?.seasons.first(where: { $0.season == seasonNum })?.episodes.count ?? 0
        if streamCount > 0 { return streamCount }
        return details.seasons?.first(where: { $0.seasonNumber == seasonNum })?.episodeCount ?? 0
    }

    private func loadCurrentSeason() {
        let idToFetch = tvSeriesId
        Task {
            do {
                currentSeasonData = try await MoviesRepository.shared.getSeason(id: idToFetch, season: selectedSeason)
            } catch {
                currentSeasonData = nil
            }
        }
    }

    private func updateWatchedSeasons() {
        guard let seasons = viewModel.inlineSourceWrapper?.allohaResult?.seasons else { return }
        var completed = Set<Int>()

        for s in seasons {
            let episodes = s.episodes.map { $0.episode }
            if !episodes.isEmpty {
                let allWatched = episodes.allSatisfy { ep in
                    let progressKey = "kp_\(rawId)_s\(s.season)_e\(ep)"
                    let progressFraction = PlaybackProgressStore.shared.normalizedProgress(mediaId: progressKey)
                    return PlaybackProgressStore.shared.loadWatched(mediaId: progressKey) || (progressFraction ?? 0) >= 0.9
                }
                if allWatched {
                    completed.insert(s.season)
                }
            }
        }
        self.fullyWatchedSeasons = completed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Сезоны и серии")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal, horizontalPadding)

            if viewModel.isFetchingInlineSeasons && allSeasons.isEmpty {
                loadingView
            } else if allSeasons.isEmpty {
                Text("Эпизоды не найдены")
                    .font(.system(size: 15))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, horizontalPadding)
            } else {
                seasonPickerView
                episodesListView
            }
        }
        .onAppear {
            updateWatchedSeasons()
            guard let kpId = details.ids?.kp else {
                loadCurrentSeason()
                return
            }
            let lastSeason = PlaybackProgressStore.shared.loadLastSeason(kpId: kpId)
            if let lastSeason, allSeasons.contains(lastSeason) {
                selectedSeason = lastSeason
            } else if let firstSeason = allSeasons.first {
                selectedSeason = firstSeason
            }
            loadCurrentSeason()
        }
        .onChange(of: selectedSeason) { _, _ in
            loadCurrentSeason()
        }
        .onChange(of: allSeasons) { _, newSeasons in
            updateWatchedSeasons()
            if !newSeasons.contains(selectedSeason), let first = newSeasons.first {
                selectedSeason = first
            }
            loadCurrentSeason()
        }
        .sheet(item: $selectedEpisodeForSheet) { item in
            EpisodeDetailsSheet(
                item: item,
                details: details,
                viewModel: viewModel,
                onPlay: { () -> Void in
                    onEpisodeTap(item.season, item.episode)
                },
                onWatchedToggle: { (isWatched: Bool) -> Void in
                    let progressKey = "kp_\(item.movieId)_s\(item.season)_e\(item.episode)"
                    if isWatched {
                        PlaybackProgressStore.shared.markAsWatched(mediaId: progressKey)
                    } else {
                        PlaybackProgressStore.shared.setWatched(mediaId: progressKey, watched: false)
                    }
                    updateWatchedSeasons()
                    redrawTrigger.toggle()
                }
            )
            .environmentObject(viewModel)
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    @ViewBuilder
    private var loadingView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<4) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 160, height: 90)
                        .shimmer()
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    @ViewBuilder
    private var seasonPickerView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 8) {
                ForEach(allSeasons, id: \.self) { season in
                    Button(action: {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.prepare()
                        generator.impactOccurred()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedSeason = season
                        }
                    }) {
                        HStack(spacing: 6) {
                            Text("\(season) сезон")
                                .font(.system(size: 14, weight: .semibold))
                            if fullyWatchedSeasons.contains(season) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(selectedSeason == season ? .black : Color.slooshAccent)
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                if selectedSeason == season {
                                    Capsule().fill(Color.white)
                                } else {
                                    Color.clear.glassEffect(in: Capsule())
                                }
                            }
                        )
                        .foregroundColor(selectedSeason == season ? .black : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, horizontalPadding)
        }
    }

    @ViewBuilder
    private var episodesListView: some View {
        let effectiveKp = details.ids?.kp ?? details.externalIds?.kp ?? (rawId.hasPrefix("kp_") ? Int(rawId.dropFirst(3)) : nil)
        let rootKey = effectiveKp.map { "kp_\($0)" } ?? (rawId.hasPrefix("tmdb_") ? rawId : "tmdb_\(rawId)")
        let lastPlayedSeason = PlaybackProgressStore.shared.loadLastSeason(mediaKey: rootKey) ?? (effectiveKp.flatMap { PlaybackProgressStore.shared.loadLastSeason(kpId: $0) })
        let lastPlayedEpisode = PlaybackProgressStore.shared.loadLastEpisode(mediaKey: rootKey) ?? (effectiveKp.flatMap { PlaybackProgressStore.shared.loadLastEpisode(kpId: $0) })

        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(episodesForSelectedSeason, id: \.self) { episode in
                        let isAvailable = isEpisodeAvailable(episode)
                        let isLastPlayed = (selectedSeason == lastPlayedSeason && episode == lastPlayedEpisode)
                        let seasonEpisode: TvSeasonEpisodeDto? = {
                            if let found = currentSeasonData?.episodes?.first(where: { $0.episodeNumber == episode }) {
                                return found
                            }
                            if episode == 0 {
                                return TvSeasonEpisodeDto(
                                    id: 0,
                                    name: "Пилотная серия",
                                    overview: viewModel.details?.description ?? "Пилотный выпуск сериала.",
                                    airDate: currentSeasonData?.airDate ?? viewModel.details?.releaseDate ?? "",
                                    episodeNumber: 0,
                                    seasonNumber: selectedSeason,
                                    stillPath: viewModel.details?.previewBackdropUrl ?? viewModel.details?.displayBackdropUrl ?? viewModel.details?.backdrop,
                                    voteAverage: 0,
                                    duration: currentSeasonData?.episodes?.first?.duration
                                )
                            }
                            return nil
                        }()
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: isAvailable ? .medium : .light)
                            generator.prepare()
                            generator.impactOccurred()
                            if isAvailable {
                                onEpisodeTap(selectedSeason, episode)
                            } else {
                                selectedEpisodeForSheet = EpisodeDetailsSheetItem(
                                    movieId: rawId,
                                    season: selectedSeason,
                                    episode: episode,
                                    meta: nil,
                                    seasonEpisode: seasonEpisode,
                                    fallbackTitle: "Серия",
                                    isAvailable: false
                                )
                            }
                        }) {
                            EpisodeCellView(
                                movieId: rawId,
                                season: selectedSeason,
                                episode: episode,
                                fallbackTitle: "Серия",
                                seasonEpisode: seasonEpisode,
                                details: details,
                                isAvailable: isAvailable,
                                isLastPlayed: isLastPlayed,
                                onPlayTap: { () -> Void in
                                    if isAvailable {
                                        onEpisodeTap(selectedSeason, episode)
                                    }
                                },
                                onUpdate: { () -> Void in
                                    updateWatchedSeasons()
                                    redrawTrigger.toggle()
                                },
                                onInfoTap: { (fetchedMeta: TvEpisodeDetailsDto?, epData: TvSeasonEpisodeDto?) -> Void in
                                    selectedEpisodeForSheet = EpisodeDetailsSheetItem(
                                        movieId: rawId,
                                        season: selectedSeason,
                                        episode: episode,
                                        meta: fetchedMeta,
                                        seasonEpisode: epData ?? seasonEpisode,
                                        fallbackTitle: "Серия",
                                        isAvailable: isAvailable
                                    )
                                }
                            )
                            .environmentObject(viewModel)
                            .id("\(selectedSeason)-\(episode)-\(seasonEpisode?.id ?? 0)-\(isAvailable)-\(redrawTrigger)")
                        }
                        .buttonStyle(.plain)
                        .id("\(selectedSeason)-\(episode)")
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
            .onAppear {
                scrollToLastPlayed(proxy: proxy)
            }
            .onChange(of: selectedSeason) { _, _ in
                scrollToLastPlayed(proxy: proxy)
            }
            .onChange(of: episodesForSelectedSeason) { _, _ in
                scrollToLastPlayed(proxy: proxy)
            }
        }
    }

    private func scrollToLastPlayed(proxy: ScrollViewProxy) {
        guard let kpId = details.ids?.kp else { return }
        let lastSeason = PlaybackProgressStore.shared.loadLastSeason(kpId: kpId) ?? 1
        let lastEpisode = PlaybackProgressStore.shared.loadLastEpisode(kpId: kpId) ?? 1

        if selectedSeason == lastSeason {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    proxy.scrollTo("\(lastSeason)-\(lastEpisode)", anchor: .center)
                }
            }
        }
    }
}

// Обертка для Identifiable, чтобы использовать в .sheet(item:)
struct SourceResultWrapper: Identifiable {
    let id = UUID()
    var allohaResult: AllohaApiResult?
    var collapsResult: CollapsParser.ParseResult?
    var kpId: Int?
}

@MainActor
class DetailsViewModel: ObservableObject {
    @Published var details: MediaDetailsDto?
    @Published var isLoading = true

    @Published var isFetchingSources = false
    @Published var hasFinishedSourceFetch = false
    @Published var sourceResultWrapper: SourceResultWrapper?

    @Published var inlineSourceWrapper: SourceResultWrapper?
    @Published var selectedInlineSeason: Int = 1
    @Published var isFetchingInlineSeasons = false

    @Published var relatedStudio: RelatedStudioResponse? = nil
    @Published var movieCollection: MovieCollectionDto? = nil
    @Published var isFetchingRelatedStudio = false
    @Published var isFetchingCollection = false

    @Published var isFavorite: Bool = false

    private let allohaTranslationPreferenceKey = "alloha_last_translation_name"

    init(id: String? = nil, type: String? = nil) {
        if let id = id, let cached = MoviesRepository.shared.getCachedDetails(id: id, type: type) {
            self.details = cached
            self.isLoading = false
            self.checkFavoriteStatus()
        }
    }

    // MARK: - Sources cache (5 min TTL)
    private var sourcesCache: [Int: (wrapper: SourceResultWrapper, expiresAt: Date)] = [:]
    private let sourcesCacheTtl: TimeInterval = 5 * 60

    func prepareSourceSheet(kpId: Int, tmdbId: Int? = nil) {
        let effectiveTmdbId = tmdbId ?? details?.externalIds?.tmdb ?? details?.ids?.tmdb ?? Int(details?.id ?? "")
        let cacheKey = kpId > 0 ? kpId : (effectiveTmdbId ?? 0)

        if cacheKey > 0, let cached = sourcesCache[cacheKey], cached.expiresAt > Date() {
            sourceResultWrapper = cached.wrapper
            isFetchingSources = false
            hasFinishedSourceFetch = true
        } else {
            sourceResultWrapper = nil
            isFetchingSources = true
            hasFinishedSourceFetch = false
        }
    }

    func resetSourceSheet() {
        sourceResultWrapper = nil
        isFetchingSources = false
        hasFinishedSourceFetch = false
    }

    func saveAllohaTranslation(_ name: String?) {
        guard let name = name, !name.isEmpty else { return }
        guard !isOriginalOrEnglishTranslation(name) else { return }
        UserDefaults.standard.set(name, forKey: allohaTranslationPreferenceKey)
    }

    func loadDetails(id: String, type: String? = nil, force: Bool = false, studio: StudioBrand? = nil) async {
        let inferredType = type ?? (id.hasPrefix("tv_") ? "tv" : (id.hasPrefix("movie_") ? "movie" : nil))
        if !force && details != nil && (details?.id == id || details?.ids?.kp?.description == id.replacingOccurrences(of: "kp_", with: "")) && (inferredType == nil || details?.type == inferredType) {
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            details = try await MoviesRepository.shared.getDetails(id: id, type: inferredType)
            if let details {
                PlaybackProgressStore.shared.saveMetadata(details: details)
            }
            checkFavoriteStatus()

            let isTv = details?.type == "tv" || inferredType == "tv"
            let effectiveKpId = details?.ids?.kp ?? details?.externalIds?.kp ?? (id.hasPrefix("kp_") ? Int(id.replacingOccurrences(of: "kp_", with: "")) : nil)
            let tmdbId = details?.externalIds?.tmdb ?? details?.ids?.tmdb ?? Int(details?.id ?? "")
            let effectiveImdbId = details?.externalIds?.imdb ?? details?.ids?.imdb

            if isTv, ((effectiveKpId ?? 0) > 0 || (tmdbId ?? 0) > 0 || effectiveImdbId != nil || !(details?.title ?? "").isEmpty) {
                await fetchInlineSeasons(
                    kpId: effectiveKpId ?? 0,
                    tmdbId: tmdbId,
                    imdbId: effectiveImdbId,
                    title: details?.title,
                    originalTitle: details?.originalTitle,
                    year: details?.year
                )
            }

            let studioToFetch = details?.identifiedStudio ?? studio
            let resolvedType = details?.type ?? inferredType ?? "movie"
            Task {
                await self.fetchRelatedByStudio(type: resolvedType, id: id, studio: studioToFetch)
            }
            if !isTv {
                Task {
                    await self.fetchMovieCollection(id: id)
                }
            }
        } catch {
            print("Error loading details: \(error)")
        }
    }

    func fetchRelatedByStudio(type: String, id: String, studio: StudioBrand? = nil) async {
        isFetchingRelatedStudio = true
        defer { isFetchingRelatedStudio = false }
        
        let rawCleanId = id.replacingOccurrences(of: "kp_", with: "")

        if let apiResult = await MoviesRepository.shared.getRelatedByStudio(type: type, id: id) {
            let items = apiResult.allItems
            if !items.isEmpty {
                let otherMovies = items.filter {
                    let itemCleanId = $0.id.replacingOccurrences(of: "kp_", with: "")
                    return itemCleanId != rawCleanId && $0.id != id
                }
                if !otherMovies.isEmpty {
                    let randomized = Array(otherMovies.shuffled().prefix(20))
                    self.relatedStudio = RelatedStudioResponse(
                        items: randomized,
                        label: apiResult.label,
                        page: apiResult.page,
                        totalPages: apiResult.totalPages,
                        totalResults: randomized.count
                    )
                    return
                }
            }
        }
        
        if let brand = studio {
            do {
                let collection = try await MoviesRepository.shared.getCollection(id: brand.id, page: 1)
                let otherMovies = collection.items.filter {
                    let itemCleanId = $0.id.replacingOccurrences(of: "kp_", with: "")
                    return itemCleanId != rawCleanId && $0.id != id
                }
                if !otherMovies.isEmpty {
                    let randomized = Array(otherMovies.shuffled().prefix(20))
                    self.relatedStudio = RelatedStudioResponse(
                        items: randomized,
                        label: brand.name,
                        page: 1,
                        totalPages: collection.totalPages,
                        totalResults: randomized.count
                    )
                }
            } catch {
                // Ignore fallback error
            }
        }
    }

    func fetchMovieCollection(id: String) async {
        isFetchingCollection = true
        defer { isFetchingCollection = false }
        self.movieCollection = await MoviesRepository.shared.getMovieCollection(id: id)
    }

    func fetchInlineSeasons(
        kpId: Int,
        tmdbId: Int? = nil,
        imdbId: String? = nil,
        title: String? = nil,
        originalTitle: String? = nil,
        year: Int? = nil
    ) async {
        isFetchingInlineSeasons = true
        defer { isFetchingInlineSeasons = false }

        let effectiveTmdbId = tmdbId ?? details?.externalIds?.tmdb ?? details?.ids?.tmdb ?? Int(details?.id ?? "")
        let effectiveImdbId = imdbId ?? details?.externalIds?.imdb ?? details?.ids?.imdb
        let effectiveTitle = (title?.isEmpty == false ? title : details?.title) ?? ""
        let effectiveOriginal = originalTitle ?? details?.originalTitle
        let effectiveYear = year ?? details?.year

        do {
            let result = try await AllohaRepository.shared.fetchByKpId(
                kpId: kpId,
                tmdbId: effectiveTmdbId,
                imdbId: effectiveImdbId,
                title: effectiveTitle,
                originalTitle: effectiveOriginal,
                year: effectiveYear
            )
            if result.isSerial && !result.seasons.isEmpty {
                self.inlineSourceWrapper = SourceResultWrapper(allohaResult: result, collapsResult: nil, kpId: kpId > 0 ? kpId : (effectiveTmdbId ?? 0))
                return
            }
        } catch {
            print("Alloha inline seasons error: \(error)")
        }

        // Fallback to Collaps for inline seasons
        let effectiveKp = kpId > 0 ? kpId : (self.details?.ids?.kp ?? self.details?.externalIds?.kp)
        if let collaps = try? await CollapsRepository.shared.fetchMedia(
            kpId: effectiveKp,
            imdbId: effectiveImdbId,
            title: effectiveTitle
        ), collaps.apiResult.isSerial && !collaps.apiResult.seasons.isEmpty {
            self.inlineSourceWrapper = SourceResultWrapper(allohaResult: collaps.apiResult, collapsResult: collaps, kpId: kpId > 0 ? kpId : (effectiveTmdbId ?? 0))
        }
    }

    func checkFavoriteStatus() {
        guard let details = details else { return }
        guard let (mediaId, mediaType) = favoriteKey(for: details) else { return }
        var fav = FavoritesRepository.shared.isFavorite(mediaId: mediaId, mediaType: mediaType)
        if !fav, let kpId = details.ids?.kp?.description {
            fav = FavoritesRepository.shared.isFavorite(mediaId: kpId, mediaType: mediaType)
        }
        isFavorite = fav
    }

    func toggleFavorite() {
        guard let details = details else { return }
        guard let (mediaId, mediaType) = favoriteKey(for: details) else { return }

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()

        if isFavorite {
            FavoritesRepository.shared.removeFromFavorites(mediaId: mediaId, mediaType: mediaType)
            if let kpId = details.ids?.kp?.description {
                FavoritesRepository.shared.removeFromFavorites(mediaId: kpId, mediaType: mediaType)
            }
            generator.notificationOccurred(.warning)
            ToastManager.shared.show(title: "Удалено из избранного", icon: "heart.slash.fill", iconColor: .primary, duration: 2.0)
        } else {
            FavoritesRepository.shared.addToFavorites(
                mediaId: mediaId,
                mediaType: mediaType,
                title: details.title ?? details.originalTitle,
                posterUrl: details.poster ?? details.backdrop,
                rating: details.ratings?.tmdb ?? details.ratings?.kp,
                year: details.year?.description,
                genres: details.genres?.compactMap { GenreDto(id: $0.lowercased(), name: $0) }
            )
            generator.notificationOccurred(.success)
            ToastManager.shared.show(title: "Добавлено в избранное", icon: "heart.fill", iconColor: .primary, duration: 2.0)
        }
        isFavorite.toggle()
    }

    private func favoriteKey(for details: MediaDetailsDto) -> (String, String)? {
        guard let mediaId = details.id, !mediaId.isEmpty else { return nil }
        let type = (details.type?.lowercased() == "tv" || details.type?.lowercased() == "series") ? "tv" : "movie"
        return (mediaId, type)
    }

    func fetchSources(
        kpId: Int,
        tmdbId: Int? = nil,
        imdbId: String? = nil,
        title: String,
        originalTitle: String? = nil,
        year: Int? = nil
    ) async {
        let effectiveTmdbId = tmdbId ?? details?.externalIds?.tmdb ?? details?.ids?.tmdb ?? Int(details?.id ?? "")
        let effectiveImdbId = imdbId ?? details?.externalIds?.imdb ?? details?.ids?.imdb
        let effectiveTitle = title.isEmpty ? (details?.title ?? "") : title
        let effectiveOriginal = originalTitle ?? details?.originalTitle
        let effectiveYear = year ?? details?.year
        let cacheKey = kpId > 0 ? kpId : (effectiveTmdbId ?? 0)

        // Кэш на 5 минут — повторный тап «Смотреть» возвращает результат мгновенно
        if cacheKey > 0, let cached = sourcesCache[cacheKey], cached.expiresAt > Date() {
            sourceResultWrapper = cached.wrapper
            isFetchingSources = false
            hasFinishedSourceFetch = true
            return
        }

        sourceResultWrapper = nil
        isFetchingSources = true
        hasFinishedSourceFetch = false
        defer {
            isFetchingSources = false
            hasFinishedSourceFetch = true
        }

        let validKp = kpId > 0 ? kpId : (self.details?.ids?.kp ?? self.details?.externalIds?.kp)

        async let allohaTask = AllohaRepository.shared.fetchByKpId(
            kpId: kpId,
            tmdbId: effectiveTmdbId,
            imdbId: effectiveImdbId,
            title: effectiveTitle,
            originalTitle: effectiveOriginal,
            year: effectiveYear
        )

        async let collapsTask = CollapsRepository.shared.fetchMedia(
            kpId: validKp,
            imdbId: effectiveImdbId,
            title: effectiveTitle
        )

        let allohaResult = try? await allohaTask
        let collapsResult = (try? await collapsTask) ?? nil
        let resolvedKp = kpId > 0 ? kpId : (effectiveTmdbId ?? 0)
        let wrapper = SourceResultWrapper(
            allohaResult: allohaResult,
            collapsResult: collapsResult,
            kpId: resolvedKp
        )

        if cacheKey > 0 && (allohaResult != nil || collapsResult != nil) {
            sourcesCache[cacheKey] = (wrapper: wrapper, expiresAt: Date().addingTimeInterval(sourcesCacheTtl))
        }
        self.sourceResultWrapper = wrapper
    }

    private func preferredAllohaTranslation(from movie: AllohaMovie) -> AllohaTranslation? {
        let savedName = UserDefaults.standard.string(forKey: allohaTranslationPreferenceKey)
        return bestTranslation(in: movie.translations, preferredName: savedName)
    }
}

// MARK: - Crew / Creators Section

private struct CrewSection: View {
    let crew: [CrewMemberDto]
    var namespace: Namespace.ID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Создатели")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(crew) { member in
                        let transitionID = "crew_\(member.id)"
                        NavigationLink(
                            destination: PersonDetailView(
                                personId: member.id,
                                initialName: member.name,
                                navigationTransitionID: transitionID,
                                navigationTransitionNamespace: namespace
                            )
                            .navigationBarBackButtonHidden(true)
                        ) {
                            if let namespace {
                                CrewCardView(member: member)
                                    .matchedTransitionSource(id: transitionID, in: namespace)
                            } else {
                                CrewCardView(member: member)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct CrewCardView: View {
    let member: CrewMemberDto

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 76, height: 76)

                if let photo = member.photo, let url = URL(string: photo) {
                    AsyncCachedImage(url: url) {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 76, height: 76)
                            .shimmer()
                    } content: { image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 76, height: 76)
                            .clipShape(Circle())
                    } fallback: {
                        placeholder
                    }
                } else {
                    placeholder
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

            VStack(spacing: 2) {
                Text(member.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)

                if let role = member.role, !role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(role)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 76)
        }
        .frame(width: 76)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 28))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(width: 76, height: 76)
    }
}

// MARK: - Cast / Actors Section

private struct ActorsSection: View {
    let cast: [CastMemberDto]
    var namespace: Namespace.ID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Актёры")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(cast) { actor in
                        let transitionID = "actor_\(actor.id)"
                        NavigationLink(
                            destination: PersonDetailView(
                                personId: actor.id,
                                initialName: actor.name,
                                navigationTransitionID: transitionID,
                                navigationTransitionNamespace: namespace
                            )
                            .navigationBarBackButtonHidden(true)
                        ) {
                            if let namespace {
                                ActorCardView(actor: actor)
                                    .matchedTransitionSource(id: transitionID, in: namespace)
                            } else {
                                ActorCardView(actor: actor)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct ActorCardView: View {
    let actor: CastMemberDto

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 76, height: 76)

                if let photo = actor.photo, let url = URL(string: photo) {
                    AsyncCachedImage(url: url) {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 76, height: 76)
                            .shimmer()
                    } content: { image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 76, height: 76)
                            .clipShape(Circle())
                    } fallback: {
                        placeholder
                    }
                } else {
                    placeholder
                }
            }
            .overlay(
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 3)

            VStack(spacing: 2) {
                Text(actor.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .allowsTightening(true)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)

                if let character = actor.character, !character.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(character)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .allowsTightening(true)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 76)
        }
        .frame(width: 76)
    }

    private var placeholder: some View {
        Image(systemName: "person.fill")
            .font(.system(size: 28))
            .foregroundStyle(Color.white.opacity(0.35))
            .frame(width: 76, height: 76)
    }
}

// MARK: - Trailers Section

private struct TrailersSection: View {
    let trailers: [TrailerVideoDto]
    let onSelect: (TrailerVideoDto) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Трейлеры")
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(trailers) { trailer in
                        Button {
                            onSelect(trailer)
                        } label: {
                            TrailerCardView(trailer: trailer)
                        }
                        .buttonStyle(.glassPress)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

private struct TrailerCardView: View {
    let trailer: TrailerVideoDto

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .center) {
                if let url = trailer.thumbnailUrl {
                    AsyncCachedImage(url: url) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 220, height: 124)
                            .shimmer()
                    } content: { image in
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 220, height: 124)
                            .clipped()
                    } fallback: {
                        fallbackThumbnail
                    }
                } else {
                    fallbackThumbnail
                }

                // Subtle bottom gradient for readability
                LinearGradient(
                    colors: [.clear, .black.opacity(0.45)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                // Centered Liquid Glass Play Badge
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .glassEffect(.regular.interactive(), in: Circle())
                    .shadow(color: Color.black.opacity(0.35), radius: 6, x: 0, y: 3)
            }
            .frame(width: 220, height: 124)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)

            Text(trailer.name)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(width: 220, alignment: .leading)
        }
    }

    private var fallbackThumbnail: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 220, height: 124)
            Image(systemName: "film")
                .font(.system(size: 28))
                .foregroundStyle(Color.white.opacity(0.35))
        }
    }
}

// MARK: - Franchise & Studio Sections

private struct FranchiseCollectionSection: View {
    let collection: MovieCollectionDto
    var onDirectPlay: ((MediaDto) -> Void)? = nil

    var body: some View {
        if let parts = collection.parts, !parts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Все части франшизы")
                        .font(.system(size: 18, weight: .bold))
                    if let name = collection.name, !name.isEmpty {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(parts) { part in
                            NavigationLink(destination: DetailsView(movieId: part.id, mediaType: "movie", navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                                MoviePosterCard(movie: part)
                                    .frame(width: 120)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Group {
                                    Button {
                                        onDirectPlay?(part)
                                    } label: {
                                        Label("Смотреть", systemImage: "play.fill")
                                    }
                                    NavigationLink(destination: DetailsView(movieId: part.id, mediaType: "movie", navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                                        Label("Подробнее", systemImage: "info.circle")
                                    }
                                }
                                .tint(nil)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

private struct RelatedStudioSection: View {
    let response: RelatedStudioResponse
    var onDirectPlay: ((MediaDto) -> Void)? = nil

    var body: some View {
        let items = response.allItems
        if !items.isEmpty {
            let brand = response.label.flatMap { StudioBrand.find(by: $0) }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("Другие релизы")
                        .font(.system(size: 18, weight: .bold))
                    if let label = response.label, !label.isEmpty {
                        NavigationLink(destination: StudioCatalogView(studioId: brand?.id ?? label, studioName: label)) {
                            Text(label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(items) { movie in
                            NavigationLink(destination: DetailsView(movieId: movie.id, mediaType: movie.type, navigationTransitionID: nil, navigationTransitionNamespace: nil, initialStudio: brand).navigationBarBackButtonHidden(true)) {
                                MoviePosterCard(movie: movie)
                                    .frame(width: 120)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Group {
                                    Button {
                                        onDirectPlay?(movie)
                                    } label: {
                                        Label("Смотреть", systemImage: "play.fill")
                                    }
                                    NavigationLink(destination: DetailsView(movieId: movie.id, mediaType: movie.type, navigationTransitionID: nil, navigationTransitionNamespace: nil, initialStudio: brand).navigationBarBackButtonHidden(true)) {
                                        Label("Подробнее", systemImage: "info.circle")
                                    }
                                }
                                .tint(nil)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
    }
}

// MARK: - Similar Media Section

private struct SimilarMediaSection: View {
    let title: String
    let items: [MediaDto]
    var onDirectPlay: ((MediaDto) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(items) { item in
                        NavigationLink(destination: DetailsView(movieId: item.id, mediaType: item.type, navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                            MoviePosterCard(movie: item)
                                .frame(width: 120)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Group {
                                Button {
                                    onDirectPlay?(item)
                                } label: {
                                    Label("Смотреть", systemImage: "play.fill")
                                }
                                NavigationLink(destination: DetailsView(movieId: item.id, mediaType: item.type, navigationTransitionID: nil, navigationTransitionNamespace: nil).navigationBarBackButtonHidden(true)) {
                                    Label("Подробнее", systemImage: "info.circle")
                                }
                            }
                            .tint(nil)
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

struct BlurFadeScaleModifier: ViewModifier {
    let isBlurry: Bool
    func body(content: Content) -> some View {
        content
            .opacity(isBlurry ? 0 : 1)
            .blur(radius: isBlurry ? 8 : 0)
            .scaleEffect(isBlurry ? 0.9 : 1)
    }
}

extension AnyTransition {
    static var blurFadeScale: AnyTransition {
        .modifier(
            active: BlurFadeScaleModifier(isBlurry: true),
            identity: BlurFadeScaleModifier(isBlurry: false)
        )
    }
}
