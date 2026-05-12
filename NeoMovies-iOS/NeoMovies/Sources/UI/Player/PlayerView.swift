import SwiftUI
import AVKit

struct PlayerView: View {
    let kpId: Int?
    let fallbackTitle: String
    
    @StateObject private var viewModel = PlayerViewModel()
    @Environment(\.presentationMode) var presentationMode
    
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
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .onAppear {
                        player.play()
                    }
                    .onDisappear {
                        player.pause()
                    }
            } else {
                Text("Видео не найдено")
                    .foregroundColor(.white)
            }
            
            // Custom Back Button Overlay
            VStack {
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    .padding(.top, 40) // SafeArea top inset approx for landscape
                    .padding(.leading, 20)
                    Spacer()
                }
                Spacer()
            }
        }
        .onAppear {
            if let kpId = kpId {
                viewModel.loadAlloha(kpId: kpId)
            } else {
                viewModel.error = "Кинопоиск ID не найден для этого фильма"
                viewModel.isLoading = false
            }
            AppDelegate.orientationLock = .landscape
            if #available(iOS 16.0, *) {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
            } else {
                UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
            }
        }
        .onDisappear {
            viewModel.cleanup()
            AppDelegate.orientationLock = .all
            if #available(iOS 16.0, *) {
                guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
            } else {
                UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
            }
        }
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
    
    func loadAlloha(kpId: Int) {
        isLoading = true
        error = nil
        
        Task {
            do {
                let result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId)
                var iframeUrl: String?
                if result.isSerial, let firstSeason = result.seasons.first, let firstEp = firstSeason.episodes.first, let trans = firstEp.translations.first {
                    iframeUrl = trans.iframeUrl
                } else if let movie = result.movie {
                    iframeUrl = movie.iframeUrl
                }
                
                guard let url = iframeUrl else {
                    self.error = "Видео недоступно для просмотра"
                    self.isLoading = false
                    return
                }
                
                self.startParsing(iframeUrl: url)
            } catch {
                self.error = "Ошибка загрузки: \(error.localizedDescription)"
                self.isLoading = false
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
