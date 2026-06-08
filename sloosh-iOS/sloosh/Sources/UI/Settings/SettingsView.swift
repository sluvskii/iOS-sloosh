import SwiftUI

struct SettingsView: View {
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    
    var body: some View {
        NavigationStack {
            List {
                Section("Воспроизведение") {
                    Picker("Качество видео", selection: $preferredQuality) {
                        ForEach(VideoQualityPreference.allCases) { quality in
                            Text(quality.rawValue).tag(quality)
                        }
                    }
                    
                    NavigationLink("Источники") {
                        SourceSettingsView()
                    }
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
