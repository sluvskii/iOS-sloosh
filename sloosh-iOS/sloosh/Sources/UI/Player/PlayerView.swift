import SwiftUI
import AVKit


struct PlayerView: View {
    let iframeUrl: String?
    let fallbackTitle: String
    let kpId: Int?
    let season: Int?
    let episode: Int?
    let selectedVoiceover: String?
    /// Pre-resolved direct stream URL. When set, skips iframe resolution and name-matching.
    let directStreamUrl: String?
    let voices: [String]
    let subtitles: [PlaybackSubtitle]
    let initialQuality: VideoQualityPreference?
    let seriesResult: AllohaApiResult?
    
    @StateObject private var viewModel = PlayerViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    init(iframeUrl: String? = nil, fallbackTitle: String, kpId: Int? = nil, season: Int? = nil, episode: Int? = nil, selectedVoiceover: String? = nil, directStreamUrl: String? = nil, voices: [String] = [], subtitles: [PlaybackSubtitle] = [], initialQuality: VideoQualityPreference? = nil, seriesResult: AllohaApiResult? = nil) {
        self.iframeUrl = iframeUrl
        self.fallbackTitle = fallbackTitle
        self.kpId = kpId
        self.season = season
        self.episode = episode
        self.selectedVoiceover = selectedVoiceover
        self.directStreamUrl = directStreamUrl
        self.voices = voices
        self.subtitles = subtitles
        self.initialQuality = initialQuality
        self.seriesResult = seriesResult
    }
    
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if let error = viewModel.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    Text("Нажмите, чтобы закрыть")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.white.opacity(0.6))
                        .padding(.top, 8)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissPlayer()
                }
            } else {
                CustomVideoPlayer(viewModel: viewModel)
                    .edgesIgnoringSafeArea(.all)
                
                PlayerControlsOverlay(
                    viewModel: viewModel,
                    title: fallbackTitle,
                    onClose: dismissPlayer,
                    onSettings: { showSettings = true }
                )
            }
        }
        .sheet(isPresented: $showSettings) {
            // Placeholder for settings sheet (qualities, subtitles, voiceovers)
            // Can be expanded later. For now, we'll re-use the UI from before if needed.
            PlayerSettingsView(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            if viewModel.player == nil { 
                viewModel.player = AVPlayer() 
                viewModel.targetQualityPreference = initialQuality
                viewModel.seriesResult = seriesResult
                
                if iframeUrl != nil || directStreamUrl != nil {
                    viewModel.load(iframeUrl: iframeUrl, kpId: kpId, season: season, episode: episode, selectedVoiceover: selectedVoiceover, directStreamUrl: directStreamUrl, voices: voices, subtitles: subtitles)
                } else {
                    viewModel.error = "Нет URL для воспроизведения"
                    viewModel.isLoading = false
                }
            }
            
            // Force landscape when opening
            AppDelegate.orientationLock = .landscape
            if #available(iOS 16.0, *) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
                }
            } else {
                UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            }
        }
        .navigationBarHidden(true)
        .navigationBarBackButtonHidden(true)
        .statusBarHidden(true)
    }
    
    private func dismissPlayer() {
        // Force portrait when closing
        AppDelegate.orientationLock = .portrait
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
        
        viewModel.cleanup()
        presentationMode.wrappedValue.dismiss()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            AppDelegate.orientationLock = .all
            if #available(iOS 16.0, *) {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }
}

