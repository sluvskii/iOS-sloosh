import SwiftUI
import Combine

enum SubtitleFontSize: String, CaseIterable, Identifiable, Codable {
    case small = "Маленький"
    case medium = "Стандартный"
    case large = "Крупный"

    var id: String { rawValue }
    var title: String { rawValue }

    var pointSize: CGFloat {
        switch self {
        case .small: return 18
        case .medium: return 24
        case .large: return 30
        }
    }
}

@MainActor
final class SubtitleSettings: ObservableObject {
    static let shared = SubtitleSettings()

    private static let key = "sloosh_subtitle_font_size"

    @Published var fontSize: SubtitleFontSize {
        didSet {
            UserDefaults.standard.set(fontSize.rawValue, forKey: Self.key)
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Self.key) ?? SubtitleFontSize.medium.rawValue
        self.fontSize = SubtitleFontSize(rawValue: saved) ?? .medium
    }
}
