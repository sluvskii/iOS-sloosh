import SwiftUI

struct AboutView: View {
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
                        .font(.system(size: 24, weight: .bold))
                    Text("Приложение для просмотра фильмов и сериалов с современным iOS-интерфейсом.")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                    Text("Версия \(appVersion)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 6)
            }

            Section("Технологии") {
                Label("SwiftUI интерфейс", systemImage: "swift")
                Label("AVPlayer для воспроизведения", systemImage: "play.rectangle")
                Label("Адаптивный интерфейс для iPhone", systemImage: "iphone")
                Label("Быстрая навигация по каталогу", systemImage: "magnifyingglass")
            }
            .foregroundColor(.secondary)
        }
        .navigationTitle("О приложении")
        .navigationBarTitleDisplayMode(.inline)
    }
}