// Temporary placeholder for settings
struct PlayerSettingsView: View {
    @ObservedObject var viewModel: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Качество видео")) {
                    ForEach(viewModel.availableQualities, id: \.key) { q in
                        Button(action: {
                            viewModel.changeQuality(to: q.key)
                            dismiss()
                        }) {
                            HStack {
                                Text(q.key)
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.currentQualityKey == q.key {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }
}

@MainActor
class PlayerViewModel: ObservableObject {
    struct PlaybackQualityOption {
        let key: String
        let url: URL
        let preferredPeakBitRate: Double?
        let isAuto: Bool
        let shouldReloadOnSelect: Bool
    }

    @Published var player: AVPlayer?
    @Published var isLoading = true
    @Published var error: String?
    
    @Published var availableQualities: [PlaybackQualityOption] = []
    @Published var currentQualityKey: String?
    
    // Custom Player UI State
    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var showControls: Bool = true
    @Published var isPiPActive: Bool = false
    var pipController: AVPictureInPictureController?
    
    private var controlsHideTimer: Timer?
    
    // UI Helpers
    func togglePlayPause() {
        guard let player = player else { return }
        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }
        resetControlsTimer()
    }
    
    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        resetControlsTimer()
    }
    
    func seekBy(_ seconds: Double) {
        let newTime = max(0, min(currentTime + seconds, duration))
        seek(to: newTime)
    }
    
    func resetControlsTimer() {
        controlsHideTimer?.invalidate()
        showControls = true
        if isPlaying {
            setupControlsTimer()
        }
    }
    
    private func setupControlsTimer() {
        controlsHideTimer?.invalidate()
        controlsHideTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isPlaying else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    self.showControls = false
                }
            }
        }
    }
    
    private var resolver: AllohaRuntimeResolver?
    private var resolveTask: Task<Void, Never>?
    private var currentHeaders: [String: String] = [:]
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    private var playbackEndObserver: NSObjectProtocol?
    private var resignActiveObserver: NSObjectProtocol?
    private var currentPlaybackSourceURL: URL?
    
    private var currentKpId: Int?
    private var currentSeason: Int?
    private var currentEpisode: Int?
    private var targetVoiceover: String?
    private var currentTranslationName: String?
    /// Pre-resolved direct stream URL; bypasses audioVariant matching when set.
    private var targetDirectStreamUrl: String?
    private var isAdvancingToNextEpisode = false

    var targetQualityPreference: VideoQualityPreference?
    var seriesResult: AllohaApiResult?
    private var hasStartedLoading = false

    private var autoplayNextEpisodeEnabled: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "autoplayNextEpisode") == nil {
            return true
        }
        return defaults.bool(forKey: "autoplayNextEpisode")
    }

    private func isLocalProxyUrl(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }
    
    func load(iframeUrl: String?, kpId: Int?, season: Int?, episode: Int?, selectedVoiceover: String?, directStreamUrl: String? = nil, voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
        if hasStartedLoading { return } // Защита от двойного вызова
        hasStartedLoading = true
        beginLoad(iframeUrl: iframeUrl, kpId: kpId, season: season, episode: episode, selectedVoiceover: selectedVoiceover, directStreamUrl: directStreamUrl, voices: voices, subtitles: subtitles)
    }

    private func beginLoad(iframeUrl: String?, kpId: Int?, season: Int?, episode: Int?, selectedVoiceover: String?, directStreamUrl: String? = nil, voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
        self.currentKpId = kpId
        self.currentSeason = season
        self.currentEpisode = episode
        self.targetVoiceover = selectedVoiceover
        self.currentTranslationName = selectedVoiceover
        self.targetDirectStreamUrl = directStreamUrl
        self.isAdvancingToNextEpisode = false

        if kpId != nil, let selectedVoiceover, !selectedVoiceover.isEmpty {
            persistVoiceoverSelection(selectedVoiceover)
        }
        
        isLoading = true
        error = nil
        
        if let directUrlString = directStreamUrl, let directUrl = URL(string: directUrlString) {
            // Direct HLS playback (local file URL)
            availableQualities = [
                PlaybackQualityOption(
                    key: "Локальный",
                    url: directUrl,
                    preferredPeakBitRate: nil,
                    isAuto: false,
                    shouldReloadOnSelect: false
                )
            ]
            currentQualityKey = "Локальный"
            playVideo(url: directUrl, headers: [:], voices: [], subtitles: [])
        } else if let iframe = iframeUrl {
            startParsing(iframeUrl: iframe, voices: voices, subtitles: subtitles)
        } else {
            error = "Нет URL для воспроизведения"
            isLoading = false
        }
    }
    
    private func parseMasterPlaylist(content: String, baseUrl: URL) {
        var qualities: [PlaybackQualityOption] = [
            PlaybackQualityOption(
                key: "Авто",
                url: baseUrl,
                preferredPeakBitRate: nil,
                isAuto: true,
                shouldReloadOnSelect: false
            )
        ]
        
        let lines = content.components(separatedBy: .newlines)
        var currentResolution: String?
        var currentBandwidth: Double?
        
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                var resStr = "Поток"
                currentBandwidth = nil
                if let range = line.range(of: "RESOLUTION=([^,\\s]+)", options: .regularExpression) {
                    let match = String(line[range])
                    let res = match.replacingOccurrences(of: "RESOLUTION=", with: "")
                    let components = res.components(separatedBy: "x")
                    if components.count == 2, let height = Int(components[1]) {
                        resStr = "\(height)p"
                    }
                } else if let range = line.range(of: "BANDWIDTH=([^,\\s]+)", options: .regularExpression) {
                    let match = String(line[range])
                    let bw = match.replacingOccurrences(of: "BANDWIDTH=", with: "")
                    if let bandwidth = Double(bw) {
                        currentBandwidth = bandwidth
                        resStr = "\(bandwidth / 1000) kbps"
                    }
                }
                currentResolution = resStr
            } else if !line.hasPrefix("#") && !line.isEmpty {
                if let res = currentResolution {
                    let variantUrl: URL
                    if line.hasPrefix("http") {
                        variantUrl = URL(string: line)!.absoluteURL
                    } else {
                        variantUrl = URL(string: line, relativeTo: baseUrl)!.absoluteURL
                    }
                    if !qualities.contains(where: { $0.key == res }) {
                        qualities.append(
                            PlaybackQualityOption(
                                key: res,
                                url: variantUrl,
                                preferredPeakBitRate: currentBandwidth,
                                isAuto: false,
                                shouldReloadOnSelect: false
                            )
                        )
                    } else {
                        // Prevent duplicate keys
                        let uniqueRes = "\(res) (\(qualities.count))"
                        qualities.append(
                            PlaybackQualityOption(
                                key: uniqueRes,
                                url: variantUrl,
                                preferredPeakBitRate: currentBandwidth,
                                isAuto: false,
                                shouldReloadOnSelect: false
                            )
                        )
                    }
                    currentResolution = nil
                    currentBandwidth = nil
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
                self.applyInitialQuality()
            }
        }
    }
    
    private func applyInitialQuality() {
        // Read global preference or the one passed from the sheet
        let prefRaw = UserDefaults.standard.string(forKey: "preferredVideoQuality") ?? VideoQualityPreference.ask.rawValue
        let globalPref = VideoQualityPreference(rawValue: prefRaw) ?? .ask
        let targetQuality = self.targetQualityPreference ?? globalPref
        
        guard targetQuality != .ask && targetQuality != .auto else { return }
        
        let targetKey = targetQuality.rawValue
        
        // Exact match (1080p -> 1080p)
        if let exact = availableQualities.first(where: { $0.key.hasPrefix(targetKey) }) {
            changeQuality(to: exact.key)
            return
        }
        
        // Find closest resolution
        let prefVal = Int(targetKey.replacingOccurrences(of: "p", with: "")) ?? 0
        guard prefVal > 0 else { return }
        
        var closest: String?
        var minDiff = Int.max
        for q in availableQualities {
            let val = Int(q.key.replacingOccurrences(of: "p", with: "")) ?? 0
            if val > 0 {
                let diff = abs(val - prefVal)
                if diff < minDiff {
                    minDiff = diff
                    closest = q.key
                }
            }
        }
        
        if let closestKey = closest {
            changeQuality(to: closestKey)
        }
    }
    
    private func startParsing(iframeUrl: String, voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
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
        hasStartedLoading = false
        currentPlaybackSourceURL = nil
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
            self.resignActiveObserver = nil
        }
        itemObservation?.invalidate()
        itemObservation = nil
        
        // Final progress save before cleanup
        saveCurrentProgress()

        resolveTask?.cancel()
        resolveTask = nil
        resolver?.cancel()
        resolver = nil
        player?.pause()
        player = nil
        HlsProxyServer.shared.stop()
        
        controlsHideTimer?.invalidate()
        controlsHideTimer = nil
        pipController?.stopPictureInPicture()
        pipController = nil
    }

    /// Сохраняет текущую позицию воспроизведения. Вызывается и по таймеру, и при сворачивании приложения.
    private func saveCurrentProgress() {
        guard let player = player, let currentKpId = currentKpId else { return }
        let mediaId: String
        if let season = currentSeason, let episode = currentEpisode {
            mediaId = "kp_\(currentKpId)_s\(season)_e\(episode)"
        } else {
            mediaId = "kp_\(currentKpId)"
        }
        let duration = player.currentItem?.duration.seconds
        PlaybackProgressStore.shared.save(
            mediaId: mediaId,
            positionSec: player.currentTime().seconds,
            durationSec: duration?.isNaN == false ? duration : nil
        )
    }
    
    func changeQuality(to key: String) {
        guard let quality = availableQualities.first(where: { $0.key == key }) else { return }
        self.currentQualityKey = key
        
        let isHls = quality.url.pathExtension.lowercased() == "m3u8" || quality.url.absoluteString.contains(".m3u8")
        
        if quality.isAuto {
            if shouldReloadForAutoSelection(autoURL: quality.url) {
                reloadPlayback(to: quality.url, preferredPeakBitRate: 0)
            } else {
                player?.currentItem?.preferredPeakBitRate = 0
            }
            return
        }

        if quality.shouldReloadOnSelect {
            reloadPlayback(to: quality.url, preferredPeakBitRate: quality.preferredPeakBitRate)
            return
        }

        if isHls, let currentItem = self.player?.currentItem {
            currentItem.preferredPeakBitRate = resolvedBitrate(for: quality)
            return
        }

        reloadPlayback(to: quality.url, preferredPeakBitRate: quality.preferredPeakBitRate)
    }

    private func reloadPlayback(to sourceURL: URL, preferredPeakBitRate: Double?) {
        let currentTime = player?.currentTime() ?? .zero
        let wasPlaying = player?.timeControlStatus == .playing

        let asset: AVURLAsset
        if sourceURL.isFileURL {
            asset = AVURLAsset(url: sourceURL)
        } else {
            guard let proxyUrl = proxiedPlaybackURL(for: sourceURL) else { return }
            asset = AVURLAsset(url: proxyUrl)
        }

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredPeakBitRate = max(0, preferredPeakBitRate ?? 0)
        currentPlaybackSourceURL = sourceURL.absoluteURL

        itemObservation?.invalidate()
        itemObservation = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }

        self.player?.replaceCurrentItem(with: playerItem)
        self.player?.seek(to: currentTime)
        if wasPlaying {
            self.player?.play()
        }
        observePlaybackCompletion(for: playerItem)

        self.itemObservation = playerItem.observe(\.status) { _, _ in }
    }

    private func proxiedPlaybackURL(for sourceURL: URL) -> URL? {
        let absoluteUrlString = sourceURL.absoluteURL.absoluteString
        guard let encodedData = absoluteUrlString.data(using: .utf8) else { return nil }
        let encoded = encodedData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let ext = sourceURL.pathExtension
        let pathSuffix = ext.isEmpty ? "stream.m3u8" : "stream.\(ext)"

        return URL(string: "http://127.0.0.1:\(HlsProxyServer.shared.port.rawValue)/proxy/\(pathSuffix)?url=\(encoded)")
    }

    private func shouldReloadForAutoSelection(autoURL: URL) -> Bool {
        guard let currentPlaybackSourceURL else { return false }
        return currentPlaybackSourceURL.absoluteURL.absoluteString != autoURL.absoluteURL.absoluteString
    }

    private func resolvedBitrate(for quality: PlaybackQualityOption) -> Double {
        if let preferredPeakBitRate = quality.preferredPeakBitRate, preferredPeakBitRate > 0 {
            return preferredPeakBitRate
        }

        let height = Int(quality.key.replacingOccurrences(of: "p", with: "")) ?? 0
        switch height {
        case 1080...: return 8_000_000
        case 720..<1080: return 4_000_000
        case 480..<720: return 2_000_000
        case 360..<480: return 1_000_000
        case 1..<360: return 700_000
        default: return 0
        }
    }

    private func bitrateValue(from variant: [String: Any]) -> Double? {
        if let bitrate = variant["bitrate"] as? Double, bitrate > 0 { return bitrate }
        if let bitrate = variant["bitrate"] as? NSNumber, bitrate.doubleValue > 0 { return bitrate.doubleValue }
        if let bandwidth = variant["bandwidth"] as? Double, bandwidth > 0 { return bandwidth }
        if let bandwidth = variant["bandwidth"] as? NSNumber, bandwidth.doubleValue > 0 { return bandwidth.doubleValue }
        return nil
    }

    private func absoluteQualityURL(from rawURL: String) -> URL? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)?.absoluteURL
    }

    private func makeQualityOption(
        key: String,
        url: URL,
        preferredPeakBitRate: Double?,
        isAuto: Bool,
        shouldReloadOnSelect: Bool
    ) -> PlaybackQualityOption {
        PlaybackQualityOption(
            key: key,
            url: url.absoluteURL,
            preferredPeakBitRate: preferredPeakBitRate,
            isAuto: isAuto,
            shouldReloadOnSelect: shouldReloadOnSelect
        )
    }

    private func makeAutoQualityOption(url: URL) -> PlaybackQualityOption {
        makeQualityOption(
            key: "Авто",
            url: url,
            preferredPeakBitRate: nil,
            isAuto: true,
            shouldReloadOnSelect: false
        )
    }

    private func makeResolvedQualityOption(label: String, url: URL, preferredPeakBitRate: Double?) -> PlaybackQualityOption {
        makeQualityOption(
            key: label,
            url: url,
            preferredPeakBitRate: preferredPeakBitRate,
            isAuto: false,
            shouldReloadOnSelect: true
        )
    }

    private func makeMasterPlaylistQualityOption(label: String, url: URL, preferredPeakBitRate: Double?) -> PlaybackQualityOption {
        makeQualityOption(
            key: label,
            url: url,
            preferredPeakBitRate: preferredPeakBitRate,
            isAuto: false,
            shouldReloadOnSelect: false
        )
    }

    private func makeResolvedQualityOptions(
        resolvedUrl: URL,
        qualityVariants: [[String: Any]],
        audioVariants: [[String: Any]]
    ) -> [PlaybackQualityOption] {
        var qualities = [makeAutoQualityOption(url: resolvedUrl)]
        var seenKeys = Set<String>(["Авто"])

        appendQualityVariants(qualityVariants, to: &qualities, seenKeys: &seenKeys)

        if qualities.count == 1,
           let firstAudio = audioVariants.first,
           let nestedQualityVariants = firstAudio["qualityVariants"] as? [[String: Any]] {
            appendQualityVariants(nestedQualityVariants, to: &qualities, seenKeys: &seenKeys)
        }

        if qualities.count > 1 {
            let autoQuality = qualities.removeFirst()
            qualities.sort { lhs, rhs in
                let valA = Int(lhs.key.replacingOccurrences(of: "p", with: "")) ?? 0
                let valB = Int(rhs.key.replacingOccurrences(of: "p", with: "")) ?? 0
                return valA > valB
            }
            qualities.insert(autoQuality, at: 0)
        }

        return qualities
    }
    
    
    private func playVideo(url: URL, headers: [String: String], voices: [String] = [], subtitles: [PlaybackSubtitle] = []) {
        currentPlaybackSourceURL = url.absoluteURL

        let asset: AVURLAsset
        if url.absoluteString.contains("127.0.0.1") || url.absoluteString.contains("localhost") {
            HlsProxyServer.shared.start(headers: [:], voices: [], subtitles: [], mediaId: "local")
            asset = AVURLAsset(url: url)
        } else if url.isFileURL {
            asset = AVURLAsset(url: url)
        } else {
            guard let proxyUrl = proxiedPlaybackURL(for: url) else {
                self.error = "Ошибка формирования URL"
                self.isLoading = false
                return
            }
            
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
            asset = AVURLAsset(url: proxyUrl)
        }
        
        let playerItem = AVPlayerItem(asset: asset)
        itemObservation?.invalidate()
        itemObservation = nil
        if let playbackEndObserver {
            NotificationCenter.default.removeObserver(playbackEndObserver)
            self.playbackEndObserver = nil
        }
        
        if self.player == nil { self.player = AVPlayer() }
        self.player?.replaceCurrentItem(with: playerItem)
        self.player?.automaticallyWaitsToMinimizeStalling = true
        

        
        observePlaybackCompletion(for: playerItem)
        
        self.isLoading = false
        self.startTrackingProgress()
        self.player?.play()
        self.isPlaying = true
        
        self.itemObservation = playerItem.observe(\.status) { _, _ in }
        
        // Setup state observers
        NotificationCenter.default.addObserver(forName: AVPlayer.rateDidChangeNotification, object: self.player, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let player = self.player else { return }
                self.isPlaying = player.rate != 0
            }
        }
        
        setupControlsTimer()
    }
    
    private func startTrackingProgress() {
        guard let player = player else { return }
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
        
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
        
        let savedPosition = PlaybackProgressStore.shared.load(mediaId: mediaId)
        if savedPosition > 0 {
            player.seek(to: CMTime(seconds: savedPosition, preferredTimescale: 600))
        }
        
        // Set high-frequency time observer for the custom UI scrubber
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self, weak player] time in
            Task { @MainActor [weak self, weak player] in
                guard let self = self, let player = player else { return }
                
                let seconds = time.seconds
                self.currentTime = seconds.isNaN ? 0 : seconds
                
                let dur = player.currentItem?.duration.seconds
                self.duration = (dur?.isNaN == false) ? dur! : 0
                
                self.isBuffering = player.currentItem?.isPlaybackBufferEmpty ?? false
                
                // Save progress to store less frequently
                if Int(seconds) % 5 == 0 {
                    let durToSave = self.duration > 0 ? self.duration : nil
                    PlaybackProgressStore.shared.save(mediaId: mediaId, positionSec: seconds, durationSec: durToSave)
                }
            }
        }

        // Сохраняем прогресс немедленно при сворачивании — даже если система потом убьёт процесс
        if let existing = resignActiveObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveCurrentProgress()
            }
        }
    }

    private func observePlaybackCompletion(for item: AVPlayerItem) {
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handlePlaybackEnded()
            }
        }
    }

    private func handlePlaybackEnded() async {
        guard autoplayNextEpisodeEnabled,
              !isAdvancingToNextEpisode,
              let nextEpisode = nextEpisodeCandidate() else {
            return
        }

        isAdvancingToNextEpisode = true
        defer { isAdvancingToNextEpisode = false }

        currentSeason = nextEpisode.season
        currentEpisode = nextEpisode.episode
        currentTranslationName = nextEpisode.translation.name
        targetVoiceover = nextEpisode.translation.name

        if let kpId = currentKpId {
            PlaybackProgressStore.shared.saveLastPlayed(kpId: kpId, season: nextEpisode.season, episode: nextEpisode.episode)
        }

        beginLoad(
            iframeUrl: nextEpisode.translation.iframeUrl,
            kpId: currentKpId,
            season: nextEpisode.season,
            episode: nextEpisode.episode,
            selectedVoiceover: nextEpisode.translation.name
        )
    }

    private func nextEpisodeCandidate() -> (season: Int, episode: Int, translation: AllohaTranslation)? {
        guard let seriesResult, seriesResult.isSerial,
              let currentSeason, let currentEpisode else {
            return nil
        }

        let sortedSeasons = seriesResult.seasons.sorted { $0.season < $1.season }
        var foundCurrentEpisode = false

        for season in sortedSeasons {
            for episode in season.episodes.sorted(by: { $0.episode < $1.episode }) {
                if foundCurrentEpisode {
                    guard let translation = preferredTranslation(in: episode) else { return nil }
                    return (season.season, episode.episode, translation)
                }

                if season.season == currentSeason && episode.episode == currentEpisode {
                    foundCurrentEpisode = true
                }
            }
        }

        return nil
    }

    private func preferredTranslation(in episode: AllohaEpisode) -> AllohaTranslation? {
        if let currentTranslationName,
           let exactMatch = episode.translations.first(where: { allohaTranslationNamesMatch($0.name, currentTranslationName) }) {
            return exactMatch
        }

        if let targetVoiceover,
           let voiceMatch = episode.translations.first(where: { allohaTranslationNamesMatch($0.name, targetVoiceover) }) {
            return voiceMatch
        }

        return episode.translations.first
    }

    private func applyResolvedAllohaStream(_ resolved: [String: Any]) {
        var resolvedUrlString = (resolved["url"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let audioVariants = (resolved["audioVariants"] as? [[String: Any]]) ?? []

        if let directUrl = targetDirectStreamUrl, !directUrl.isEmpty {
            // Pre-resolved URL stored at fetch time: use directly, no name matching needed.
            resolvedUrlString = directUrl
        } else {
            // Pick the URL for the selected voiceover from audioVariants by name.
            // Exact match first, then fuzzy.
            let voiceToMatch = targetVoiceover ?? currentTranslationName
            if let voiceToMatch, !voiceToMatch.isEmpty {
                let exactMatch = audioVariants.first(where: { variant in
                    let title = variant["title"] as? String
                    return allohaTranslationNamesMatch(title, voiceToMatch, exactOnly: true)
                })
                let match = exactMatch ?? audioVariants.first(where: { variant in
                    let title = variant["title"] as? String
                    return allohaTranslationNamesMatch(title, voiceToMatch, exactOnly: false)
                })
                if let validMatch = match, let matchedUrl = validMatch["url"] as? String, !matchedUrl.isEmpty {
                    resolvedUrlString = matchedUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        guard let resolvedUrl = URL(string: resolvedUrlString) else {
            self.error = "Не удалось извлечь ссылку на видео"
            self.isLoading = false
            return
        }

        let headers = (resolved["headers"] as? [String: String]) ?? [:]
        currentHeaders = headers
        let resolvedSubtitles = resolvedSubtitles(from: resolved)

        let qualityVariants = (resolved["qualityVariants"] as? [[String: Any]]) ?? []

        availableQualities = makeResolvedQualityOptions(
            resolvedUrl: resolvedUrl,
            qualityVariants: qualityVariants,
            audioVariants: audioVariants
        )
        currentQualityKey = "Авто"
        playVideo(url: resolvedUrl, headers: headers, voices: [], subtitles: resolvedSubtitles)
        NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)
        applyInitialQuality()
    }

    private func resolvedVoiceovers(from resolved: [String: Any]) -> [String] {
        let variants = (resolved["audioVariants"] as? [[String: Any]]) ?? []
        var seen = Set<String>()
        return variants.compactMap { variant in
            let title = (variant["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }
            let cleanTitle = normalizedAllohaTranslationName(title).isEmpty ? title : normalizedAllohaTranslationName(title)
            return seen.insert(cleanTitle).inserted ? cleanTitle : nil
        }
    }

    private func resolvedSubtitles(from resolved: [String: Any]) -> [PlaybackSubtitle] {
        let subtitles = (resolved["subtitles"] as? [[String: Any]]) ?? []
        return subtitles.compactMap { item in
            let url = ((item["url"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            let label = ((item["label"] as? String) ?? (item["name"] as? String) ?? "Субтитры")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let language = ((item["language"] as? String) ?? (item["lang"] as? String) ?? "ru")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return PlaybackSubtitle(
                url: url,
                label: label.isEmpty ? "Субтитры" : label,
                lang: language.isEmpty ? "ru" : language
            )
        }
    }


    private func persistVoiceoverSelection(_ name: String?) {
        guard let kpId = currentKpId else { return }
        let normalized = normalizedAllohaTranslationName(name)
        let finalName = normalized.isEmpty ? name : normalized
        PlaybackProgressStore.shared.saveLastVoiceover(
            kpId: kpId,
            source: "alloha",
            voiceover: finalName
        )
        if let finalName, !finalName.isEmpty {
            UserDefaults.standard.set(finalName, forKey: "alloha_last_translation_name")
        }
    }

    private func appendQualityVariants(_ variants: [[String: Any]], to qualities: inout [PlaybackQualityOption], seenKeys: inout Set<String>) {
        for variant in variants {
            guard let urlString = variant["url"] as? String,
                  let url = absoluteQualityURL(from: urlString) else {
                continue
            }
            let label = normalizedQualityLabel(from: variant["label"] as? String)
            guard seenKeys.insert(label).inserted else { continue }
            qualities.append(
                makeResolvedQualityOption(
                    label: label,
                    url: url,
                    preferredPeakBitRate: bitrateValue(from: variant)
                )
            )
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
