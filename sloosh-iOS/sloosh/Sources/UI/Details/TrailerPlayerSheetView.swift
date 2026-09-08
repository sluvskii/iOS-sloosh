import SwiftUI
import WebKit

// MARK: - In-App Trailer Player Sheet (Liquid Glass)

struct TrailerPlayerSheetView: View {
    let trailer: TrailerVideoDto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Video Player Container (16:9 ratio, immediately full width)
                    ZStack {
                        Color.black

                        TrailerWebView(trailer: trailer)
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.35), radius: 12, x: 0, y: 6)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                    // Trailer Title (Clean, symmetrical, uniform 16pt padding)
                    Text(trailer.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 16)

                    // Primary Action Button: Open in YouTube
                    if let appUrl = trailer.youtubeAppUrl, let webUrl = trailer.youtubeWebUrl {
                        Button {
                            if UIApplication.shared.canOpenURL(appUrl) {
                                UIApplication.shared.open(appUrl)
                            } else {
                                UIApplication.shared.open(webUrl)
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.right.video.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                Text("Открыть в YouTube")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Трейлер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Кнопка закрытия (без вложенного glassEffect, чтобы не двоилась)
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .tint(.white)
                }

                // Кнопка «Поделиться» сверху в шапке
                ToolbarItem(placement: .primaryAction) {
                    if let webUrl = trailer.youtubeWebUrl {
                        ShareLink(item: webUrl) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .tint(.white)
                    }
                }
            }
        }
        .presentationDetents([.height(420), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
    }
}

// MARK: - Native WebKit YouTube Trailer Player

struct TrailerWebView: UIViewRepresentable {
    let trailer: TrailerVideoDto

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.layer.cornerRadius = 16
        webView.layer.masksToBounds = true

        loadContent(in: webView)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op to avoid reloading during sheet gestures
    }

    private func loadContent(in webView: WKWebView) {
        let videoKey = trailer.key
        let embedUrlString = "https://www.youtube-nocookie.com/embed/\(videoKey)?autoplay=1&playsinline=1&rel=0&modestbranding=1&controls=1&iv_load_policy=3"

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                html, body {
                    width: 100%;
                    height: 100%;
                    background-color: #000000;
                    overflow: hidden;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                }
                iframe {
                    position: absolute;
                    top: 0;
                    left: 0;
                    width: 100%;
                    height: 100%;
                    border: none;
                }
            </style>
        </head>
        <body>
            <iframe 
                src="\(embedUrlString)" 
                title="Trailer" 
                frameborder="0" 
                allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" 
                allowfullscreen>
            </iframe>
        </body>
        </html>
        """

        webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }
}
