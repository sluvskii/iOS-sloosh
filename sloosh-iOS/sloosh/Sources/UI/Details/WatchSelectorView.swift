import SwiftUI

struct WatchSelectorView: View {
    @ObservedObject var viewModel: DetailsViewModel
    let kpId: Int
    let title: String
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var sourceManager = SourceManager.shared
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Source Switcher
                SourceSelectorHeader(selectedMode: $sourceManager.currentMode)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .onChange(of: sourceManager.currentMode) { _ in
                        fetchCurrentSource()
                    }
                
                Divider().opacity(0.5)
                
                ZStack {
                    if viewModel.isFetchingSources {
                        VStack(spacing: 20) {
                            ProgressView()
                                .scaleEffect(1.2)
                            Text("Поиск источников...")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let wrapper = viewModel.sourceResultWrapper {
                        if wrapper.mode == .alloha, let result = wrapper.allohaResult {
                            SourceSelectionViewContent(result: result) { translation in
                                viewModel.resolveAllohaPlayback(iframeUrl: translation.iframeUrl, translationName: translation.name)
                            }
                        } else if wrapper.mode == .collaps {
                            let isSerial = wrapper.collapsSeasons != nil && !(wrapper.collapsSeasons?.isEmpty ?? true)
                            CollapsSelectionViewContent(
                                result: wrapper.collapsSeasons ?? [],
                                movieResult: wrapper.collapsMovie,
                                isSerial: isSerial,
                                onPlay: { url in
                                    viewModel.playDirectUrl(url)
                                }
                            )
                        } else {
                            emptyView
                        }
                    } else {
                        emptyView
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .padding(8)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(Circle())
                            .foregroundStyle(.primary)
                    }
                    .tint(.primary)
                    .buttonStyle(.plain)
                }
            }
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if viewModel.sourceResultWrapper == nil {
                fetchCurrentSource()
            }
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 20) {
            Image(systemName: "video.slash")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)
            
            VStack(spacing: 8) {
                Text("Источник не ответил")
                    .font(.system(size: 22, weight: .bold))
                
                Text("Попробуйте сменить источник сверху или проверьте интернет.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            Button(action: {
                fetchCurrentSource()
            }) {
                Text("Повторить поиск")
                    .font(.system(size: 16, weight: .bold))
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .glassEffect(in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func fetchCurrentSource() {
        Task {
            await viewModel.fetchSources(kpId: kpId, title: title)
        }
    }
}

private struct SourceSelectorHeader: View {
    @Binding var selectedMode: SourceMode
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(SourceMode.allCases) { mode in
                let isSelected = selectedMode == mode
                
                Button {
                    selectedMode = mode
                } label: {
                    Text(mode.displayName)
                        .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(
                            ZStack {
                                if isSelected {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.1))
                                        .matchedGeometryEffect(id: "source_tab", in: sourceNamespace)
                                }
                            }
                        )
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(isSelected ? .primary : .secondary)
            }
        }
        .padding(4)
        .glassEffect(in: Capsule())
    }
    
    @Namespace private var sourceNamespace
}

// Separate Content views for Alloha and Collaps to keep WatchSelectorView clean
struct SourceSelectionViewContent: View {
    let result: AllohaApiResult
    let onPlay: (AllohaTranslation) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSeason: Int?
    @State private var selectedEpisode: Int?
    @State private var selectedTranslationName: String?
    
    var allTranslations: [String] {
        if result.isSerial {
            var names = Set<String>()
            for season in result.seasons {
                for episode in season.episodes {
                    for t in episode.translations {
                        names.insert(t.name)
                    }
                }
            }
            return Array(names).sorted()
        } else if let movie = result.movie {
            return movie.translations.map { $0.name }.sorted()
        }
        return []
    }
    
    var allSeasons: [Int] {
        return result.seasons.map { $0.season }.sorted()
    }
    
    var allEpisodes: [Int] {
        guard let s = selectedSeason, let season = result.seasons.first(where: { $0.season == s }) else { return [] }
        return season.episodes.map { $0.episode }.sorted()
    }
    
