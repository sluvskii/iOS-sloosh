import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Воспроизведение") {
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
