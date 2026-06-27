import SwiftUI

struct SettingsView: View {
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    @AppStorage("autoplayNextEpisode") private var autoplayNextEpisode = true
    @AppStorage("tabBarShowsLabels") private var tabBarShowsLabels = false
    
    var body: some View {
        NavigationStack {
            List {
                Section("Интерфейс") {
                    Toggle("Показывать подписи вкладок", isOn: $tabBarShowsLabels)
                }

                Section("Воспроизведение") {
                    Picker("Качество видео", selection: $preferredQuality) {
                        ForEach(VideoQualityPreference.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }

                    Toggle("Автопереход к следующей серии", isOn: $autoplayNextEpisode)
                }

                Section("О приложении") {
                    NavigationLink("О приложении") {
                        AboutView()
                    }
                }
            }
            .navigationTitle("Настройки")
        }
    }
}
