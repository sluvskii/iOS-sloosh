import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Воспроизведение") {
                    NavigationLink("Источники") {
                        SourceSettingsView()
                    }
                    NavigationLink("Настройки плеера") {
                        PlayerSettingsPlaceholderView()
                    }
                }

                Section("О приложении") {
                    NavigationLink("О sloosh") {
                        AboutView()
                    }
                    NavigationLink("Изменения") {
                        ChangesView()
                    }
                    NavigationLink("Благодарности") {
                        CreditsView()
                    }
                }
            }
            .navigationTitle("Настройки")
        }
    }
}

private struct PlayerSettingsPlaceholderView: View {
    var body: some View {
        List {
            Section("Плеер") {
                Label("Сейчас используется нативный AVPlayer", systemImage: "play.rectangle.fill")
                Label("Поддерживается fullscreen и смена ориентации", systemImage: "iphone.landscape")
                Label("Alloha работает через встроенный parser и HLS proxy", systemImage: "network")
            }

            Section("План развития") {
                Text("Дальше сюда можно аккуратно добавить сохранение позиции, предпочитаемое качество, автозапуск следующей серии и другие playback-настройки.")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Плеер")
        .navigationBarTitleDisplayMode(.inline)
    }
}
