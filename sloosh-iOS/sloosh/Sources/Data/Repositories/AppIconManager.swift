import SwiftUI
import UIKit

public enum AppIconOption: String, CaseIterable, Identifiable {
    case `default` = "default"
    case glyph = "AppIcon-Glyph"
    case dark = "AppIcon-Dark"
    case neon = "AppIcon-Neon"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .default:
            return "Основная"
        case .glyph:
            return "Символ"
        case .dark:
            return "Тёмная"
        case .neon:
            return "Неон"
        }
    }

    public var subtitle: String {
        switch self {
        case .default:
            return "Типографика Sloosh на акцентном фоне"
        case .glyph:
            return "Классический символ Sloosh"
        case .dark:
            return "Глубокий матовый чёрный"
        case .neon:
            return "Кибер-зелёный неоновый стиль"
        }
    }

    public var previewAsset: String {
        switch self {
        case .default:
            return "AppIconPreview-Default"
        case .glyph:
            return "AppIconPreview-Glyph"
        case .dark:
            return "AppIconPreview-Dark"
        case .neon:
            return "AppIconPreview-Neon"
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
