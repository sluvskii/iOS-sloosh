import SwiftUI
import AVKit

class PlayerPresenterViewController: UIViewController {
    var player: AVPlayer? {
        didSet {
            if playerController?.player !== player {
                playerController?.player = player
            }
            if player != nil && player?.timeControlStatus != .playing {
                player?.play()
            }
        }
    }
    var viewModel: PlayerViewModel?
    
    var onDismiss: (() -> Void)?
    private var didPresent = false
    private var playerController: AVPlayerViewController?
    private var observation: NSKeyValueObservation?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if !didPresent {
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
            
            let pc = AVPlayerViewController()
            pc.player = player
            pc.showsPlaybackControls = true
            pc.allowsPictureInPicturePlayback = true
            pc.modalPresentationStyle = .fullScreen
            self.playerController = pc
            
            self.present(pc, animated: true) {
                self.player?.play()
            }
        } else {
            // Если мы вернулись на этот экран и плеера больше нет (смахнули вниз)
            if self.presentedViewController == nil {
                handleDismissal()
            }
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Ensure dismiss is called only when the view controller is ACTUALLY being dismissed from SwiftUI
        // or when the child AVPlayerViewController has been fully dismissed
        if self.isBeingDismissed || self.isMovingFromParent || (self.presentedViewController == nil && self.didPresent) {
            handleDismissal()
        }
    }
    
    private func handleDismissal() {
        // Restore orientation
        AppDelegate.orientationLock = .all
        if #available(iOS 16.0, *) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            }
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
        
        onDismiss?()
    }
    
    deinit {
        observation?.invalidate()
    }
}

struct ModalPlayerPresenter: UIViewControllerRepresentable {
    var player: AVPlayer?
    var viewModel: PlayerViewModel
    var onDismiss: () -> Void
    
    class Coordinator: NSObject {
        var didDismiss = false
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeUIViewController(context: Context) -> PlayerPresenterViewController {
        let controller = PlayerPresenterViewController()
        controller.view.backgroundColor = .clear
        controller.player = player
        controller.viewModel = viewModel
        controller.onDismiss = {
            DispatchQueue.main.async {
                if !context.coordinator.didDismiss {
                    context.coordinator.didDismiss = true
                    onDismiss()
                }
            }
        }
        return controller
    }
    
