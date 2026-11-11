import Foundation

/// Availability of voiceovers for the currently selected season/episode.
///
/// Kept free of SwiftUI, networking and provider parsing so the same rules can be
/// verified by the standalone CI tests. Provider episode metadata is sometimes
/// sparse: an empty episode or season list must not dim every voiceover.
struct TranslationAvailabilityPolicy {
    let isSerial: Bool
    let movieNames: Set<String>
    let seasonNames: [Int: Set<String>]
    let episodeNames: [Int: [Int: Set<String>]]

    /// Names stored in `episodeNames`/`seasonNames` are already canonical
    /// (matched against the full voiceover list during preparation), so a plain
    /// set lookup is enough here.
    func isAvailable(name: String, season: Int?, episode: Int?) -> Bool {
        guard isSerial else { return movieNames.contains(name) }
        guard let season else { return true }

        if let episode, let names = episodeNames[season]?[episode], !names.isEmpty {
            return names.contains(name)
        }
        if let names = seasonNames[season], !names.isEmpty {
            return names.contains(name)
        }
        // No metadata at all for this season/episode: keep everything selectable
        // instead of dimming the whole row.
        return true
    }
}
