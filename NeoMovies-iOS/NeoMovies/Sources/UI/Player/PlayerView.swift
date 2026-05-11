import SwiftUI
import WebKit

struct PlayerView: View {
    let kpId: Int?
    let fallbackTitle: String
    
    @StateObject private var viewModel = PlayerViewModel()
    
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
            } else if let urlString = viewModel.iframeUrl, let url = URL(string: urlString) {
                WebView(url: url)
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text("Видео не найдено")
                    .foregroundColor(.white)
            }
        }
        .onAppear {
            if let kpId = kpId {
                Task {
                    await viewModel.loadAlloha(kpId: kpId)
                }
            } else {
                viewModel.error = "Кинопоиск ID не найден для этого фильма"
                viewModel.isLoading = false
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

@MainActor
class PlayerViewModel: ObservableObject {
    @Published var iframeUrl: String?
    @Published var isLoading = true
    @Published var error: String?
    
    func loadAlloha(kpId: Int) async {
        isLoading = true
        error = nil
        
        do {
            let result = try await AllohaRepository.shared.fetchByKpId(kpId: kpId)
            if result.isSerial, let firstSeason = result.seasons.first, let firstEp = firstSeason.episodes.first, let trans = firstEp.translations.first {
                self.iframeUrl = trans.iframeUrl
            } else if let movie = result.movie {
                self.iframeUrl = movie.iframeUrl
            } else {
                self.error = "Видео недоступно для просмотра"
            }
        } catch {
            self.error = "Ошибка загрузки: \(error.localizedDescription)"
        }
        
        isLoading = false
    }
}

struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        webView.load(request)
    }
}
