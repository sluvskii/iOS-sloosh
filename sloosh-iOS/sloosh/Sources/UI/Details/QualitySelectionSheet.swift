import SwiftUI

struct QualitySelectionSheet: View {
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    
    @State private var selectedQuality: VideoQualityPreference = .auto
    @State private var rememberChoice: Bool = false
    
    let onSelect: (VideoQualityPreference) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach([VideoQualityPreference.auto, .q1080, .q720, .q480, .q360]) { quality in
                        Button {
                            selectedQuality = quality
                        } label: {
                            HStack {
                                Text(quality.rawValue)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedQuality == quality {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section {
                    Toggle("Запомнить выбор", isOn: $rememberChoice)
                        .tint(.blue)
                } footer: {
                    Text("Вы всегда можете изменить качество по умолчанию в настройках.")
                }
            }
            .navigationTitle("Качество видео")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button(action: {
                        if rememberChoice {
                            preferredQuality = selectedQuality
                        }
                        onSelect(selectedQuality)
                    }) {
                        Text("Продолжить")
                            .font(.system(size: 17, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .buttonBorderShape(.capsule)
                    .tint(.primary)
                    .foregroundStyle(Color(UIColor.systemBackground))
                    .padding(.horizontal)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
