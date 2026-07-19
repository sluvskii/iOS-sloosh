import SwiftUI
import AVFoundation

struct QualitySelectionSheet: View {
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    
    @State private var selectedQuality: VideoQualityPreference = .auto
    @State private var rememberChoice: Bool = false
    @State private var showWarningAlert: Bool = false
    @State private var pendingWarningQuality: VideoQualityPreference? = nil
    
    var isForDownload: Bool = false
    let onSelect: (VideoQualityPreference) -> Void
    
    private var availableQualities: [VideoQualityPreference] {
        let base = VideoQualityPreference.allCases.filter { $0 != .ask }
        if isForDownload {
            return base
        } else {
            return AVURLAsset.isAV1Supported ? base : base.filter { $0 != .q2160 && $0 != .q1440 }
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(availableQualities) { quality in
                        let isWarning = isForDownload && !AVURLAsset.isAV1Supported && (quality == .q2160 || quality == .q1440)
                        
                        Button {
                            if isWarning {
                                pendingWarningQuality = quality
                                showWarningAlert = true
                            } else {
                                selectedQuality = quality
                            }
                        } label: {
                            HStack {
                                Text(quality.title)
                                    .foregroundColor(.primary)
                                if isWarning {
                                    Spacer()
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                }
                                Spacer()
                                if selectedQuality == quality {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                if !isForDownload {
                    Section {
                        Toggle("Запомнить выбор", isOn: $rememberChoice)
                            .tint(.blue)
                    } footer: {
                        Text("Вы всегда можете изменить качество по умолчанию в настройках.")
                    }
                }
            }
            .navigationTitle(isForDownload ? "Качество для загрузки" : "Качество видео")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: {
                    if !isForDownload && rememberChoice {
                        preferredQuality = selectedQuality
                    }
                    onSelect(selectedQuality)
                }) {
                    HStack(spacing: 8) {
                        Text(isForDownload ? "Скачать" : "Продолжить")
                            .font(.system(size: 19, weight: .heavy))
                    }
                    .frame(height: 50)
                    .padding(.horizontal, 24)
                }
                .buttonStyle(GlassPlayButtonStyle())
                .padding(.bottom, 8)
            }
            .alert("Сторонний плеер", isPresented: $showWarningAlert) {
                Button("Понятно", role: .cancel) {
                    if let q = pendingWarningQuality {
                        selectedQuality = q
                    }
                }
            } message: {
                Text("Ваше устройство аппаратно не поддерживает этот формат для встроенного плеера. Вы сможете посмотреть скачанный файл через меню «Поделиться» в стороннем приложении (например, Infuse или VLC).")
            }
        }
        .presentationDetents([.medium, .large])
    }
}
