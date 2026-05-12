import SwiftUI

struct SourceSettingsView: View {
    @ObservedObject var sourceManager = SourceManager.shared
    
    var body: some View {
        Form {
            Section(header: Text("Выбор источника")) {
                Picker("", selection: $sourceManager.currentMode) {
                    ForEach(SourceMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        .navigationTitle("Источники")
        .navigationBarTitleDisplayMode(.inline)
    }
}
