import SwiftUI

struct SettingsView: View {
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    @AppStorage("autoplayNextEpisode") private var autoplayNextEpisode = true
    @AppStorage("tabBarShowsLabels") private var tabBarShowsLabels = false
    @AppStorage("cardStyle") private var cardStyle: CardStyle = .classic
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular
    @AppStorage("posterQuality") private var posterQuality: PosterQuality = .high
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @State private var tabBarShowsLabelsDraft = false
    @State private var applyTabBarLabelsTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            Section("Вид каталога") {
                // Единая горизонтальная визуализация карточек (скелетоны)
                HStack {
                    Spacer()
                    let spacing: CGFloat = cardDensity == .compact ? 8 : 16
                    let cardWidth: CGFloat = cardDensity == .compact ? 95 : 85
                    let cardHeight = cardStyle == .classic ? cardWidth * 1.5 + 34 : cardWidth * 1.5
                    
                    HStack(spacing: spacing) {
                        ForEach(0..<3, id: \.self) { _ in
                            PreviewMoviePosterCard(style: cardStyle, width: cardWidth)
                        }
                    }
                    .frame(height: cardHeight)
                    Spacer()
                }
                .padding(.vertical, 12)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: cardStyle)
                .animation(.spring(response: 0.35, dampingFraction: 0.75), value: cardDensity)
                
                // Отображение названий
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.grid.1x2")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        
                        Text("Отображение названий")
                            .font(.body)
                    }
                    
                    Picker("Отображение названий", selection: $cardStyle.animation(.spring(response: 0.35, dampingFraction: 0.75))) {
                        Text("Под постером").tag(CardStyle.classic)
                        Text("Поверх постера").tag(CardStyle.overlay)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
                
                // Плотность сетки
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.grid.2x2")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        
                        Text("Плотность сетки")
                            .font(.body)
                    }
                    
                    Picker("Плотность сетки", selection: $cardDensity.animation(.spring(response: 0.35, dampingFraction: 0.75))) {
                        Text("Стандартная").tag(CardDensity.regular)
                        Text("Компактная").tag(CardDensity.compact)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.vertical, 4)
            }
            
            Section("Интерфейс") {
                // Тема
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette.fill")
                        .foregroundStyle(Color.slooshAccent)
                        .font(.system(size: 18))
                        .frame(width: 24)
                    
                    Picker("Тема", selection: $appTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme)
                        }
                    }
                }
                
                // Показывать названия вкладок
                Toggle(isOn: $tabBarShowsLabelsDraft) {
                    HStack(spacing: 12) {
                        Image(systemName: "dock.rectangle")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        
                        Text("Названия вкладок")
                            .font(.body)
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
                        
                        Text("Автопереход к серии")
                            .font(.body)
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
        .padding(.top, -24)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Настройки")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .tint(.primary)
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                VariableBlurView(tintOpacity: 0.75)
                    .padding(.bottom, -20)
                    .ignoresSafeArea(edges: .top)
            )
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
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
        let cardHeight = style == .classic ? width * 1.5 + 34 : width * 1.5
        VStack(alignment: .leading, spacing: style == .classic ? 8 : 0) {
            RoundedRectangle(cornerRadius: style == .overlay ? 16 : 12, style: .continuous)
                .fill(Color.secondary.opacity(0.15))
                .frame(width: width, height: width * 1.5)
                .overlay(
                    // Текст оверлея всегда в иерархии, меняется только прозрачность
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
                    .opacity(style == .overlay ? 1.0 : 0.0)
                )
            
            // Классический текст всегда в иерархии, плавно меняются высота и прозрачность
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
            .opacity(style == .classic ? 1.0 : 0.0)
            .frame(height: style == .classic ? 26 : 0, alignment: .top)
            .clipped()
        }
        .frame(width: width, height: cardHeight, alignment: .top)
    }
}


