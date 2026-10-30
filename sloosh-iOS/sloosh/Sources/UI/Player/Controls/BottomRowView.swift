import SwiftUI

// MARK: - Нижняя правая панель: скорость | качество | субтитры
// Нативные Liquid Glass меню iOS с анимацией трансформации кнопки
// Оптимизировано: View изолировано через Equatable от ежесекундного тика currentTime в PlayerViewModel

struct BottomRowView: View, Equatable {
    let vm: PlayerViewModel
    let playbackRate: Float
    let availableQualities: [PlayerViewModel.PlaybackQualityOption]
    let currentQualityKey: String?
    let availableSubtitles: [PlaybackSubtitle]
    let currentSubtitleUrl: String?
    let subtitleFontSize: SubtitleFontSize
    var onInteraction: (() -> Void)? = nil

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    static func == (lhs: BottomRowView, rhs: BottomRowView) -> Bool {
        lhs.playbackRate == rhs.playbackRate &&
        lhs.currentQualityKey == rhs.currentQualityKey &&
        lhs.currentSubtitleUrl == rhs.currentSubtitleUrl &&
        lhs.subtitleFontSize == rhs.subtitleFontSize &&
        lhs.availableQualities == rhs.availableQualities &&
        lhs.availableSubtitles == rhs.availableSubtitles
    }

    var body: some View {
        HStack(spacing: 0) {
            // Скорость воспроизведения (иконка спидометра + 1.0x)
            speedMenu

            // Качество видео (иконка шестеренки + 1080p, 720p, Авто)
            if availableQualities.count > 1 {
                qualityMenu
            }

            // Субтитры
            if !availableSubtitles.isEmpty {
                subtitlesMenu
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
        .tint(.white)
    }

    // MARK: - Скорость (спидометр + 1.0x)

    private var speedMenu: some View {
        Menu {
            Picker("Скорость", selection: Binding(
                get: { playbackRate },
                set: { rate in
                    vm.setPlaybackRate(rate)
                    onInteraction?()
                }
            )) {
                ForEach(speeds, id: \.self) { rate in
                    Text(rateLabel(rate)).tag(rate)
                }
            }
        } label: {
            HStack(spacing: 4.5) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 13, weight: .medium))
                Text(speedLabel)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.92))
            .glassForeground()
            .padding(.horizontal, 10)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glassPress)
        .menuOrder(.priority)
        .accessibilityLabel("Скорость воспроизведения: \(speedLabel)")
    }

    // MARK: - Качество (шестеренка + 1080p, 720p, Авто)

    private var qualityMenu: some View {
        Menu {
            Picker("Качество", selection: Binding(
                get: { currentQualityKey ?? "" },
                set: { qKey in
                    vm.changeQuality(to: qKey)
                    onInteraction?()
                }
            )) {
                ForEach(availableQualities, id: \.key) { q in
                    Text(q.key).tag(q.key)
                }
            }
        } label: {
            HStack(spacing: 4.5) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                Text(qualityLabel)
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(.white.opacity(0.92))
            .glassForeground()
            .padding(.horizontal, 10)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glassPress)
        .menuOrder(.priority)
        .accessibilityLabel("Качество видео: \(qualityLabel)")
    }

    // MARK: - Субтитры

    private var subtitlesMenu: some View {
        Menu {
            Section {
                Picker("Субтитры", selection: Binding(
                    get: { currentSubtitleUrl ?? "none" },
                    set: { url in
                        if url == "none" {
                            vm.setSubtitle(nil)
                        } else if let sub = availableSubtitles.first(where: { $0.url == url }) {
                            vm.setSubtitle(sub)
                        }
                        onInteraction?()
                    }
                )) {
                    Text("Выключены").tag("none")
                    ForEach(availableSubtitles, id: \.url) { sub in
                        Text(sub.label).tag(sub.url)
                    }
                }
            }

            Section {
                Menu {
                    Picker("Размер", selection: Binding(
                        get: { subtitleFontSize },
                        set: { size in
                            withAnimation(.easeInOut(duration: 0.15)) {
                                SubtitleSettings.shared.fontSize = size
                            }
                            onInteraction?()
                        }
                    )) {
                        ForEach(SubtitleFontSize.allCases) { size in
                            Text(size.title).tag(size)
                        }
                    }
                } label: {
                    Label("Размер текста", systemImage: "textformat.size")
                }
            }
        } label: {
            Image(systemName: currentSubtitleUrl != nil ? "captions.bubble.fill" : "captions.bubble")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(currentSubtitleUrl != nil ? .white : .white.opacity(0.85))
                .glassForeground()
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.glassPress)
        .menuOrder(.priority)
        .accessibilityLabel(currentSubtitleUrl != nil ? "Субтитры (включены)" : "Субтитры")
    }

    // MARK: - Хелперы

    private var speedLabel: String {
        switch playbackRate {
        case 1.0: return "1.0x"
        case 0.5: return "0.5x"
        case 0.75: return "0.75x"
        case 1.25: return "1.25x"
        case 1.5: return "1.5x"
        case 2.0: return "2.0x"
        default:
            if playbackRate == floor(playbackRate) {
                return String(format: "%.1fx", playbackRate)
            } else {
                return String(format: "%.2gx", playbackRate)
            }
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        switch rate {
        case 1.0: return "Обычная (1.0x)"
        case 0.5: return "0.5x"
        case 0.75: return "0.75x"
        case 1.25: return "1.25x"
        case 1.5: return "1.5x"
        case 2.0: return "2.0x"
        default:  return String(format: "%.2gx", rate)
        }
    }

    private var qualityLabel: String {
        guard let key = currentQualityKey, !key.isEmpty else {
            return "Авто"
        }
        let lower = key.lowercased()
        if lower.contains("авто") || lower.contains("auto") {
            return "Авто"
        }
        if lower.contains("1080") {
            return "1080p"
        }
        if lower.contains("720") {
            return "720p"
        }
        if lower.contains("480") {
            return "480p"
        }
        if lower.contains("360") {
            return "360p"
        }
        if lower.contains("4k") || lower.contains("2160") {
            return "4K"
        }
        if key.hasSuffix("p") || key.hasSuffix("P") {
            return key
        }
        return "\(key)p"
    }
}
