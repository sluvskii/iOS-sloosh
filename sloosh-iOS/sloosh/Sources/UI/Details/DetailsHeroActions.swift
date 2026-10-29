import SwiftUI

/// Shared by the real actions and loading skeleton so the hero does not jump
/// when details arrive. Equal side controls keep Play optically centered.
enum DetailsHeroActionMetrics {
    static let primaryDiameter: CGFloat = 72
    static let secondaryDiameter: CGFloat = 52
    static let spacing: CGFloat = 22
}

struct DetailsHeroButton<Label: View>: View {
    let isPrimary: Bool
    let action: () -> Void
    private let label: () -> Label
    private let size: CGFloat?
    private let usesGlass: Bool

    init(isPrimary: Bool = false, size: CGFloat? = nil, usesGlass: Bool = false, action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.isPrimary = isPrimary
        self.size = size
        self.usesGlass = usesGlass
        self.action = action
        self.label = label
    }

    private var diameter: CGFloat {
        size ?? (isPrimary ? DetailsHeroActionMetrics.primaryDiameter : DetailsHeroActionMetrics.secondaryDiameter)
    }

    var body: some View {
        if isPrimary {
            Button(action: action) {
                Circle()
                    .fill(.white)
                    .overlay {
                        label()
                            .foregroundStyle(.white)
                            .blendMode(.destinationOut)
                    }
                    // Flatten ONLY the circle and symbol: the triangle removes
                    // alpha from the disc, revealing the actual screen beneath.
                    .compositingGroup()
                    .frame(width: diameter, height: diameter)
                    // Keep the transparent triangle part of the tappable button.
                    .contentShape(Circle())
            }
            // No glass behind the disc: it would fill the transparent cutout.
            .buttonStyle(.plain)
        } else if usesGlass {
            Button(action: action) {
                secondaryLabel
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.glassPress)
        } else {
            Button(action: action) {
                secondaryLabel
                    .background(Circle().fill(.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
    }

    private var secondaryLabel: some View {
        label()
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
    }
}

/// Isolate frequent progress updates from DetailsView's image/hero hierarchy.
struct DetailsHeroDownloadButton: View {
    let details: MediaDetailsDto
    let onAction: (DownloadItem?) -> Void
    @ObservedObject private var manager = DownloadManager.shared

    private var item: DownloadItem? {
        let kpId = [details.ids?.kp, details.externalIds?.kp].compactMap { $0 }.first { $0 > 0 } ?? 0
        guard kpId > 0 else { return nil }
        return manager.getDownloadItem(kpId: kpId, season: nil, episode: nil)
    }

    private var accessibilityTitle: String {
        switch item?.status {
        case .downloading, .pending: return "Приостановить загрузку"
        case .paused: return "Продолжить загрузку"
        case .completed: return "Удалить загрузку"
        case .failed: return "Повторить загрузку"
        case nil: return "Скачать"
        }
    }

    private var accessibilityStatus: String {
        switch item?.status {
        case .downloading:
            let progress = min(1, max(0, item?.progress ?? 0))
            return "Загружено \(Int(progress * 100)) процентов"
        case .pending: return "Ожидание загрузки"
        case .paused: return "Загрузка приостановлена"
        case .completed: return "Сохранено на устройстве"
        case .failed: return "Не удалось загрузить"
        case nil: return ""
        }
    }

    var body: some View {
        let currentItem = item
        DetailsHeroButton {
            onAction(currentItem)
        } label: {
            icon(for: currentItem)
                .foregroundStyle(.white)
        }
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityStatus)
        .accessibilityIdentifier("details.download")
    }

    @ViewBuilder
    private func icon(for item: DownloadItem?) -> some View {
        switch item?.status {
        case .downloading, .paused:
            ZStack {
                Circle().stroke(.white.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(1, max(0, item?.progress ?? 0)))
                    .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: item?.status == .paused ? "arrow.down.to.line" : "pause.fill")
                    .font(.system(size: 9, weight: .semibold))
            }
            .frame(width: 24, height: 24)
        case .pending:
            ProgressView().controlSize(.small).tint(.white)
        case .completed:
            Image(systemName: "checkmark").font(.system(size: 20, weight: .semibold))
        case .failed:
            Image(systemName: "arrow.clockwise").font(.system(size: 20, weight: .semibold))
        case nil:
            Image(systemName: "arrow.down.to.line").font(.system(size: 22, weight: .semibold))
        }
    }
}
