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
                
                // Стиль карточек (с визуализацией)
                VStack(alignment: .leading, spacing: 12) {
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
                    .padding(.top, 4)
                    
                    HStack {
                        Spacer()
                        PreviewMoviePosterCard(style: cardStyle, scale: 0.8)
                            .frame(width: 80, height: 135)
                            .padding(10)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(16)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    
                    Picker("Стиль карточек", selection: $cardStyle.animation(.spring(response: 0.35, dampingFraction: 0.75))) {
                        Text("Классический").tag(CardStyle.classic)
                        Text("Инфо внутри").tag(CardStyle.overlay)
                    }
                    .pickerStyle(.segmented)
                }
                
                // Сетка карточек (с визуализацией)
                VStack(alignment: .leading, spacing: 12) {
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
                    .padding(.top, 4)
                    
                    HStack {
                        Spacer()
                        DensityPreviewGrid(density: cardDensity, style: cardStyle)
                            .background(Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(16)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    
                    Picker("Сетка списков", selection: $cardDensity.animation(.spring(response: 0.35, dampingFraction: 0.75))) {
                        Text("Стандартная").tag(CardDensity.regular)
                        Text("Компактная").tag(CardDensity.compact)
                    }
                    .pickerStyle(.segmented)
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
    let scale: CGFloat
    
    var body: some View {
        switch style {
        case .classic:
            classicBody
        case .overlay:
            overlayBody
        }
    }
    
    private var classicBody: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .aspectRatio(2/3, contentMode: .fit)
            
            VStack(alignment: .leading, spacing: 4 * scale) {
                RoundedRectangle(cornerRadius: 2 * scale)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(height: 10 * scale)
                    .frame(width: 50 * scale)
                
                RoundedRectangle(cornerRadius: 2 * scale)
                    .fill(Color.secondary.opacity(0.1))
                    .frame(height: 8 * scale)
                    .frame(width: 32 * scale)
            }
            .padding(.horizontal, 2 * scale)
        }
    }
    
    private var overlayBody: some View {
        RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
            .fill(Color.secondary.opacity(0.15))
            .aspectRatio(2/3, contentMode: .fit)
            .overlay(
                VStack(alignment: .leading, spacing: 4 * scale) {
                    Spacer()
                    RoundedRectangle(cornerRadius: 2 * scale)
                        .fill(Color.secondary.opacity(0.25))
                        .frame(height: 10 * scale)
                        .frame(width: 45 * scale)
                    
                    RoundedRectangle(cornerRadius: 2 * scale)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8 * scale)
                        .frame(width: 30 * scale)
                }
                .padding(8 * scale)
                .frame(maxWidth: .infinity, alignment: .leading)
            )
    }
}

struct DensityPreviewGrid: View {
    let density: CardDensity
    let style: CardStyle
    
    var body: some View {
        let cardWidth: CGFloat = density == .regular ? 34 : 41
        let spacing: CGFloat = density == .regular ? 12 : 6
        let padding: CGFloat = density == .regular ? 12 : 8
        let scale: CGFloat = density == .regular ? 0.34 : 0.41
        
        VStack(spacing: spacing) {
            HStack(spacing: spacing) {
                PreviewMoviePosterCard(style: style, scale: scale)
                    .frame(width: cardWidth)
                PreviewMoviePosterCard(style: style, scale: scale)
                    .frame(width: cardWidth)
            }
            HStack(spacing: spacing) {
                PreviewMoviePosterCard(style: style, scale: scale)
                    .frame(width: cardWidth)
                PreviewMoviePosterCard(style: style, scale: scale)
                    .frame(width: cardWidth)
            }
        }
        .padding(padding)
        .frame(width: 104, height: 160)
    }
}


