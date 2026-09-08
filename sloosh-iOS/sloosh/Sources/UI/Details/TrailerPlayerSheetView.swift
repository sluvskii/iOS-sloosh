import SwiftUI
import WebKit

// MARK: - In-App Trailer Player Sheet (Liquid Glass)

struct TrailerPlayerSheetView: View {
    let trailer: TrailerVideoDto
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Video Player Container (16:9 ratio)
                ZStack {
                    Color.black

                    TrailerWebView(trailer: trailer)
                }
                .aspectRatio(16 / 9, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 16, x: 0, y: 8)
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // Trailer Info & Action Bar
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(trailer.typeTag.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Color.slooshAccent)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.slooshAccent.opacity(0.15))
                                .clipShape(Capsule())

                            if trailer.isYouTube {
                                HStack(spacing: 4) {
                                    Image(systemName: "play.rectangle.fill")
                                        .font(.system(size: 12))
                                    Text("YouTube")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                        }

                        Text(trailer.name)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(3)
                    }

                    Divider()
                        .background(Color.white.opacity(0.1))

                    // Secondary actions: Open in YouTube & Share
                    HStack(spacing: 12) {
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
                                        .font(.system(size: 14, weight: .semibold))
                                    Text("Открыть в YouTube")
                                        .font(.system(size: 14, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .glassEffect(.regular.interactive(), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }

                        if let webUrl = trailer.youtubeWebUrl {
                            ShareLink(item: webUrl) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 44, height: 44)
                                    .glassEffect(.regular.interactive(), in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .navigationTitle("Трейлер")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 30, height: 30)
                            .glassEffect(.regular.interactive(), in: Circle())
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
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
