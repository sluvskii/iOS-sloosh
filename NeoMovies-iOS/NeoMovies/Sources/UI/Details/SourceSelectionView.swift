import SwiftUI

struct SourceSelectionView: View {
    let result: AllohaApiResult
    let onPlay: (String) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedSeason: AllohaSeason?
    @State private var selectedEpisode: AllohaEpisode?
    @State private var selectedTranslation: AllohaTranslation?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Выбор источника")
                    .font(.system(size: 24, weight: .heavy, design: .rounded))
                Spacer()
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
            }
            .padding()
            .padding(.top, 8)
            
            ScrollView {
                VStack(spacing: 24) {
                    if result.isSerial {
                        if result.seasons.isEmpty {
                            Text("Нет доступных сезонов")
                                .font(.system(size: 16, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding()
                        } else {
                            VStack(spacing: 20) {
                                // Сезон
                                PickerRow(icon: "tv", title: "Сезон", selection: $selectedSeason, options: result.seasons) { season in
                                    Text("\(season.season) сезон").tag(season as AllohaSeason?)
                                }
                                
                                Divider()
                                
                                // Серия
                                if let season = selectedSeason {
                                    PickerRow(icon: "play.tv", title: "Серия", selection: $selectedEpisode, options: season.episodes) { episode in
                                        Text("\(episode.episode) серия").tag(episode as AllohaEpisode?)
                                    }
                                }
                                
                                Divider()
                                
                                // Озвучка
                                if let episode = selectedEpisode {
                                    PickerRow(icon: "mic", title: "Озвучка", selection: $selectedTranslation, options: episode.translations) { translation in
                                        Text(translation.name).tag(translation as AllohaTranslation?)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .cornerRadius(20)
                            .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                        }
                    } else if let movie = result.movie {
                        VStack(spacing: 20) {
                            PickerRow(icon: "mic", title: "Озвучка", selection: $selectedTranslation, options: movie.translations) { translation in
                                Text(translation.name).tag(translation as AllohaTranslation?)
                            }
                        }
                        .padding()
                        .background(Color(UIColor.secondarySystemGroupedBackground))
                        .cornerRadius(20)
                        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 5)
                    } else {
                        Text("Видео недоступно")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
                .padding(.horizontal)
                .padding(.top, 10)
            }
            
            // Play Button
            Button(action: {
                if let translation = selectedTranslation {
                    onPlay(translation.iframeUrl)
                    presentationMode.wrappedValue.dismiss()
                }
            }) {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Смотреть")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.regularMaterial)
                .background(selectedTranslation != nil ? Color.blue.opacity(0.4) : Color.gray.opacity(0.2))
                .foregroundColor(selectedTranslation != nil ? .white : .gray)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .shadow(color: selectedTranslation != nil ? .blue.opacity(0.3) : .clear, radius: 15, x: 0, y: 8)
            }
            .disabled(selectedTranslation == nil)
            .padding(.horizontal)
            .padding(.bottom, 24)
            .padding(.top, 16)
        }
        .background(Color(UIColor.systemGroupedBackground).edgesIgnoringSafeArea(.all))
        .onAppear {
            setupInitialSelection()
        }
        .onChange(of: selectedSeason) { season in
            if let season = season {
                withAnimation {
                    selectedEpisode = season.episodes.first
                }
            }
        }
        .onChange(of: selectedEpisode) { episode in
            if let episode = episode {
                withAnimation {
                    selectedTranslation = episode.translations.first
                }
            }
        }
    }
    
    private func setupInitialSelection() {
        if result.isSerial {
            if let firstSeason = result.seasons.first {
                selectedSeason = firstSeason
                if let firstEpisode = firstSeason.episodes.first {
                    selectedEpisode = firstEpisode
                    selectedTranslation = firstEpisode.translations.first
                }
            }
        } else if let movie = result.movie {
            selectedTranslation = movie.translations.first
        }
    }
}

struct PickerRow<T: Hashable, V: View>: View {
    let icon: String
    let title: String
    @Binding var selection: T?
    let options: [T]
    let content: (T) -> V
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.blue)
            }
            
            Text(title)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
            
            Spacer()
            
            Picker(title, selection: $selection) {
                ForEach(options, id: \.self) { option in
                    content(option)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .accentColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(UIColor.tertiarySystemFill))
            .cornerRadius(10)
        }
    }
}
