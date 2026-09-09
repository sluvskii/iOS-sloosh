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
                    ForEach(VideoQualityPreference.allCases.filter { $0 != .ask }) { quality in
                        Button {
                            selectedQuality = quality
                        } label: {
                            HStack {
                                Text(quality.title)
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
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    if rememberChoice {
                        preferredQuality = selectedQuality
                    }
                    onSelect(selectedQuality)
                }) {
                    HStack(spacing: 8) {
                        Text("Продолжить")
                            .font(.system(size: 19, weight: .heavy))
                    }
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 26)
                    .frame(height: 50)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.94))
                    )
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(.glassPress)
                .padding(.bottom, 8)
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .presentationDetents([.medium, .large])
        .presentationBackground { Color.clear.glassEffect(in: .rect) }
        .presentationDragIndicator(.visible)
    }
}
