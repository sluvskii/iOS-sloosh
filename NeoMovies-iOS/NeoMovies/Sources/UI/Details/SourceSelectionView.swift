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
            Form {
                if result.isSerial {
                    if result.seasons.isEmpty {
                        Text("Нет доступных сезонов")
                            .foregroundColor(.secondary)
                    } else {
                        Section(header: Text("Выбор серии")) {
                            Picker("Сезон", selection: $selectedSeason) {
                                ForEach(result.seasons, id: \.season) { season in
                                    Text("\(season.season) сезон").tag(season as AllohaSeason?)
                                }
                            }
                            
                            if let season = selectedSeason {
                                Picker("Серия", selection: $selectedEpisode) {
                                    ForEach(season.episodes, id: \.episode) { episode in
                                        Text("\(episode.episode) серия").tag(episode as AllohaEpisode?)
                                    }
                                }
                            }
                        }
                        
                        if let episode = selectedEpisode {
                            Section(header: Text("Озвучка")) {
                                Picker("Озвучка", selection: $selectedTranslation) {
                                    ForEach(episode.translations, id: \.id) { translation in
                                        Text(translation.name).tag(translation as AllohaTranslation?)
                                    }
                                }
                            }
                        }
                    }
                } else if let movie = result.movie {
                    Section(header: Text("Озвучка")) {
                        Picker("Озвучка", selection: $selectedTranslation) {
                            ForEach(movie.translations, id: \.id) { translation in
                                Text(translation.name).tag(translation as AllohaTranslation?)
                            }
                        }
                    }
                } else {
                    Text("Видео недоступно")
                        .foregroundColor(.secondary)
                }
                
                Section {
                    Button(action: {
                        if let translation = selectedTranslation {
                            onPlay(translation.iframeUrl)
                            presentationMode.wrappedValue.dismiss()
                        }
                    }) {
                        Text("Смотреть")
                            .frame(maxWidth: .infinity, alignment: .center)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(selectedTranslation != nil ? .white : .gray)
                    }
                    .listRowBackground(selectedTranslation != nil ? Color.neoAccent : Color(UIColor.systemGray5))
                    .disabled(selectedTranslation == nil)
                }
            }
            .tint(Color.neoAccent)
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
