import SwiftUI

struct SettingsView: View {
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    @AppStorage("autoplayNextEpisode") private var autoplayNextEpisode = true
    @AppStorage("tabBarShowsLabels") private var tabBarShowsLabels = false
    @State private var tabBarShowsLabelsDraft = false
    @State private var applyTabBarLabelsTask: Task<Void, Never>?
    
    var body: some View {
        List {
            Section("Интерфейс") {
                Toggle("Показывать подписи вкладок", isOn: $tabBarShowsLabelsDraft)
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
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            tabBarShowsLabelsDraft = tabBarShowsLabels
        }
        .onChange(of: tabBarShowsLabels) { _, newValue in
            if tabBarShowsLabelsDraft != newValue {
                tabBarShowsLabelsDraft = newValue
            }
        }
        .onChange(of: tabBarShowsLabelsDraft) { _, newValue in
            applyTabBarLabelsTask?.cancel()
            applyTabBarLabelsTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                tabBarShowsLabels = newValue
            }
        }
        .onDisappear {
            applyTabBarLabelsTask?.cancel()
        }
    }
}
