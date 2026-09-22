import SwiftUI

// MARK: - Нижняя правая панель: скорость | озвучка | качество | субтитры | серии
// Нативные Liquid Glass меню iOS с анимацией трансформации кнопки

struct BottomRowView: View {
    @ObservedObject var vm: PlayerViewModel

    private let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        HStack(spacing: 0) {
            // Скорость воспроизведения
            speedMenu

            // Озвучка / аудиодорожка
            if vm.availableVoiceovers.count > 1 {
                voiceoverMenu
            }

            // Качество видео
            if vm.availableQualities.count > 1 {
                qualityMenu
            }

            // Субтитры
            if !vm.availableSubtitles.isEmpty {
                subtitlesMenu
            }

            // Выбор серий (для сериалов)
            if !vm.isMovie, let series = vm.seriesResult, !series.seasons.isEmpty {
                episodesMenu(series: series)
            }
        }
        .padding(.horizontal, 2)
        .frame(height: 44)
        .clipShape(Capsule())
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Скорость

    private var speedMenu: some View {
        Menu {
            Picker("Скорость", selection: Binding(
                get: { vm.playbackRate },
                set: { vm.setPlaybackRate($0) }
            )) {
                ForEach(speeds, id: \.self) { rate in
                    Text(rateLabel(rate)).tag(rate)
                }
            }
        } label: {
            Text(speedLabel)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .blendMode(.plusLighter)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.priority)
        .accessibilityLabel("Скорость воспроизведения: \(speedLabel)")
    }

    // MARK: - Озвучка

    private var voiceoverMenu: some View {
        Menu {
            Picker("Озвучка", selection: Binding(
                get: { activeVoiceoverIndex ?? -1 },
                set: { idx in
                    if idx >= 0 && idx < vm.availableVoiceovers.count {
                        vm.switchVoiceover(to: vm.availableVoiceovers[idx], at: idx)
                    }
                }
            )) {
                ForEach(Array(vm.availableVoiceovers.enumerated()), id: \.offset) { idx, name in
                    Text(displayTranslationName(name, at: idx, in: vm.availableVoiceovers)).tag(idx)
                }
            }
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .blendMode(.plusLighter)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.priority)
        .accessibilityLabel("Выбор озвучки")
    }

    // MARK: - Качество

    private var qualityMenu: some View {
        Menu {
            Picker("Качество", selection: Binding(
                get: { vm.currentQualityKey ?? "" },
                set: { vm.changeQuality(to: $0) }
            )) {
                ForEach(vm.availableQualities, id: \.key) { q in
                    Text(q.key).tag(q.key)
                }
            }
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .blendMode(.plusLighter)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.priority)
        .accessibilityLabel("Качество видео")
    }

    // MARK: - Субтитры

    private var subtitlesMenu: some View {
        Menu {
            Picker("Субтитры", selection: Binding(
                get: { vm.currentSubtitle?.url ?? "none" },
                set: { url in
                    if url == "none" {
                        vm.setSubtitle(nil)
                    } else if let sub = vm.availableSubtitles.first(where: { $0.url == url }) {
                        vm.setSubtitle(sub)
                    }
                }
            )) {
                Text("Выключены").tag("none")
                ForEach(vm.availableSubtitles, id: \.url) { sub in
                    Text(sub.label).tag(sub.url)
                }
            }
        } label: {
            Image(systemName: vm.currentSubtitle != nil ? "text.bubble.fill" : "text.bubble")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .blendMode(.plusLighter)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.priority)
        .accessibilityLabel(vm.currentSubtitle != nil ? "Субтитры (включены)" : "Субтитры")
    }

    // MARK: - Серии (для сериалов)

    @ViewBuilder
    private func episodesMenu(series: AllohaApiResult) -> some View {
        Menu {
            if series.seasons.count > 1 {
                ForEach(series.seasons.sorted(by: { $0.season < $1.season }), id: \.season) { season in
                    Menu {
                        Picker("Серии", selection: Binding(
                            get: { (vm.currentSeason == season.season) ? (vm.currentEpisode ?? -1) : -1 },
                            set: { ep in
                                if ep >= 0 {
                                    vm.selectEpisode(season: season.season, episode: ep)
                                }
                            }
                        )) {
                            ForEach(season.episodes.sorted(by: { $0.episode < $1.episode }), id: \.episode) { ep in
                                Text("Серия \(ep.episode)").tag(ep.episode)
                            }
                        }
                    } label: {
                        if vm.currentSeason == season.season {
                            Label("Сезон \(season.season)", systemImage: "checkmark")
                        } else {
                            Text("Сезон \(season.season)")
                        }
                    }
                }
            } else if let singleSeason = series.seasons.first {
                Picker("Серии", selection: Binding(
                    get: { vm.currentEpisode ?? -1 },
                    set: { ep in
                        if ep >= 0 {
                            vm.selectEpisode(season: singleSeason.season, episode: ep)
                        }
                    }
                )) {
                    ForEach(singleSeason.episodes.sorted(by: { $0.episode < $1.episode }), id: \.episode) { ep in
                        Text("Серия \(ep.episode)").tag(ep.episode)
                    }
                }
            }
        } label: {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .blendMode(.plusLighter)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuOrder(.priority)
        .accessibilityLabel("Выбор серии")
    }

    // MARK: - Хелперы

    private var speedLabel: String {
        switch vm.playbackRate {
        case 1.0: return "1×"
        case 1.5: return "1.5×"
        case 2.0: return "2×"
        default:  return String(format: "%.2g×", vm.playbackRate)
        }
    }

    private func rateLabel(_ rate: Float) -> String {
        rate == 1.0 ? "Обычная (1×)" : String(format: "%.2g×", rate)
    }

    private var activeVoiceoverIndex: Int? {
        if let current = vm.currentTranslationName {
            if let directIdx = vm.availableVoiceovers.firstIndex(of: current) {
                return directIdx
            }
            if let matchIdx = vm.availableVoiceovers.firstIndex(where: { allohaTranslationNamesMatch($0, current, exactOnly: true) }) {
                return matchIdx
            }
            if let matchIdx = vm.availableVoiceovers.firstIndex(where: { allohaTranslationNamesMatch($0, current, exactOnly: false) }) {
                return matchIdx
            }
        }
        return nil
    }
}
