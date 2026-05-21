import SwiftUI
import AVKit

class PlayerPresenterViewController: UIViewController {
    var player: AVPlayer?
    var onDismiss: (() -> Void)?
    private var didPresent = false
    private var checkTimer: Timer?
    
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
            
            // ВАЖНО: Используем fullScreen вместо overFullScreen!
            // overFullScreen заставляет родительский контроллер оставаться в иерархии вьюх, 
            // что ломает логику SwiftUI .onDisappear. Но если использовать просто fullScreen, 
            // SwiftUI может вызвать onDisappear слишком рано и убить сервер.
            // Чтобы этого избежать, мы перенесем cleanup сервера из onDisappear 
            // непосредственно в логику закрытия плеера (onDismiss).
            playerController.modalPresentationStyle = .fullScreen
            
            self.present(playerController, animated: true) {
                player.play()
                self.startDismissalObserver()
            }
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
    var onDismiss: () -> Void
    
    func makeUIViewController(context: Context) -> PlayerPresenterViewController {
        let controller = PlayerPresenterViewController()
        controller.view.backgroundColor = .clear
        controller.player = player
        controller.onDismiss = onDismiss
        return controller
    }
    
    func updateUIViewController(_ uiViewController: PlayerPresenterViewController, context: Context) {
        uiViewController.player = player
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
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
            } else if let error = viewModel.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.red)
                    Text(error)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
            } else if let player = viewModel.player {
                ModalPlayerPresenter(player: player) {
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
    
    private var parser: AllohaParser?
    
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
        
        let asset = AVURLAsset(url: parsedUrl)
        let playerItem = AVPlayerItem(asset: asset)
        self.player = AVPlayer(playerItem: playerItem)
        self.isLoading = false
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
               let quality = firstSource["quality"] as? [String: String],
               let firstQualityKey = quality.keys.first,
               let urlString = quality[firstQualityKey]?.components(separatedBy: " or ").first,
               let url = URL(string: urlString) {
                
                playVideo(url: url, headers: extraHeaders)
            } else {
                self.error = "Не удалось извлечь ссылку на видео"
                self.isLoading = false
            }
        } catch {
            self.error = "Ошибка парсинга: \(error.localizedDescription)"
            self.isLoading = false
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
