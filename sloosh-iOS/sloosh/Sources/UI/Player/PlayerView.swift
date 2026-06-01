import SwiftUI
import AVKit

class PlayerPresenterViewController: UIViewController {
    var player: AVPlayer?
    var viewModel: PlayerViewModel?
    var onDismiss: (() -> Void)?
    private var didPresent = false
    private var checkTimer: Timer?
    private var qualityButton: UIButton?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !didPresent, let player = player {
            didPresent = true
            
            // 1. Плавно переводим ориентацию в горизонтальную ТОЛЬКО перед показом самого видео
            AppDelegate.orientationLock = .landscape
            if #available(iOS 16.0, *) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
                }
            } else {
                UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            }
            
            let playerController = AVPlayerViewController()
            playerController.player = player
            playerController.showsPlaybackControls = true
            playerController.allowsPictureInPicturePlayback = true
            
            playerController.modalPresentationStyle = .fullScreen
            
            self.present(playerController, animated: true) {
                player.play()
                self.startDismissalObserver()
                self.setupQualityButton(in: playerController)
                self.setupAudioButton(in: playerController)
            }
        }
    }
    
    private func setupAudioButton(in playerController: AVPlayerViewController) {
        guard let overlay = playerController.contentOverlayView, self.viewModel != nil else { return }
        
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "waveform"), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        btn.layer.cornerRadius = 22
        btn.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(btn)
        
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 16),
            btn.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -112), // To the left of quality button
            btn.widthAnchor.constraint(equalToConstant: 44),
            btn.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        btn.showsMenuAsPrimaryAction = true
        
        // Use an associated object or similar to store the button reference, or just update directly via Notification
        // Since we don't have a property for it, we can just find it later or store it in a closure
        let updateAudioMenu: () -> Void = { [weak btn, weak viewModel] in
            guard let btn = btn, let viewModel = viewModel else { return }
            
            var actions: [UIAction] = []
            for track in viewModel.availableAudioTracks {
                let isSelected = track.id == viewModel.currentAudioTrackId
                let action = UIAction(title: track.name, state: isSelected ? .on : .off) { _ in
                    viewModel.changeAudioTrack(to: track.id)
                    // Notification will trigger re-render
                }
                actions.append(action)
            }
            
            if actions.isEmpty {
                btn.isHidden = true
            } else {
                btn.isHidden = false
                let menu = UIMenu(title: "Озвучка", children: actions)
                btn.menu = menu
            }
        }
        
        updateAudioMenu()
        
        NotificationCenter.default.addObserver(forName: NSNotification.Name("AudioTracksUpdated"), object: nil, queue: .main) { _ in
            updateAudioMenu()
        }
    }
    
    private func setupQualityButton(in playerController: AVPlayerViewController) {
        guard let overlay = playerController.contentOverlayView, self.viewModel != nil else { return }
        
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "slider.horizontal.3"), for: .normal)
        btn.tintColor = .white
        btn.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        btn.layer.cornerRadius = 22
        btn.translatesAutoresizingMaskIntoConstraints = false
        overlay.addSubview(btn)
        
        NSLayoutConstraint.activate([
            btn.topAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.topAnchor, constant: 16),
            btn.trailingAnchor.constraint(equalTo: overlay.safeAreaLayoutGuide.trailingAnchor, constant: -60),
            btn.widthAnchor.constraint(equalToConstant: 44),
            btn.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Setup menu menu
        btn.showsMenuAsPrimaryAction = true
        
        // Update menu dynamically based on viewModel
        self.qualityButton = btn
        updateQualityMenu()
        
        // Listen for changes (using a simple timer or combine observer)
        NotificationCenter.default.addObserver(forName: NSNotification.Name("QualitiesUpdated"), object: nil, queue: .main) { [weak self] _ in
            self?.updateQualityMenu()
        }
    }
    
    private func updateQualityMenu() {
        guard let btn = qualityButton, let viewModel = viewModel else { return }
        
        var actions: [UIAction] = []
        for quality in viewModel.availableQualities {
            let isSelected = quality.key == viewModel.currentQualityKey
            let action = UIAction(title: quality.key, state: isSelected ? .on : .off) { _ in
                viewModel.changeQuality(to: quality.key)
                // Force menu update for checkmark
                DispatchQueue.main.async {
                    self.updateQualityMenu()
                }
            }
            actions.append(action)
        }
        
        if actions.isEmpty {
            btn.isHidden = true
        } else {
            btn.isHidden = false
            let menu = UIMenu(title: "Качество видео", children: actions)
            btn.menu = menu
        }
    }
    
    // 2. Таймер нужен для отлова "жеста смахивания вниз", потому что overFullScreen
    // не вызывает viewDidAppear повторно при закрытии дочернего контроллера
    private func startDismissalObserver() {
        checkTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            if self.presentedViewController == nil {
                timer.invalidate()
                
                // Возвращаем ориентацию обратно
                AppDelegate.orientationLock = .all
                if #available(iOS 16.0, *) {
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
                    }
                } else {
                    UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
                }
                
                self.onDismiss?()
            }
        }
    }
    
    deinit {
        checkTimer?.invalidate()
    }
}

