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
        case .small: return 17
        case .medium: return 21
        case .large: return 25
        }
    }
}

@MainActor
final class SubtitleSettings: ObservableObject {
    static let shared = SubtitleSettings()

    @AppStorage("sloosh_subtitle_font_size") var fontSizeRaw: String = SubtitleFontSize.medium.rawValue

    var fontSize: SubtitleFontSize {
        get {
            SubtitleFontSize(rawValue: fontSizeRaw) ?? .medium
        }
        set {
            fontSizeRaw = newValue.rawValue
            objectWillChange.send()
        }
    }
}
