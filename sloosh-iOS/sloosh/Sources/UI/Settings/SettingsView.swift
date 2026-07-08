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
                    
                    HStack(spacing: 32) {
                        Spacer()
                        // Option 1: Classic
                        VStack(spacing: 8) {
                            PreviewMoviePosterCard(style: .classic, scale: 0.8)
                                .frame(width: 80, height: 135)
                                .padding(8)
                                .background(cardStyle == .classic ? Color.slooshAccent.opacity(0.08) : Color(.tertiarySystemGroupedBackground))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(cardStyle == .classic ? Color.slooshAccent : Color.clear, lineWidth: 1.5)
                                )
                            
                            Text("Классический")
                                .font(.caption2)
                                .foregroundStyle(cardStyle == .classic ? .primary : .secondary)
                                .fontWeight(cardStyle == .classic ? .semibold : .regular)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                cardStyle = .classic
                            }
                        }
                        
                        // Option 2: Overlay
                        VStack(spacing: 8) {
                            PreviewMoviePosterCard(style: .overlay, scale: 0.8)
                                .frame(width: 80, height: 135)
                                .padding(8)
                                .background(cardStyle == .overlay ? Color.slooshAccent.opacity(0.08) : Color(.tertiarySystemGroupedBackground))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(cardStyle == .overlay ? Color.slooshAccent : Color.clear, lineWidth: 1.5)
                                )
                            
                            Text("Инфо внутри")
                                .font(.caption2)
                                .foregroundStyle(cardStyle == .overlay ? .primary : .secondary)
                                .fontWeight(cardStyle == .overlay ? .semibold : .regular)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                cardStyle = .overlay
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
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
                    
                    HStack(spacing: 32) {
                        Spacer()
                        // Option 1: Standard
                        VStack(spacing: 8) {
                            DensityPreviewGrid(density: .regular, style: cardStyle)
                                .background(cardDensity == .regular ? Color.slooshAccent.opacity(0.08) : Color(.tertiarySystemGroupedBackground))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(cardDensity == .regular ? Color.slooshAccent : Color.clear, lineWidth: 1.5)
                                )
                            
                            Text("Стандартная")
                                .font(.caption2)
                                .foregroundStyle(cardDensity == .regular ? .primary : .secondary)
                                .fontWeight(cardDensity == .regular ? .semibold : .regular)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                cardDensity = .regular
                            }
                        }
                        
                        // Option 2: Compact
                        VStack(spacing: 8) {
                            DensityPreviewGrid(density: .compact, style: cardStyle)
                                .background(cardDensity == .compact ? Color.slooshAccent.opacity(0.08) : Color(.tertiarySystemGroupedBackground))
                                .cornerRadius(16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .stroke(cardDensity == .compact ? Color.slooshAccent : Color.clear, lineWidth: 1.5)
                                )
                            
                            Text("Компактная")
                                .font(.caption2)
                                .foregroundStyle(cardDensity == .compact ? .primary : .secondary)
                                .fontWeight(cardDensity == .compact ? .semibold : .regular)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                cardDensity = .compact
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
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
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color.slooshAccent.opacity(0.25), Color.black.opacity(0.4)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .aspectRatio(2/3, contentMode: .fit)
                    .overlay(
                        Image(systemName: "film")
                            .font(.system(size: 24 * scale))
                            .foregroundStyle(Color.slooshAccent.opacity(0.7))
                    )
                
                Text("8.4")
                    .font(.system(size: 10 * scale, weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5 * scale)
                    .padding(.vertical, 3 * scale)
                    .background(Color.rating(8.4))
                    .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
                    .padding(6 * scale)
            }
            
            VStack(alignment: .leading, spacing: 2 * scale) {
                Text("Дюна 2")
                    .font(.system(size: 13 * scale, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("2024 • Фантастика")
                    .font(.system(size: 10 * scale))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2 * scale)
        }
    }
    
    private var overlayBody: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.slooshAccent.opacity(0.25), Color.black.opacity(0.4)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .aspectRatio(2/3, contentMode: .fit)
                .overlay(
                    Image(systemName: "film")
                        .font(.system(size: 24 * scale))
                        .foregroundStyle(Color.slooshAccent.opacity(0.7))
                )
            
            Rectangle()
                .fill(.regularMaterial)
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.2),
                            .init(color: .black, location: 0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))
            
            VStack(alignment: .leading, spacing: 1 * scale) {
                Text("Дюна 2")
                    .font(.system(size: 12 * scale, weight: .bold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text("2024 • Фантастика")
                    .font(.system(size: 9 * scale, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(8 * scale)
            
            VStack {
                HStack {
                    Text("8.4")
                        .font(.system(size: 10 * scale, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5 * scale)
                        .padding(.vertical, 3 * scale)
                        .background(Color.rating(8.4))
                        .clipShape(RoundedRectangle(cornerRadius: 6 * scale, style: .continuous))
                        .padding(6 * scale)
                    Spacer()
                }
                Spacer()
            }
        }
        .environment(\.colorScheme, .dark)
        .aspectRatio(2/3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12 * scale, style: .continuous))
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


