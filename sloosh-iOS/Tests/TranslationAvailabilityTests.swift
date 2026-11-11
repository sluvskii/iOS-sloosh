import Foundation

@main
struct TranslationAvailabilityTests {
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ description: String) {
            precondition(condition, description)
            count += 1
        }

        let serial = TranslationAvailabilityPolicy(
            isSerial: true,
            movieNames: [],
            seasonNames: [1: ["LostFilm", "HDrezka"]],
            episodeNames: [1: [1: ["LostFilm"], 2: ["LostFilm", "HDrezka"]]]
        )

        check(serial.isAvailable(name: "LostFilm", season: 1, episode: 1), "Voiceover present in the episode")
        check(!serial.isAvailable(name: "HDrezka", season: 1, episode: 1), "Voiceover missing from the episode is dimmed")
        check(serial.isAvailable(name: "HDrezka", season: 1, episode: 2), "Availability follows the selected episode")
        check(!serial.isAvailable(name: "Кубик в кубе", season: 1, episode: 2), "Unknown voiceover is dimmed")

        check(serial.isAvailable(name: "HDrezka", season: 1, episode: 3), "Sparse episode metadata falls back to the season")
        check(serial.isAvailable(name: "Кубик в кубе", season: 2, episode: 1), "Missing season metadata keeps every voiceover selectable")
        check(serial.isAvailable(name: "Кубик в кубе", season: nil, episode: nil), "No season selected keeps every voiceover selectable")

        let emptyEpisodeLists = TranslationAvailabilityPolicy(
            isSerial: true,
            movieNames: [],
            seasonNames: [1: ["LostFilm"]],
            episodeNames: [1: [1: [], 2: []]]
        )
        check(emptyEpisodeLists.isAvailable(name: "LostFilm", season: 1, episode: 1), "Empty episode list falls back to the season instead of dimming everything")
        check(!emptyEpisodeLists.isAvailable(name: "HDrezka", season: 1, episode: 1), "Season fallback still dims unavailable voiceovers")

        let movie = TranslationAvailabilityPolicy(
            isSerial: false,
            movieNames: ["LostFilm"],
            seasonNames: [:],
            episodeNames: [:]
        )
        check(movie.isAvailable(name: "LostFilm", season: nil, episode: nil), "Movie voiceover is available")
        check(!movie.isAvailable(name: "HDrezka", season: nil, episode: nil), "Movie voiceover that is missing is dimmed")

        print("PASS: \(count) translation availability cases")
    }
}
