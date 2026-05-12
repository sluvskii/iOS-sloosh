import SwiftUI

struct SourceSettingsView: View {
    @ObservedObject var sourceManager = SourceManager.shared
    
    var body: some View {
        Form {
            Section(header: Text("Выбор источника")) {
                Picker("Текущий источник", selection: $sourceManager.currentMode) {
                    ForEach(SourceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }
        }
        .navigationTitle("Источники")
        .navigationBarTitleDisplayMode(.inline)
    }
}
