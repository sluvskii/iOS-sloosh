import SwiftUI

struct SettingsView: View {
    @AppStorage("preferredVideoQuality") private var preferredQuality: VideoQualityPreference = .ask
    @AppStorage("autoplayNextEpisode") private var autoplayNextEpisode = true
    @AppStorage("tabBarShowsLabels") private var tabBarShowsLabels = false
    @AppStorage("cardStyle") private var cardStyle: CardStyle = .classic
    @AppStorage("cardDensity") private var cardDensity: CardDensity = .regular
    @AppStorage("posterQuality") private var posterQuality: PosterQuality = .high
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("showOriginalTitle") private var showOriginalTitle = true
    @State private var tabBarShowsLabelsDraft = false
    @State private var applyTabBarLabelsTask: Task<Void, Never>?
    @State private var scrollOffset: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @State private var showLogsShareSheet = false
    
    private var blurOpacity: Double {
        let progress = max(0, scrollOffset) / 30.0
        return min(1.0, Double(progress))
    }
    
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

                // Иконка приложения
                NavigationLink {
                    AppIconPickerView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "app.badge.fill")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)

                        Text("Иконка приложения")
                            .font(.body)

                        Spacer()

                        Text(AppIconManager.shared.currentIcon.title)
                            .font(.body)
                            .foregroundColor(.secondary)
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

                // Показывать оригинальное название
                Toggle(isOn: $showOriginalTitle) {
                    HStack(spacing: 12) {
                        Image(systemName: "character.textbox")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        
                        Text("Оригинальное название")
                            .font(.body)
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
            
            Section("Диагностика") {
                Button {
                    showLogsShareSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(Color.slooshAccent)
                            .font(.system(size: 18))
                            .frame(width: 24)
                        Text("Поделиться логами")
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .environment(\.defaultMinListHeaderHeight, .leastNonzeroMagnitude)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            ZStack {
                Text("Настройки")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                
                HStack {
                    TelegramGlassIconButton(systemName: "chevron.left") {
                        dismiss()
                    }
                    
                    Spacer()
                }
            }
            .padding(.horizontal, 16)
            .background(
                VariableBlurView(tintOpacity: 1.0)
                    .padding(.bottom, -60)
                    .ignoresSafeArea(edges: .top)
                    .opacity(blurOpacity)
                    .animation(.easeInOut(duration: 0.2), value: blurOpacity)
            )
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newOffset in
            scrollOffset = newOffset
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
        .fullWidthSwipeBack()
        .sheet(isPresented: $showLogsShareSheet) {
            ShareSheet(items: [AppDiagnostics.shared.getLogsURL()])
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

// MARK: - App Icon Picker Screen

public struct AppIconPickerView: View {
    @ObservedObject private var iconManager = AppIconManager.shared
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AppIconOption.allCases) { option in
                        let isSelected = iconManager.currentIcon == option

                        Button {
                            iconManager.selectIcon(option)
                        } label: {
                            VStack(spacing: 12) {
                                ZStack(alignment: .topTrailing) {
                                    Image(option.previewAsset)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 84, height: 84)
                                        .clipShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 19, style: .continuous)
                                                .stroke(isSelected ? Color.slooshAccent : Color.primary.opacity(0.1), lineWidth: isSelected ? 2 : 1)
                                        )
                                        .shadow(color: Color.black.opacity(isSelected ? 0.25 : 0.12), radius: isSelected ? 8 : 4, x: 0, y: isSelected ? 4 : 2)

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22, weight: .bold))
                                            .foregroundStyle(.white, Color.slooshAccent)
                                            .background(Circle().fill(Color.black.opacity(0.2)))
                                            .offset(x: 6, y: -6)
                                            .transition(.scale.combined(with: .opacity))
                                    }
                                }
                                .padding(.top, 6)

                                Text(option.title)
                                    .font(.system(size: 15, weight: isSelected ? .semibold : .medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                            )
                            .glassEffect(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(isSelected ? Color.slooshAccent.opacity(0.8) : Color.clear, lineWidth: 1.5)
                            )
                            .scaleEffect(isSelected ? 1.02 : 1.0)
                            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: isSelected)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Text("Выбранная иконка будет отображаться на домашнем экране вашего устройства.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .padding(.top, 4)
            }
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Иконка приложения")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            iconManager.refreshCurrentIcon()
        }
    }
}


