import SwiftUI

struct SourceSelectionView: View {
    let result: AllohaApiResult
    let onPlay: (String) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedSeason: AllohaSeason?
    @State private var selectedEpisode: AllohaEpisode?
    @State private var selectedTranslation: AllohaTranslation?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if result.isSerial {
                    // Сериалы
                    if result.seasons.isEmpty {
                        Text("Нет доступных сезонов")
                            .foregroundColor(.secondary)
                    } else {
                        // Выбор сезона
                        VStack(alignment: .leading) {
                            Text("Сезон")
                                .font(.headline)
                            Picker("Сезон", selection: $selectedSeason) {
                                ForEach(result.seasons, id: \.season) { season in
                                    Text("\(season.season) сезон").tag(season as AllohaSeason?)
                                }
                            }
                            .pickerStyle(MenuPickerStyle())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                        
                        // Выбор серии
                        if let season = selectedSeason {
                            VStack(alignment: .leading) {
                                Text("Серия")
                                    .font(.headline)
                                Picker("Серия", selection: $selectedEpisode) {
                                    ForEach(season.episodes, id: \.episode) { episode in
                                        Text("\(episode.episode) серия").tag(episode as AllohaEpisode?)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                        
                        // Выбор озвучки
                        if let episode = selectedEpisode {
                            VStack(alignment: .leading) {
                                Text("Озвучка")
                                    .font(.headline)
                                Picker("Озвучка", selection: $selectedTranslation) {
                                    ForEach(episode.translations, id: \.id) { translation in
                                        Text(translation.name).tag(translation as AllohaTranslation?)
                                    }
                                }
                                .pickerStyle(MenuPickerStyle())
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(12)
                            }
                        }
                    }
                } else if let movie = result.movie {
                    // Фильмы
                    VStack(alignment: .leading) {
                        Text("Озвучка")
                            .font(.headline)
                        Picker("Озвучка", selection: $selectedTranslation) {
                            ForEach(movie.translations, id: \.id) { translation in
                                Text(translation.name).tag(translation as AllohaTranslation?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(12)
                    }
                } else {
                    Text("Видео недоступно")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    if let translation = selectedTranslation {
                        onPlay(translation.iframeUrl)
                        presentationMode.wrappedValue.dismiss()
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Смотреть")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedTranslation != nil ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(16)
                }
                .disabled(selectedTranslation == nil)
                .padding(.bottom)
            }
            .padding()
            .navigationTitle("Выбор источника")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
        .onAppear {
            setupInitialSelection()
        }
        .onChange(of: selectedSeason) { season in
            if let season = season {
                selectedEpisode = season.episodes.first
            }
        }
        .onChange(of: selectedEpisode) { episode in
            if let episode = episode {
                selectedTranslation = episode.translations.first
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

// Нужно добавить Hashable/Equatable для моделей, чтобы они работали с Picker
