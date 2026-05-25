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
            }
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
    
    @StateObject private var viewModel = PlayerViewModel()
    @Environment(\.presentationMode) var presentationMode
    
    init(iframeUrl: String? = nil, directVideoUrl: String? = nil, fallbackTitle: String) {
        self.iframeUrl = iframeUrl
        self.directVideoUrl = directVideoUrl
        self.fallbackTitle = fallbackTitle
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
                    viewModel.loadDirect(url: directUrl)
                } else if let iframe = iframeUrl {
                    viewModel.load(iframeUrl: iframe)
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
class PlayerViewModel: ObservableObject, AllohaParserDelegate {
    @Published var player: AVPlayer?
    @Published var isLoading = true
    @Published var error: String?
    
    @Published var availableQualities: [(key: String, url: URL)] = []
    @Published var currentQualityKey: String?
    
    private var parser: AllohaParser?
    private var currentHeaders: [String: String] = [:]
    
    func load(iframeUrl: String) {
        if player != nil { return } // Защита от двойного вызова
        
        isLoading = true
        error = nil
        
        startParsing(iframeUrl: iframeUrl)
    }
    
    func loadDirect(url: String) {
        if player != nil { return }
        
        isLoading = true
        error = nil
        
        guard let parsedUrl = URL(string: url) else {
            self.error = "Некорректный URL"
            self.isLoading = false
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
        
        playVideo(url: parsedUrl, headers: headers)
        
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
    
    private func startParsing(iframeUrl: String) {
        parser = AllohaParser()
        parser?.delegate = self
        parser?.parse(iframeUrl: iframeUrl)
    }
    
    func cleanup() {
        player?.pause()
        player = nil
        parser?.release()
        parser = nil
        HlsProxyServer.shared.stop()
    }
    
    // MARK: - AllohaParserDelegate
    
    func onHlsLinksReceived(json: String, extraHeaders: [String : String]) {
        do {
            if let data = json.data(using: .utf8),
               let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hlsSource = dict["hlsSource"] as? [[String: Any]],
               let firstSource = hlsSource.first,
               let quality = firstSource["quality"] as? [String: String] {
                
                self.currentHeaders = extraHeaders
                
                // Parse all available qualities
                var parsedQualities: [(key: String, url: URL)] = []
                for (key, urlString) in quality {
                    if let realUrlString = urlString.components(separatedBy: " or ").first,
                       let url = URL(string: realUrlString) {
                        parsedQualities.append((key: key, url: url))
                    }
                }
                
                // Sort qualities descending (e.g. 1080p, 720p, 480p)
                parsedQualities.sort { (a, b) -> Bool in
                    let valA = Int(a.key.replacingOccurrences(of: "p", with: "")) ?? 0
                    let valB = Int(b.key.replacingOccurrences(of: "p", with: "")) ?? 0
                    return valA > valB
                }
                
                self.availableQualities = parsedQualities
                
                if let firstQuality = parsedQualities.first {
                    self.currentQualityKey = firstQuality.key
                    playVideo(url: firstQuality.url, headers: extraHeaders)
                    NotificationCenter.default.post(name: NSNotification.Name("QualitiesUpdated"), object: nil)
                } else {
                    self.error = "Не удалось извлечь ссылку на видео"
                    self.isLoading = false
                }
            } else {
                self.error = "Не удалось извлечь ссылку на видео"
                self.isLoading = false
            }
        } catch {
            self.error = "Ошибка парсинга: \(error.localizedDescription)"
            self.isLoading = false
        }
    }
    
    func changeQuality(to key: String) {
        guard let quality = availableQualities.first(where: { $0.key == key }) else { return }
        self.currentQualityKey = key
        
        let currentTime = player?.currentTime() ?? .zero
        let wasPlaying = player?.timeControlStatus == .playing
        
        let absoluteUrlString = quality.url.absoluteString
        guard let encodedData = absoluteUrlString.data(using: .utf8) else { return }
        let encoded = encodedData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        // Update the proxy if needed (HlsProxyServer should handle new URL just fine since it's stateless per url parameter)
        guard let proxyUrl = URL(string: "http://127.0.0.1:\(HlsProxyServer.shared.port.rawValue)/proxy?url=\(encoded)") else { return }
        
        let asset = AVURLAsset(url: proxyUrl)
        let playerItem = AVPlayerItem(asset: asset)
        
        self.player?.replaceCurrentItem(with: playerItem)
        self.player?.seek(to: currentTime)
        if wasPlaying {
            self.player?.play()
        }
    }
    
    func onConfigUpdate(edgeHash: String, ttlSeconds: Int, extraHeaders: [String : String]) {
        // Ignored for simple AVPlayer, AVPlayer handles streams automatically
    }
    
    func onM3u8Refreshed(url: String, extraHeaders: [String : String]) {
        // Ignored for simple AVPlayer
    }
    
    func onStreamHeadersUpdated(extraHeaders: [String : String]) {
        // Ignored for simple AVPlayer
    }
    
    func onError(error: String) {
        self.error = error
        self.isLoading = false
    }
    
    private func playVideo(url: URL, headers: [String: String]) {
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
        
        HlsProxyServer.shared.start(headers: headers)
        
        guard let proxyUrl = URL(string: "http://127.0.0.1:\(HlsProxyServer.shared.port.rawValue)/proxy?url=\(encoded)") else {
            self.error = "Ошибка формирования URL"
            self.isLoading = false
            return
        }
        
        let asset = AVURLAsset(url: proxyUrl)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        self.isLoading = false
    }
}