    func isTranslationAvailable(_ name: String) -> Bool {
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode else { return false }
            return episodeHasTranslation(season: s, episode: e, t: name)
        } else if let movie = result.movie {
            return movie.translations.contains { $0.name == name }
        }
        return false
    }
    
    func isSeasonAvailable(_ seasonNum: Int) -> Bool {
        guard let tName = selectedTranslationName else { return true }
        return seasonHasTranslation(season: seasonNum, t: tName)
    }
    
    func isEpisodeAvailable(_ episodeNum: Int) -> Bool {
        guard let s = selectedSeason, let tName = selectedTranslationName else { return true }
        return episodeHasTranslation(season: s, episode: episodeNum, t: tName)
    }
    
    func seasonHasTranslation(season: Int, t: String) -> Bool {
        guard let s = result.seasons.first(where: { $0.season == season }) else { return false }
        return s.episodes.contains { ep in ep.translations.contains { $0.name == t } }
    }

    func episodeHasTranslation(season: Int, episode: Int, t: String) -> Bool {
        guard let s = result.seasons.first(where: { $0.season == season }),
              let ep = s.episodes.first(where: { $0.episode == episode }) else { return false }
        return ep.translations.contains { $0.name == t }
    }
    
    func selectTranslation(_ name: String) {
        selectedTranslationName = name
        if result.isSerial {
            if let s = selectedSeason, !seasonHasTranslation(season: s, t: name) {
                if let newS = result.seasons.first(where: { seasonHasTranslation(season: $0.season, t: name) }) {
                    selectedSeason = newS.season
                }
            }
            if let s = selectedSeason, let e = selectedEpisode, !episodeHasTranslation(season: s, episode: e, t: name) {
                if let season = result.seasons.first(where: { $0.season == s }),
                   let newEp = season.episodes.first(where: { $0.translations.contains(where: { $0.name == name }) }) {
                    selectedEpisode = newEp.episode
                }
            }
        }
    }
    
    func selectSeason(_ s: Int) {
        selectedSeason = s
        let seasonObj = result.seasons.first(where: { $0.season == s })!
        if let e = selectedEpisode, !seasonObj.episodes.contains(where: { $0.episode == e }) {
            selectedEpisode = seasonObj.episodes.first?.episode ?? 1
        }
        if let t = selectedTranslationName, let e = selectedEpisode, !episodeHasTranslation(season: s, episode: e, t: t) {
            if let ep = seasonObj.episodes.first(where: { $0.episode == e }), let firstT = ep.translations.first {
                selectedTranslationName = firstT.name
            }
        }
    }
    
    func selectEpisode(_ e: Int) {
        selectedEpisode = e
        if let s = selectedSeason, let t = selectedTranslationName, !episodeHasTranslation(season: s, episode: e, t: t) {
            if let seasonObj = result.seasons.first(where: { $0.season == s }),
               let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
               let firstT = epObj.translations.first {
                selectedTranslationName = firstT.name
            }
        }
    }
    
    func playSelected() {
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode, let tName = selectedTranslationName else { return }
            guard let seasonObj = result.seasons.first(where: { $0.season == s }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
                  let translation = epObj.translations.first(where: { $0.name == tName }) else { return }
            onPlay(translation)
        } else if let movie = result.movie {
            guard let tName = selectedTranslationName,
                  let translation = movie.translations.first(where: { $0.name == tName }) else { return }
            onPlay(translation)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !allTranslations.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Озвучка")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            
                            FlowLayout(spacing: 10) {
                                ForEach(allTranslations, id: \.self) { tName in
                                    WatchSelectorChip(
                                        title: tName,
                                        isSelected: selectedTranslationName == tName,
                                        isAvailable: isTranslationAvailable(tName)
                                    ) {
                                        selectTranslation(tName)
                                    }
                                }
                            }
                        }
                    }
                    
                    if result.isSerial && !allSeasons.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Сезон")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            
                            FlowLayout(spacing: 10) {
                                ForEach(allSeasons, id: \.self) { s in
                                    WatchSelectorChip(
                                        title: "\(s) сезон",
                                        isSelected: selectedSeason == s,
                                        isAvailable: isSeasonAvailable(s)
                                    ) {
                                        selectSeason(s)
                                    }
                                }
                            }
                        }
                        
                        if !allEpisodes.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Серия")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                FlowLayout(spacing: 10) {
                                    ForEach(allEpisodes, id: \.self) { e in
                                        WatchSelectorChip(
                                            title: "\(e) серия",
                                            isSelected: selectedEpisode == e,
                                            isAvailable: isEpisodeAvailable(e)
                                        ) {
                                            selectEpisode(e)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            
            // Bottom play button
            Button(action: {
                playSelected()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Смотреть")
                        .font(.system(size: 17, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .glassEffect(in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onAppear {
            if selectedTranslationName == nil {
                setupInitialSelection()
            }
        }
    }
    
    private func setupInitialSelection() {
        if result.isSerial {
            if let firstSeason = result.seasons.first {
                selectedSeason = firstSeason.season
                if let firstEpisode = firstSeason.episodes.first {
                    selectedEpisode = firstEpisode.episode
                    selectedTranslationName = firstEpisode.translations.first?.name
                }
            }
        } else if let movie = result.movie {
            selectedTranslationName = movie.translations.first?.name
        }
    }
}

struct CollapsSelectionViewContent: View {
    let result: [CollapsSeason]
    let movieResult: CollapsMovie?
    let isSerial: Bool
    let onPlay: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSeason: Int?
    @State private var selectedEpisode: Int?
    @State private var selectedTranslationName: String?
    
    var allTranslations: [String] {
        if isSerial {
            var names = Set<String>()
            for season in result {
                for episode in season.episodes {
                    for v in episode.voices {
                        names.insert(v)
                    }
                }
            }
            return Array(names).sorted()
        } else if let movie = movieResult {
            return movie.voices.sorted()
        }
        return []
    }
    
    var allSeasons: [Int] {
        return result.map { $0.season }.sorted()
    }
    
    var allEpisodes: [Int] {
        guard let s = selectedSeason, let season = result.first(where: { $0.season == s }) else { return [] }
        return season.episodes.map { $0.episode }.sorted()
    }
    
    func isTranslationAvailable(_ name: String) -> Bool {
        if isSerial {
            guard let s = selectedSeason, let e = selectedEpisode else { return false }
            return episodeHasTranslation(season: s, episode: e, t: name)
        } else if let movie = movieResult {
            return movie.voices.contains(name)
        }
        return false
    }
    
    func isSeasonAvailable(_ seasonNum: Int) -> Bool {
        guard let tName = selectedTranslationName else { return true }
        return seasonHasTranslation(season: seasonNum, t: tName)
    }
    
    func isEpisodeAvailable(_ episodeNum: Int) -> Bool {
        guard let s = selectedSeason, let tName = selectedTranslationName else { return true }
        return episodeHasTranslation(season: s, episode: episodeNum, t: tName)
    }
    
    func seasonHasTranslation(season: Int, t: String) -> Bool {
        guard let s = result.first(where: { $0.season == season }) else { return false }
        return s.episodes.contains { ep in ep.voices.contains(t) }
    }

    func episodeHasTranslation(season: Int, episode: Int, t: String) -> Bool {
        guard let s = result.first(where: { $0.season == season }),
              let ep = s.episodes.first(where: { $0.episode == episode }) else { return false }
        return ep.voices.contains(t)
    }
    
    func selectTranslation(_ name: String) {
        selectedTranslationName = name
        if isSerial {
            if let s = selectedSeason, !seasonHasTranslation(season: s, t: name) {
                if let newS = result.first(where: { seasonHasTranslation(season: $0.season, t: name) }) {
                    selectedSeason = newS.season
                }
            }
            if let s = selectedSeason, let e = selectedEpisode, !episodeHasTranslation(season: s, episode: e, t: name) {
                if let season = result.first(where: { $0.season == s }),
                   let newEp = season.episodes.first(where: { $0.voices.contains(name) }) {
                    selectedEpisode = newEp.episode
                }
            }
        }
    }
    
    func selectSeason(_ s: Int) {
        selectedSeason = s
        let seasonObj = result.first(where: { $0.season == s })!
        if let e = selectedEpisode, !seasonObj.episodes.contains(where: { $0.episode == e }) {
            selectedEpisode = seasonObj.episodes.first?.episode ?? 1
        }
        if let t = selectedTranslationName, let e = selectedEpisode, !episodeHasTranslation(season: s, episode: e, t: t) {
            if let ep = seasonObj.episodes.first(where: { $0.episode == e }), let firstT = ep.voices.first {
                selectedTranslationName = firstT
            }
        }
    }
    
    func selectEpisode(_ e: Int) {
        selectedEpisode = e
        if let s = selectedSeason, let t = selectedTranslationName, !episodeHasTranslation(season: s, episode: e, t: t) {
            if let seasonObj = result.first(where: { $0.season == s }),
               let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
               let firstT = epObj.voices.first {
                selectedTranslationName = firstT
            }
        }
    }
    
    func playSelected() {
        if isSerial {
            guard let s = selectedSeason, let e = selectedEpisode else { return }
            guard let seasonObj = result.first(where: { $0.season == s }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == e }) else { return }
            
            if let hls = epObj.hlsUrl, !hls.isEmpty {
                onPlay(hls)
            } else if let mpd = epObj.mpdUrl, !mpd.isEmpty {
                onPlay(mpd)
            }
        } else if let movie = movieResult {
            if let hls = movie.hlsUrl, !hls.isEmpty {
                onPlay(hls)
            } else if let mpd = movie.mpdUrl, !mpd.isEmpty {
                onPlay(mpd)
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    if !allTranslations.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Озвучка")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            
                            FlowLayout(spacing: 10) {
                                ForEach(allTranslations, id: \.self) { tName in
                                    WatchSelectorChip(
                                        title: tName,
                                        isSelected: selectedTranslationName == tName,
                                        isAvailable: isTranslationAvailable(tName)
                                    ) {
                                        selectTranslation(tName)
                                    }
                                }
                            }
                        }
                    }
                    
                    if isSerial && !allSeasons.isEmpty {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Сезон")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.primary)
                            
                            FlowLayout(spacing: 10) {
                                ForEach(allSeasons, id: \.self) { s in
                                    WatchSelectorChip(
                                        title: "\(s) сезон",
                                        isSelected: selectedSeason == s,
                                        isAvailable: isSeasonAvailable(s)
                                    ) {
                                        selectSeason(s)
                                    }
                                }
                            }
                        }
                        
                        if !allEpisodes.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Серия")
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.primary)
                                
                                FlowLayout(spacing: 10) {
                                    ForEach(allEpisodes, id: \.self) { e in
                                        WatchSelectorChip(
                                            title: "\(e) серия",
                                            isSelected: selectedEpisode == e,
                                            isAvailable: isEpisodeAvailable(e)
                                        ) {
                                            selectEpisode(e)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            
            // Bottom play button
            Button(action: {
                playSelected()
            }) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .bold))
                    Text("Смотреть")
                        .font(.system(size: 17, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .glassEffect(in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        }
        .onAppear {
            if selectedTranslationName == nil {
                setupInitialSelection()
            }
        }
    }
    
    private func setupInitialSelection() {
        if isSerial {
            if let firstSeason = result.first {
                selectedSeason = firstSeason.season
                if let firstEpisode = firstSeason.episodes.first {
                    selectedEpisode = firstEpisode.episode
                    selectedTranslationName = firstEpisode.voices.first
                }
            }
        } else if let movie = movieResult {
            selectedTranslationName = movie.voices.first
        }
    }
}