struct ModalPlayerPresenter: UIViewControllerRepresentable {
    var player: AVPlayer
    var viewModel: PlayerViewModel
    var onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> PlayerPresenterViewController {
        let controller = PlayerPresenterViewController()
        controller.view.backgroundColor = .clear
        controller.player = player
        controller.viewModel = viewModel
        controller.onDismiss = onDismiss
        return controller
    }
    
    func updateUIViewController(_ uiViewController: PlayerPresenterViewController, context: Context) {
        uiViewController.player = player
        uiViewController.viewModel = viewModel
        uiViewController.onDismiss = onDismiss
    }
}

struct PlayerView: View {
    let iframeUrl: String?
    let directVideoUrl: String?
    let fallbackTitle: String
    let kpId: Int?
    let season: Int?
    let episode: Int?
    let selectedVoiceover: String?
    let voices: [String]
    let subtitles: [CollapsSubtitle]
    
    @StateObject private var viewModel = PlayerViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    init(iframeUrl: String? = nil, directVideoUrl: String? = nil, fallbackTitle: String, kpId: Int? = nil, season: Int? = nil, episode: Int? = nil, selectedVoiceover: String? = nil, voices: [String] = [], subtitles: [CollapsSubtitle] = []) {
        self.iframeUrl = iframeUrl
        self.directVideoUrl = directVideoUrl
        self.fallbackTitle = fallbackTitle
        self.kpId = kpId
        self.season = season
        self.episode = episode
        self.selectedVoiceover = selectedVoiceover
        self.voices = voices
        self.subtitles = subtitles
    }
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if viewModel.isLoading {
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Поиск видео источника...")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                }
            } else if let error = viewModel.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else if let player = viewModel.player {
                ModalPlayerPresenter(player: player, viewModel: viewModel) {
                    viewModel.cleanup() // Теперь очистка происходит ТОЛЬКО когда плеер реально закрылся
                    presentationMode.wrappedValue.dismiss()
                }
                .edgesIgnoringSafeArea(.all)
            } else {
                Text("Видео не найдено")
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            if viewModel.player == nil { // Избегаем повторной загрузки при перерисовках
                if let directUrl = directVideoUrl {
                    viewModel.loadDirect(url: directUrl, kpId: kpId, season: season, episode: episode, selectedVoiceover: selectedVoiceover, voices: voices, subtitles: subtitles)
                } else if let iframe = iframeUrl {
                    viewModel.load(iframeUrl: iframe, kpId: kpId, season: season, episode: episode, selectedVoiceover: selectedVoiceover, voices: voices, subtitles: subtitles)
                } else {
                    viewModel.error = "Нет URL для воспроизведения"
                    viewModel.isLoading = false
                }
            }
        }
        // Убрали .onDisappear с cleanup, чтобы он не убивал видео при показе плеера
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
    }
}

