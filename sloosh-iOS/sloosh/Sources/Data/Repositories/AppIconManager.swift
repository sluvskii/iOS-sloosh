import SwiftUI
import UIKit

public enum AppIconOption: String, CaseIterable, Identifiable {
    case `default` = "default"
    case cyrillic = "AppIcon-Cyrillic"
    case glyph = "AppIcon-Glyph"
    case cinema = "AppIcon-Cinema"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .default:
            return "Основная"
        case .cyrillic:
            return "Кириллица"
        case .glyph:
            return "Символ"
        case .cinema:
            return "Кинотеатр"
        }
    }

    public var previewAsset: String {
        switch self {
        case .default:
            return "AppIconPreview-Default"
        case .cyrillic:
            return "AppIconPreview-Cyrillic"
        case .glyph:
            return "AppIconPreview-Glyph"
        case .cinema:
            return "AppIconPreview-Cinema"
        }
    }

    public var iconName: String? {
        switch self {
        case .default:
            return nil
        default:
            return rawValue
        }
    }
}

@MainActor
public final class AppIconManager: ObservableObject {
    public static let shared = AppIconManager()

    @Published public private(set) var currentIcon: AppIconOption = .default

    private init() {
        refreshCurrentIcon()
    }

    public func refreshCurrentIcon() {
        if let name = UIApplication.shared.alternateIconName {
            currentIcon = AppIconOption(rawValue: name) ?? .default
        } else {
            currentIcon = .default
        }
    }

    public func selectIcon(_ option: AppIconOption) {
        guard UIApplication.shared.supportsAlternateIcons else { return }
        guard currentIcon != option else { return }

        let targetName = option.iconName
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        UIApplication.shared.setAlternateIconName(targetName) { [weak self] error in
            if let error = error {
                print("[AppIcon] Failed to set alternate icon: \(error.localizedDescription)")
            }
            Task { @MainActor in
                self?.refreshCurrentIcon()
            }
        }
    }
}
