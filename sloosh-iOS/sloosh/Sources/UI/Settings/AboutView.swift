import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }

    var body: some View {
        List {
            Section("О приложении") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("sloosh")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("Премиальный клиент для просмотра фильмов и сериалов с фокусом на современный iOS-интерфейс.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    Text("Версия \(appVersion)")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Ссылки") {
                Button("Telegram-канал") {
                    open("https://t.me/neomovies_news")
                }
                Button("Последний релиз Android") {
                    open("https://github.com/Neo-Open-Source/neomovies-android/releases/latest")
                }
                Button("Все релизы") {
                    open("https://github.com/Neo-Open-Source/neomovies-android/releases")
                }
            }

            Section("Технологии") {
                Label("SwiftUI интерфейс", systemImage: "swift")
                Label("AVPlayer для воспроизведения", systemImage: "play.rectangle")
                Label("WKWebView + HLS proxy для Alloha", systemImage: "network")
                Label("Collaps и Alloha sources", systemImage: "antenna.radiowaves.left.and.right")
            }
            .foregroundColor(.secondary)
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func open(_ rawUrl: String) {
        guard let url = URL(string: rawUrl) else { return }
        openURL(url)
    }
}