    func updateUIViewController(_ uiViewController: PlayerPresenterViewController, context: Context) {
        uiViewController.player = player
        uiViewController.viewModel = viewModel
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
    
    let initialQuality: VideoQualityPreference?
    
    @StateObject private var viewModel = PlayerViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    init(iframeUrl: String? = nil, directVideoUrl: String? = nil, fallbackTitle: String, kpId: Int? = nil, season: Int? = nil, episode: Int? = nil, selectedVoiceover: String? = nil, voices: [String] = [], subtitles: [CollapsSubtitle] = [], initialQuality: VideoQualityPreference? = nil) {
        self.iframeUrl = iframeUrl
        self.directVideoUrl = directVideoUrl
        self.fallbackTitle = fallbackTitle
        self.kpId = kpId
        self.season = season
        self.episode = episode
        self.selectedVoiceover = selectedVoiceover
        self.voices = voices
        self.subtitles = subtitles
        self.initialQuality = initialQuality
    }
    
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
                    viewModel.cleanup()
                    presentationMode.wrappedValue.dismiss()
                }
            } else if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
            } else {
                ModalPlayerPresenter(player: viewModel.player, viewModel: viewModel) {
                    viewModel.cleanup() // Теперь очистка происходит ТОЛЬКО когда плеер реально закрылся
                    presentationMode.wrappedValue.dismiss()
                }
                .edgesIgnoringSafeArea(.all)
            }
        }
        .onAppear {
            if viewModel.player == nil { // Избегаем повторной загрузки при перерисовках
                viewModel.player = AVPlayer() // СРАЗУ СОЗДАЕМ ПЛЕЕР, ЧТОБЫ AVPlayerViewController ПОЛУЧИЛ ЕГО ПРИ СТАРТЕ
                viewModel.targetQualityPreference = initialQuality
                
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
    
    private var resolver: AllohaRuntimeResolver?
    private var resolveTask: Task<Void, Never>?
    private var currentHeaders: [String: String] = [:]
    private var timeObserver: Any?
    private var itemObservation: NSKeyValueObservation?
    
    private var currentKpId: Int?
    private var currentSeason: Int?
    private var currentEpisode: Int?
    private var currentSourcePreferenceKey: String?
    private var targetVoiceover: String?
    var targetQualityPreference: VideoQualityPreference?
    private var hasStartedLoading = false

    private func isLocalProxyUrl(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "127.0.0.1" || host == "localhost"
    }
    
    func load(iframeUrl: String, kpId: Int?, season: Int?, episode: Int?, selectedVoiceover: String?, voices: [String] = [], subtitles: [CollapsSubtitle] = []) {
        if hasStartedLoading { return } // Защита от двойного вызова
        hasStartedLoading = true
        
        self.currentKpId = kpId
        self.currentSeason = season
        self.currentEpisode = episode
        self.currentSourcePreferenceKey = "alloha"
        self.targetVoiceover = selectedVoiceover
        
        isLoading = true
        error = nil
        
        startParsing(iframeUrl: iframeUrl, voices: voices, subtitles: subtitles)
    }
    
    func loadDirect(url: String, kpId: Int?, season: Int?, episode: Int?, selectedVoiceover: String?, voices: [String] = [], subtitles: [CollapsSubtitle] = []) {
        if hasStartedLoading { return }
        hasStartedLoading = true
        
        self.currentKpId = kpId
        self.currentSeason = season
        self.currentEpisode = episode
        self.currentSourcePreferenceKey = "collaps"
        self.targetVoiceover = selectedVoiceover
        
        isLoading = true
        error = nil
        
        guard let parsedUrl = URL(string: url) else {
            self.error = "Некорректный URL"
            self.isLoading = false
            return
        }

        self.currentHeaders = [:]
        self.currentQualityKey = "Авто"
        self.availableQualities = [("Авто", parsedUrl)]

        playVideo(url: parsedUrl, headers: [:], voices: voices, subtitles: subtitles)

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
    }
    
    private func parseMasterPlaylist(content: String, baseUrl: URL) {
        var qualities: [(key: String, url: URL)] = []
        qualities.append(("Авто", baseUrl))
        
        let lines = content.components(separatedBy: .newlines)
        var currentResolution: String?
        
        for line in lines {
            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                var resStr = "Поток"
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
                    if let bandwidth = Int(bw) {
                        resStr = "\(bandwidth / 1000) kbps"
                    }
                }
                currentResolution = resStr
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
                    } else {
                        // Prevent duplicate keys
                        let uniqueRes = "\(res) (\(qualities.count))"
                        qualities.append((uniqueRes, variantUrl))
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
        hasStartedLoading = false
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
        if currentSourcePreferenceKey == "collaps" {
            playbackUrl = quality.url
        } else {
            let absoluteUrlString = quality.url.absoluteString
            guard let encodedData = absoluteUrlString.data(using: .utf8) else { return }
            let encoded = encodedData.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")

            let ext = quality.url.pathExtension
            let pathSuffix = ext.isEmpty ? "stream.m3u8" : "stream.\(ext)"

            guard let proxyUrl = URL(string: "http://127.0.0.1:\(HlsProxyServer.shared.port.rawValue)/proxy/\(pathSuffix)?url=\(encoded)") else { return }
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
            
            DispatchQueue.main.async {
                if let targetVoice = self.targetVoiceover, !targetVoice.isEmpty {
                    if let match = group.options.first(where: { $0.displayName.lowercased() == targetVoice.lowercased() }) {
                        item.select(match, in: group)
                        self.persistVoiceoverSelection(match.displayName)
                        return
                    }
                }
                
                let savedVoiceover = self.loadSavedVoiceover()
                if let saved = savedVoiceover, !saved.isEmpty {
                    if let match = group.options.first(where: { $0.displayName.lowercased() == saved.lowercased() }) {
                        item.select(match, in: group)
                        return
                    }
                }
                
                self.persistCurrentVoiceoverSelection(from: item)
            }
        }
    }
    
    private func loadSavedVoiceover() -> String? {
        guard let kpId = currentKpId,
              let source = currentSourcePreferenceKey else {
            return nil
        }
        return CollapsPlaybackProgressStore.shared.loadLastVoiceover(kpId: kpId, source: source)
    }
    
    private func playVideo(url: URL, headers: [String: String], voices: [String] = [], subtitles: [CollapsSubtitle] = []) {
        if currentSourcePreferenceKey == "collaps" {
            let asset = AVURLAsset(url: url)
            let playerItem = AVPlayerItem(asset: asset)
            
            if self.player == nil { self.player = AVPlayer() }
            self.player?.replaceCurrentItem(with: playerItem)
            self.player?.automaticallyWaitsToMinimizeStalling = true
            
            self.isLoading = false
            self.startTrackingProgress()
            self.player?.play()
            
            self.itemObservation = playerItem.observe(\.status) { [weak self] item, _ in
                guard let self = self else { return }
                if item.status == .readyToPlay {
                    Task { @MainActor in
                        self.extractAudioTracks(from: item)
                    }
                }
            }
            return
        }

        let absoluteUrlString = url.absoluteString
        guard let encodedData = absoluteUrlString.data(using: .utf8) else {
            self.error = "Ошибка формирования URL"
            self.isLoading = false
            return
        }
        
        // Use URL Safe Base64 without padding (same as proxy implementation)
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
        
        let ext = url.pathExtension
        let pathSuffix = ext.isEmpty ? "stream.m3u8" : "stream.\(ext)"
        
        guard let proxyUrl = URL(string: "http://127.0.0.1:\(HlsProxyServer.shared.port.rawValue)/proxy/\(pathSuffix)?url=\(encoded)") else {
            self.error = "Ошибка формирования URL"
            self.isLoading = false
            return
        }
        
        let asset = AVURLAsset(url: proxyUrl)
        let playerItem = AVPlayerItem(asset: asset)
        
        if self.player == nil { self.player = AVPlayer() }
        self.player?.replaceCurrentItem(with: playerItem)
        self.player?.automaticallyWaitsToMinimizeStalling = true
        
        self.isLoading = false
        self.startTrackingProgress()
        self.player?.play()
        
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
            guard let self = self, let player = player else { return }
            let duration = player.currentItem?.duration.seconds
            CollapsPlaybackProgressStore.shared.save(mediaId: mediaId, positionSec: time.seconds, durationSec: duration?.isNaN == false ? duration : nil)
            if let item = player.currentItem {
                self.persistCurrentVoiceoverSelection(from: item)
            }
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
        let resolvedVoices = resolvedVoiceovers(from: resolved)
        let resolvedSubtitles = resolvedSubtitles(from: resolved)

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
        playVideo(url: resolvedUrl, headers: headers, voices: resolvedVoices, subtitles: resolvedSubtitles)
        NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)
        applyInitialQuality()
    }

    private func resolvedVoiceovers(from resolved: [String: Any]) -> [String] {
        let variants = (resolved["audioVariants"] as? [[String: Any]]) ?? []
        var seen = Set<String>()
        return variants.compactMap { variant in
            let title = (variant["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !title.isEmpty else { return nil }
            return seen.insert(title).inserted ? title : nil
        }
    }

    private func resolvedSubtitles(from resolved: [String: Any]) -> [CollapsSubtitle] {
        let subtitles = (resolved["subtitles"] as? [[String: Any]]) ?? []
        return subtitles.compactMap { item in
            let url = ((item["url"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty else { return nil }
            let label = ((item["label"] as? String) ?? (item["name"] as? String) ?? "Субтитры")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let language = ((item["language"] as? String) ?? (item["lang"] as? String) ?? "ru")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return CollapsSubtitle(
                url: url,
                label: label.isEmpty ? "Субтитры" : label,
                lang: language.isEmpty ? "ru" : language
            )
        }
    }

    private func persistCurrentVoiceoverSelection(from item: AVPlayerItem) {
        guard let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .audible),
              let selectedOption = item.currentMediaSelection.selectedMediaOption(in: group) else {
            return
        }
        persistVoiceoverSelection(selectedOption.displayName)
    }

    private func persistVoiceoverSelection(_ name: String?) {
        guard let kpId = currentKpId,
              let source = currentSourcePreferenceKey else {
            return
        }
        CollapsPlaybackProgressStore.shared.saveLastVoiceover(kpId: kpId, source: source, voiceover: name)
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