@MainActor
class PlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isLoading = true
    @Published var error: String?
    
    @Published var availableQualities: [(key: String, url: URL)] = []
    @Published var currentQualityKey: String?
    
    @Published var availableAudioTracks: [(id: String, name: String)] = []
    @Published var currentAudioTrackId: String?
    
    private var resolver: AllohaRuntimeResolver?
    private var resolveTask: Task<Void, Never>?
    private var currentHeaders: [String: String] = [:]
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    
    private var currentKpId: Int?
    private var currentSeason: Int?
    private var currentEpisode: Int?
    private var targetVoiceover: String?

    private func isLocalProxyUrl(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }
    
    func load(iframeUrl: String, kpId: Int?, season: Int?, episode: Int?, selectedVoiceover: String?, voices: [String] = [], subtitles: [CollapsSubtitle] = []) {
        if player != nil { return } // Защита от двойного вызова
        
        self.currentKpId = kpId
        self.currentSeason = season
        self.currentEpisode = episode
        self.targetVoiceover = selectedVoiceover
        
        isLoading = true
        error = nil
        
        startParsing(iframeUrl: iframeUrl, voices: voices, subtitles: subtitles)
    }
    
    func loadDirect(url: String, kpId: Int?, season: Int?, episode: Int?, selectedVoiceover: String?, voices: [String] = [], subtitles: [CollapsSubtitle] = []) {
        if player != nil { return }
        
        self.currentKpId = kpId
        self.currentSeason = season
        self.currentEpisode = episode
        self.targetVoiceover = selectedVoiceover
        
        isLoading = true
        error = nil
        
        guard let parsedUrl = URL(string: url) else {
            self.error = "Некорректный URL"
            self.isLoading = false
            return
        }

        if isLocalProxyUrl(parsedUrl) {
            self.currentHeaders = [:]
            self.currentQualityKey = "Авто"
            self.availableQualities = [("Авто", parsedUrl)]

            let asset = AVURLAsset(url: parsedUrl)
            let playerItem = AVPlayerItem(asset: asset)
            self.player = AVPlayer(playerItem: playerItem)
            self.isLoading = false
            self.startTrackingProgress()
            
            self.itemObservation = playerItem.observe(\.status) { [weak self] item, _ in
                guard let self = self else { return }
                if item.status == .readyToPlay {
                    Task { @MainActor in
                        self.extractAudioTracks(from: item)
                    }
                }
            }

            Task {
                do {
                    let (data, _) = try await URLSession.shared.data(from: parsedUrl)
                    if let content = String(data: data, encoding: .utf8) {
                        parseMasterPlaylist(content: content, baseUrl: parsedUrl)
                    }
                } catch {
                    print("Failed to fetch local master playlist: \(error)")
                }
            }
            return
        }
        
        let headers = [
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
            "Referer": "https://kinokrad.my/",
            "Origin": "https://kinokrad.my"
        ]
        self.currentHeaders = headers
        
        self.currentQualityKey = "Авто"
        self.availableQualities = [("Авто", parsedUrl)]
        
        playVideo(url: parsedUrl, headers: headers, voices: voices, subtitles: subtitles)
        
        // Fetch playlist to parse qualities
        Task {
            do {
                var request = URLRequest(url: parsedUrl)
                headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
                let (data, _) = try await URLSession.shared.data(for: request)
                if let content = String(data: data, encoding: .utf8) {
                    parseMasterPlaylist(content: content, baseUrl: parsedUrl)
                }
            } catch {
                print("Failed to fetch master playlist: \(error)")
            }
        }
    }
    
    private func parseMasterPlaylist(content: String, baseUrl: URL) {
        var qualities: [(key: String, url: URL)] = []
        qualities.append(("Авто", baseUrl))
        
        let lines = content.components(separatedBy: .newlines)
        var currentResolution: String?
        
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                if let range = line.range(of: "RESOLUTION=([^,\\s]+)", options: .regularExpression) {
                    let match = String(line[range])
                    let res = match.replacingOccurrences(of: "RESOLUTION=", with: "")
                    let components = res.components(separatedBy: "x")
                    if components.count == 2, let height = Int(components[1]) {
                        currentResolution = "\(height)p"
                    }
                }
            } else if !line.hasPrefix("#") && !line.isEmpty {
                if let res = currentResolution {
                    let variantUrl: URL
                    if line.hasPrefix("http") {
                        variantUrl = URL(string: line)!
                    } else {
                        variantUrl = URL(string: line, relativeTo: baseUrl)!
                    }
                    if !qualities.contains(where: { $0.key == res }) {
                        qualities.append((res, variantUrl))
                    }
                    currentResolution = nil
                }
            }
        }
        
        if qualities.count > 1 {
            let autoQuality = qualities.removeFirst()
            qualities.sort { (a, b) -> Bool in
                let valA = Int(a.key.replacingOccurrences(of: "p", with: "")) ?? 0
                let valB = Int(b.key.replacingOccurrences(of: "p", with: "")) ?? 0
                return valA > valB
            }
            qualities.insert(autoQuality, at: 0)
            
            DispatchQueue.main.async {
                self.availableQualities = qualities
                NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)
            }
        }
    }
    
    private func startParsing(iframeUrl: String, voices: [String] = [], subtitles: [CollapsSubtitle] = []) {
        resolveTask?.cancel()
        resolver?.cancel()

        let resolver = AllohaRuntimeResolver()
        self.resolver = resolver

        resolveTask = Task { [weak self] in
            do {
                let resolved = try await resolver.resolve(iframeUrl: iframeUrl)
                guard let self, !Task.isCancelled else { return }
                self.applyResolvedAllohaStream(resolved)
            } catch is CancellationError {
                return
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Final progress save before cleanup
        if let player = player, let currentKpId = currentKpId {
            let mediaId: String
            if let season = currentSeason, let episode = currentEpisode {
                mediaId = "kp_\(currentKpId)_s\(season)_e\(episode)"
            } else {
                mediaId = "kp_\(currentKpId)"
            }
            let duration = player.currentItem?.duration.seconds
            CollapsPlaybackProgressStore.shared.save(mediaId: mediaId, positionSec: player.currentTime().seconds, durationSec: duration?.isNaN == false ? duration : nil)
        }

        resolveTask?.cancel()
        resolveTask = nil
        resolver?.cancel()
        resolver = nil
        player?.pause()
        player = nil
        HlsProxyServer.shared.stop()
    }
    
    func changeQuality(to key: String) {
        guard let quality = availableQualities.first(where: { $0.key == key }) else { return }
        self.currentQualityKey = key
        
        let currentTime = player?.currentTime() ?? .zero
        let wasPlaying = player?.timeControlStatus == .playing
        
        let playbackUrl: URL
        if isLocalProxyUrl(quality.url) {
            playbackUrl = quality.url
        } else {
            let absoluteUrlString = quality.url.absoluteString
            guard let encodedData = absoluteUrlString.data(using: .utf8) else { return }
            let encoded = encodedData.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")

            guard let proxyUrl = URL(string: "http://127.0.0.1:\(HlsProxyServer.shared.port.rawValue)/proxy?url=\(encoded)") else { return }
            playbackUrl = proxyUrl
        }

        let asset = AVURLAsset(url: playbackUrl)
        let playerItem = AVPlayerItem(asset: asset)
        
        self.player?.replaceCurrentItem(with: playerItem)
        self.player?.seek(to: currentTime)
        if wasPlaying {
            self.player?.play()
        }
        
        // Re-extract audio tracks for new item and restore selection
        self.itemObservation = playerItem.observe(\.status) { [weak self] item, _ in
            guard let self = self else { return }
            if item.status == .readyToPlay {
                Task { @MainActor in
                    self.extractAudioTracks(from: item)
                }
            }
        }
    }
    
    private func extractAudioTracks(from item: AVPlayerItem) {
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
            
            var tracks: [(id: String, name: String)] = []
            for (index, option) in group.options.enumerated() {
                let id = option.extendedLanguageTag ?? option.locale?.identifier ?? "\(index)"
                tracks.append((id: id, name: option.displayName))
            }
            
            DispatchQueue.main.async {
                self.availableAudioTracks = tracks
                if let current = item.currentMediaSelection.selectedMediaOption(in: group) {
                    self.currentAudioTrackId = current.extendedLanguageTag ?? current.locale?.identifier ?? ""
                }
                
                // Auto-select if targetVoiceover matches any track
                if let voiceover = self.targetVoiceover, !voiceover.isEmpty {
                    // Find best match (ignore case)
                    if let match = group.options.first(where: { $0.displayName.lowercased().contains(voiceover.lowercased()) }) {
                        item.select(match, in: group)
                        self.currentAudioTrackId = match.extendedLanguageTag ?? match.locale?.identifier ?? ""
                        self.targetVoiceover = nil // Only apply once per initial load or quality change if needed, but it's safe to clear
                    }
                } else if let currentTrackId = self.currentAudioTrackId, !currentTrackId.isEmpty {
                    // Restore user selection after quality change
                    if let match = group.options.first(where: { ($0.extendedLanguageTag ?? $0.locale?.identifier ?? "") == currentTrackId }) {
                        item.select(match, in: group)
                    }
                }
                NotificationCenter.default.post(name: NSNotification.Name("AudioTracksUpdated"), object: nil)
            }
        }
    }
    
    func changeAudioTrack(to id: String) {
        guard let item = player?.currentItem else { return }
        
        Task {
            guard let group = try? await item.asset.loadMediaSelectionGroup(for: .audible) else { return }
            
            DispatchQueue.main.async {
                if let match = group.options.first(where: { ($0.extendedLanguageTag ?? $0.locale?.identifier ?? "") == id }) {
                    item.select(match, in: group)
                    self.currentAudioTrackId = id
                    // Update the target voiceover so it persists across quality changes
                    self.targetVoiceover = match.displayName
                }
            }
        }
    }
    
    private func playVideo(url: URL, headers: [String: String], voices: [String] = [], subtitles: [CollapsSubtitle] = []) {
        let absoluteUrlString = url.absoluteString
        guard let encodedData = absoluteUrlString.data(using: .utf8) else {
            self.error = "Ошибка формирования URL"
            self.isLoading = false
            return
        }
        
        let encoded = encodedData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let mediaId: String
        if let kpId = currentKpId {
            if let season = currentSeason, let episode = currentEpisode {
                mediaId = "kp_\(kpId)_s\(season)_e\(episode)"
            } else {
                mediaId = "kp_\(kpId)"
            }
        } else {
            mediaId = "unknown"
        }
        
        HlsProxyServer.shared.start(headers: headers, voices: voices, subtitles: subtitles, mediaId: mediaId)
        
        guard let proxyUrl = URL(string: "http://127.0.0.1:\(HlsProxyServer.shared.port.rawValue)/proxy?url=\(encoded)") else {
            self.error = "Ошибка формирования URL"
            self.isLoading = false
            return
        }
        
        let asset = AVURLAsset(url: proxyUrl)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        self.isLoading = false
        self.startTrackingProgress()
        
        self.itemObservation = playerItem.observe(\.status) { [weak self] item, _ in
            guard let self = self else { return }
            if item.status == .readyToPlay {
                Task { @MainActor in
                    self.extractAudioTracks(from: item)
                }
            }
        }
    }
    
    private func startTrackingProgress() {
        guard let player = player else { return }
        
        let mediaId: String
        if let kpId = currentKpId {
            if let season = currentSeason, let episode = currentEpisode {
                mediaId = "kp_\(kpId)_s\(season)_e\(episode)"
            } else {
                mediaId = "kp_\(kpId)"
            }
        } else {
            return
        }
        
        let savedPosition = CollapsPlaybackProgressStore.shared.load(mediaId: mediaId)
        if savedPosition > 0 {
            player.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 600))
        }
        
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 5, preferredTimescale: 600), queue: .main) { [weak self, weak player] time in
            guard let _ = self, let player = player else { return }
            let duration = player.currentItem?.duration.seconds
            CollapsPlaybackProgressStore.shared.save(mediaId: mediaId, positionSec: time.seconds, durationSec: duration?.isNaN == false ? duration : nil)
        }
    }

    private func applyResolvedAllohaStream(_ resolved: [String: Any]) {
        guard let resolvedUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let resolvedUrl = URL(string: resolvedUrlString) else {
            self.error = "Не удалось извлечь ссылку на видео"
            self.isLoading = false
            return
        }

        let headers = (resolved["headers"] as? [String: String]) ?? [:]
        currentHeaders = headers

        var qualities = [(key: "Авто", url: resolvedUrl)]
        var seenKeys = Set<String>(["Авто"])

        let qualityVariants = (resolved["qualityVariants"] as? [[String: Any]]) ?? []
        appendQualityVariants(qualityVariants, to: &qualities, seenKeys: &seenKeys)

        if qualities.count == 1,
           let audioVariants = resolved["audioVariants"] as? [[String: Any]],
           let firstAudio = audioVariants.first,
           let nestedQualityVariants = firstAudio["qualityVariants"] as? [[String: Any]] {
            appendQualityVariants(nestedQualityVariants, to: &qualities, seenKeys: &seenKeys)
        }

        if qualities.count > 1 {
            let autoQuality = qualities.removeFirst()
            qualities.sort { (a, b) -> Bool in
                let valA = Int(a.key.replacingOccurrences(of: "p", with: "")) ?? 0
                let valB = Int(b.key.replacingOccurrences(of: "p", with: "")) ?? 0
                return valA > valB
            }
            qualities.insert(autoQuality, at: 0)
        }

        availableQualities = qualities
        currentQualityKey = "Авто"
        playVideo(url: resolvedUrl, headers: headers)
        NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)
    }

    private func appendQualityVariants(_ variants: [[String: Any]], to qualities: inout [(key: String, url: URL)], seenKeys: inout Set<String>) {
        for variant in variants {
            guard let urlString = variant["url"] as? String,
                  let url = URL(string: urlString),
                  !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let label = normalizedQualityLabel(from: variant["label"] as? String)
            guard seenKeys.insert(label).inserted else { continue }
            qualities.append((key: label, url: url))
        }
    }

    private func normalizedQualityLabel(from rawLabel: String?) -> String {
        let label = (rawLabel ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return "Поток" }
        if label.lowercased().hasSuffix("p") { return label }
        if Int(label) != nil { return "\(label)p" }
        return label
    }
}
