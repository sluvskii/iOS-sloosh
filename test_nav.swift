import SwiftUI

@available(iOS 26.0, *)
struct TestView: View {
    @State private var isPresented = false
    @State private var translations: [WatchSelectorOption] = [
        .init(title: "AniLibria", isSelected: true),
        .init(title: "TVShows"),
        .init(title: "HDrezka"),
        .init(title: "LostFilm"),
        .init(title: "Original", isAvailable: false)
    ]
    @State private var seasons: [WatchSelectorOption] = [
        .init(title: "1 сезон", isSelected: true),
        .init(title: "2 сезон"),
        .init(title: "3 сезон")
    ]
    @State private var episodes: [WatchSelectorOption] = [
        .init(title: "1 серия"),
        .init(title: "2 серия"),
        .init(title: "3 серия", isSelected: true),
        .init(title: "4 серия"),
        .init(title: "5 серия")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(0..<40) { i in
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(.quinary)
                            .frame(height: 88)
                            .overlay {
                                Text("Контент \(i)")
                            }
                    }
                }
                .padding()
            }
            .navigationTitle("Детали")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Озвучка") {
                        isPresented = true
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .sheet(isPresented: $isPresented) {
            NativeWatchSelectorSheet(
                title: "Разделение",
                actionTitle: "Смотреть",
                translationOptions: translations,
                seasonOptions: seasons,
                episodeOptions: episodes,
                onTranslationTap: selectTranslation,
                onSeasonTap: selectSeason,
                onEpisodeTap: selectEpisode,
                onConfirm: {}
            )
        }
    }

    private func selectTranslation(_ option: WatchSelectorOption) {
        translations = translations.map {
            var updated = $0
            updated.isSelected = ($0.id == option.id)
            return updated
        }
    }

    private func selectSeason(_ option: WatchSelectorOption) {
        seasons = seasons.map {
            var updated = $0
            updated.isSelected = ($0.id == option.id)
            return updated
        }
    }

    private func selectEpisode(_ option: WatchSelectorOption) {
        episodes = episodes.map {
            var updated = $0
            updated.isSelected = ($0.id == option.id)
            return updated
        }
    }
}
