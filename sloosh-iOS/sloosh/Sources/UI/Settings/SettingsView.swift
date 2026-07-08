import SwiftUI

struct SettingsView: View {
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    @AppStorage("autoplayNextEpisode") private var autoplayNextEpisode = true
    @AppStorage("tabBarShowsLabels") private var tabBarShowsLabels = false
    @AppStorage("cardStyle") private var cardStyle: CardStyle = .classic
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular
    @AppStorage("posterQuality") private var posterQuality: PosterQuality = .high
    @State private var tabBarShowsLabelsDraft = false
    @State private var applyTabBarLabelsTask: Task<Void, Never>?
    
    var body: some View {
        List {
            Section("Интерфейс") {
                // Единая горизонтальная визуализация карточек (скелетоны)
                HStack {
                    Spacer()
                    let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                    let cardWidth: CGFloat = cardDensity == .compact ? 85 : 95
                    
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { _ in
                            PreviewMoviePosterCard(style: cardStyle, width: cardWidth)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 12)
                
                // Стиль карточек
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.grid.1x2")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Стиль карточек")
                                .font(.body)
                            Text("Отображение информации в списках")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Picker("Стиль карточек", selection: $cardStyle.animation(.spring(response: 0.35, dampingFraction: 0.75))) {
                        Text("Классический").tag(CardStyle.classic)
                        Text("Инфо внутри").tag(CardStyle.overlay)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
                
                // Сетка списков
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Сетка списков")
                                .font(.body)
                            Text("Отступы между карточками и плотность")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Picker("Сетка списков", selection: $cardDensity.animation(.spring(response: 0.35, dampingFraction: 0.75))) {
                        Text("Стандартная").tag(CardDensity.regular)
                        Text("Компактная").tag(CardDensity.compact)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
                
                // Показывать подписи вкладок
                Toggle(isOn: $tabBarShowsLabelsDraft) {
                    HStack(spacing: 12) {
                        Image(systemName: "dock.rectangle")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Подписи вкладок")
                                .font(.body)
                            Text("Названия разделов в нижней панели")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Качество постеров
                HStack(spacing: 12) {
                    Image(systemName: "photo.fill")
                        .foregroundStyle(Color.slooshAccent)
                        .font(.system(size: 18))
                        .frame(width: 24)
                    
                    Picker("Качество постеров", selection: $posterQuality) {
                        ForEach(PosterQuality.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                }
            }
            
            Section("Воспроизведение") {
                // Качество видео
                HStack(spacing: 12) {
                    Image(systemName: "video.fill")
                        .foregroundStyle(Color.slooshAccent)
                        .font(.system(size: 18))
                        .frame(width: 24)
                    
                    Picker("Качество видео", selection: $preferredQuality) {
                        ForEach(VideoQualityPreference.allCases) { quality in
                            Text(quality.title).tag(quality)
                        }
                    }
                }
                
                // Автопереход к следующей серии
                Toggle(isOn: $autoplayNextEpisode) {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.forward.to.line.circle.fill")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Автопереход к серии")
                                .font(.body)
                            Text("Автоматически включать следующий эпизод")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            Section("О приложении") {
                NavigationLink {
                    AboutView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        Text("О приложении")
                    }
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

struct PreviewMoviePosterCard: View {
    let style: CardStyle
    let width: CGFloat
    
    var body: some View {
        switch style {
        case .classic:
            classicBody
        case .overlay:
            overlayBody
        }
    }
    
    private var classicBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: width, height: width * 1.5)
            
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 12)
                    .frame(width: width * 0.75)
                
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 10)
                    .frame(width: width * 0.5)
            }
            .padding(.horizontal, 4)
        }
    }
    
    private var overlayBody: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: width, height: width * 1.5)
            .overlay(
                VStack(alignment: .leading, spacing: 4) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 12)
                        .frame(width: width * 0.7)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 10)
                        .frame(width: width * 0.45)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            )
    }
}


