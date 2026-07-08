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
                    
                    HStack(spacing: 24) {
                        Spacer()
                        // Option 1: Classic
                        VStack(spacing: 8) {
                            VStack(spacing: 6) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(LinearGradient(
                                        colors: [Color.slooshAccent.opacity(cardStyle == .classic ? 0.3 : 0.15),
                                                 Color.slooshAccent.opacity(cardStyle == .classic ? 0.1 : 0.05)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                    .aspectRatio(2/3, contentMode: .fit)
                                    .overlay(
                                        Image(systemName: "film")
                                            .foregroundStyle(Color.slooshAccent.opacity(cardStyle == .classic ? 0.8 : 0.4))
                                            .font(.system(size: 16))
                                    )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(cardStyle == .classic ? Color.primary.opacity(0.8) : Color.primary.opacity(0.4))
                                        .frame(height: 4)
                                        .frame(width: 36)
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(cardStyle == .classic ? Color.primary.opacity(0.4) : Color.primary.opacity(0.2))
                                        .frame(height: 3)
                                        .frame(width: 22)
                                }
                                .padding(.horizontal, 2)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(width: 64)
                            .padding(6)
                            .background(cardStyle == .classic ? Color.slooshAccent.opacity(0.08) : Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
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
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(LinearGradient(
                                        colors: [Color.slooshAccent.opacity(cardStyle == .overlay ? 0.3 : 0.15),
                                                 Color.slooshAccent.opacity(cardStyle == .overlay ? 0.1 : 0.05)],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                    .aspectRatio(2/3, contentMode: .fit)
                                    .overlay(
                                        Image(systemName: "film")
                                            .foregroundStyle(Color.slooshAccent.opacity(cardStyle == .overlay ? 0.8 : 0.4))
                                            .font(.system(size: 16))
                                    )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(.white)
                                        .frame(height: 4)
                                        .frame(width: 36)
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(.white.opacity(0.6))
                                        .frame(height: 3)
                                        .frame(width: 22)
                                }
                                .padding(4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .bottom, endPoint: .top)
                                )
                                .cornerRadius(6)
                            }
                            .frame(width: 64)
                            .padding(6)
                            .background(cardStyle == .overlay ? Color.slooshAccent.opacity(0.08) : Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
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
                            Text("Количество элементов в сетке")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 4)
                    
                    HStack(spacing: 24) {
                        Spacer()
                        // Option 1: Standard
                        VStack(spacing: 8) {
                            VStack(spacing: 4) {
                                HStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .regular ? 0.3 : 0.15))
                                        .frame(width: 20, height: 30)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .regular ? 0.3 : 0.15))
                                        .frame(width: 20, height: 30)
                                }
                                HStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .regular ? 0.3 : 0.15))
                                        .frame(width: 20, height: 30)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .regular ? 0.3 : 0.15))
                                        .frame(width: 20, height: 30)
                                }
                            }
                            .frame(width: 64, height: 76)
                            .padding(6)
                            .background(cardDensity == .regular ? Color.slooshAccent.opacity(0.08) : Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
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
                            VStack(spacing: 3) {
                                HStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .compact ? 0.3 : 0.15))
                                        .frame(width: 14, height: 21)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .compact ? 0.3 : 0.15))
                                        .frame(width: 14, height: 21)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .compact ? 0.3 : 0.15))
                                        .frame(width: 14, height: 21)
                                }
                                HStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .compact ? 0.3 : 0.15))
                                        .frame(width: 14, height: 21)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .compact ? 0.3 : 0.15))
                                        .frame(width: 14, height: 21)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .compact ? 0.3 : 0.15))
                                        .frame(width: 14, height: 21)
                                }
                                HStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .compact ? 0.3 : 0.15))
                                        .frame(width: 14, height: 21)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .compact ? 0.3 : 0.15))
                                        .frame(width: 14, height: 21)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color.slooshAccent.opacity(cardDensity == .compact ? 0.3 : 0.15))
                                        .frame(width: 14, height: 21)
                                }
                            }
                            .frame(width: 64, height: 76)
                            .padding(6)
                            .background(cardDensity == .compact ? Color.slooshAccent.opacity(0.08) : Color(.tertiarySystemGroupedBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
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
}
