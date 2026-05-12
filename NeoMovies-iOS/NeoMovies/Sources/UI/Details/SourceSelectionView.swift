import SwiftUI

struct SourceSelectionView: View {
    let result: AllohaApiResult
    let onPlay: (String) -> Void
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedSeason: Int?
    @State private var selectedEpisode: Int?
    @State private var selectedTranslationName: String?
    
    // Computed properties for ALL unique values
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
    
    // Available checking
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
    
    // Logic
    func seasonHasTranslation(season: Int, t: String) -> Bool {
        guard let s = result.seasons.first(where: { $0.season == season }) else { return false }
        return s.episodes.contains { ep in ep.translations.contains { $0.name == t } }
    }

    func episodeHasTranslation(season: Int, episode: Int, t: String) -> Bool {
        guard let s = result.seasons.first(where: { $0.season == season }),
              let ep = s.episodes.first(where: { $0.episode == episode }) else { return false }
        return ep.translations.contains { $0.name == t }
    }
    
    // Selection actions
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
    
    func playSelected() {
        if result.isSerial {
            guard let s = selectedSeason, let e = selectedEpisode, let tName = selectedTranslationName else { return }
            guard let seasonObj = result.seasons.first(where: { $0.season == s }),
                  let epObj = seasonObj.episodes.first(where: { $0.episode == e }),
                  let translation = epObj.translations.first(where: { $0.name == tName }) else { return }
            onPlay(translation.iframeUrl)
            presentationMode.wrappedValue.dismiss()
        } else if let movie = result.movie {
            guard let tName = selectedTranslationName,
                  let translation = movie.translations.first(where: { $0.name == tName }) else { return }
            onPlay(translation.iframeUrl)
            presentationMode.wrappedValue.dismiss()
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if !allTranslations.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Озвучка")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(allTranslations, id: \.self) { tName in
                                        ChipView(
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
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Сезон")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                
                                FlowLayout(spacing: 8) {
                                    ForEach(allSeasons, id: \.self) { s in
                                        ChipView(
                                            title: "Сезон \(s)",
                                            isSelected: selectedSeason == s,
                                            isAvailable: isSeasonAvailable(s)
                                        ) {
                                            selectSeason(s)
                                        }
                                    }
                                }
                            }
                            
                            if !allEpisodes.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Серия")
                                        .font(.headline)
                                        .foregroundColor(.secondary)
                                    
                                    FlowLayout(spacing: 8) {
                                        ForEach(allEpisodes, id: \.self) { e in
                                            ChipView(
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
                        
                        // Bottom padding for button
                        Color.clear.frame(height: 80)
                    }
                    .padding()
                }
                
                // Play Button
                Button(action: {
                    playSelected()
                }) {
                    Text("Далее")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.neoAccent)
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
                .padding(.top, 32)
                .background(
                    LinearGradient(gradient: Gradient(colors: [Color(UIColor.systemBackground).opacity(0), Color(UIColor.systemBackground)]), startPoint: .top, endPoint: .bottom)
                )
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(result.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .onAppear {
            setupInitialSelection()
        }
    }
}

struct ChipView: View {
    let title: String
    let isSelected: Bool
    let isAvailable: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .medium))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.neoAccent : Color(UIColor.secondarySystemBackground)
                )
                .foregroundColor(
                    isSelected ? .black : (isAvailable ? .primary : .secondary)
                )
                .clipShape(Capsule())
                .opacity(isAvailable ? 1.0 : 0.4)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.clear : Color(UIColor.separator).opacity(0.3), lineWidth: 1)
                )
        }
    }
}

@available(iOS 16.0, *)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? UIScreen.main.bounds.width, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let point = result.points[index]
            subview.place(at: CGPoint(x: point.x + bounds.minX, y: point.y + bounds.minY), proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var points: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Layout.Subviews, spacing: CGFloat) {
            var currentPoint = CGPoint.zero
            var rowHeight: CGFloat = 0
            var points: [CGPoint] = []
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentPoint.x + size.width > maxWidth, currentPoint.x > 0 {
                    currentPoint.x = 0
                    currentPoint.y += rowHeight + spacing
                    rowHeight = 0
                }
                
                points.append(currentPoint)
                currentPoint.x += size.width + spacing
                rowHeight = max(rowHeight, size.height)
            }
            
            self.points = points
            self.size = CGSize(width: maxWidth, height: currentPoint.y + rowHeight)
        }
    }
}
