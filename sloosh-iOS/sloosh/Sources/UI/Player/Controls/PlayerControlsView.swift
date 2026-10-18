import SwiftUI

// MARK: - Полный слой контролов плеера

struct PlayerControlsView: View {
    @ObservedObject var vm: PlayerViewModel
    let onDismiss: () -> Void
    var onBackgroundTap: (() -> Void)? = nil

    @Binding var isInteracting: Bool
    var showControls: Bool
    var isSeeking: Bool
    var onInteraction: (() -> Void)? = nil

    @ObservedObject private var subtitleSettings = SubtitleSettings.shared

    var body: some View {
        ZStack {
            // Лёгкое затемнение фона, когда контролы видны
            LinearGradient(
                colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.45)],
                startPoint: .top,
                endPoint: .bottom
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onBackgroundTap?()
            }
            .opacity(showControls && !isSeeking ? 1 : 0)
            .animation(.easeInOut(duration: 0.24), value: showControls)
            .animation(.easeInOut(duration: 0.2), value: isSeeking)
            .ignoresSafeArea()

            // ── Элементы управления с мягким нативным блюром ──
            ZStack {
                // ── Верхний и нижний блоки ───────────────────────
                VStack {
                    TopBarView(vm: vm, onDismiss: onDismiss, isInteracting: $isInteracting, onInteraction: onInteraction)
                        .padding(.top, 24) // Увеличенный отступ
                        .offset(y: showControls ? 0 : -8)
                        .opacity(isSeeking ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: isSeeking)

                    Spacer()

                    // ── Нижний блок: инфо слева + правые кнопки + seek bar ───────
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(alignment: .bottom) {
                            PlayerTitleInfoView(
                                vm: vm,
                                currentTranslationName: vm.currentTranslationName,
                                availableVoiceovers: vm.availableVoiceovers,
                                onInteraction: onInteraction
                            )
                            .equatable()
                            .padding(.leading, 8)
                            
                            Spacer()
                            
                            VStack(alignment: .trailing, spacing: 8) {
                                if vm.showSkipIntro {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        if let range = vm.introRange {
                                            vm.seek(to: range.upperBound + 0.5)
                                            vm.showSkipIntro = false
                                            vm.introRange = nil
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "forward.end.fill")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("Пропустить заставку")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 18)
                                        .frame(height: 44)
                                        .clipShape(Capsule())
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                    }
                                    .buttonStyle(.glassPress)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                }
                                
                                if vm.showSkipOutro {
                                    Button {
                                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                        if let range = vm.outroRange {
                                            vm.seek(to: range.upperBound + 0.5)
                                            vm.showSkipOutro = false
                                            vm.outroRange = nil
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "forward.end.fill")
                                                .font(.system(size: 13, weight: .semibold))
                                            Text("Пропустить титры")
                                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                        }
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 18)
                                        .frame(height: 44)
                                        .clipShape(Capsule())
                                        .glassEffect(.regular.interactive(), in: .capsule)
                                    }
                                    .buttonStyle(.glassPress)
                                    .transition(.move(edge: .trailing).combined(with: .opacity))
                                }
                                
                                BottomRowView(
                                    vm: vm,
                                    playbackRate: vm.playbackRate,
                                    availableQualities: vm.availableQualities,
                                    currentQualityKey: vm.currentQualityKey,
                                    availableSubtitles: vm.availableSubtitles,
                                    currentSubtitleUrl: vm.currentSubtitle?.url,
                                    subtitleFontSize: subtitleSettings.fontSize,
                                    onInteraction: onInteraction
                                )
                                .equatable()
                            }
                            .padding(.trailing, 8)
                        }
                        .opacity(isSeeking ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: isSeeking)

                        SeekBarView(vm: vm, timeTracker: vm.timeTracker, isInteracting: $isInteracting)
                            .padding(.horizontal, 8)
                            .padding(.bottom, 24) // Увеличенный отступ
                    }
                    .offset(y: showControls ? 0 : 8)
                }
                .ignoresSafeArea(edges: .vertical) // Игнорируем safe area для идеальной симметрии

                // ── Центральные кнопки (ровно по центру экрана) ───
                CenterControlsView(vm: vm)
                    .scaleEffect(showControls ? 1.0 : 0.90)
                    .opacity(isSeeking ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isSeeking)
                    .ignoresSafeArea()
            }
            .opacity(showControls ? 1 : 0)
            .blur(radius: showControls ? 0 : 16)
            .animation(.easeInOut(duration: 0.24), value: showControls)
            .tint(.white)
        }
    }
}

// MARK: - Инфо о текущем видео снизу слева (Капсула озвучки с логотипом студии/флагом)
// Оптимизировано: изолировано через Equatable от ежесекундного тика времени воспроизведения

struct PlayerTitleInfoView: View, Equatable {
    let vm: PlayerViewModel
    let currentTranslationName: String?
    let availableVoiceovers: [String]
    var onInteraction: (() -> Void)? = nil

    static func == (lhs: PlayerTitleInfoView, rhs: PlayerTitleInfoView) -> Bool {
        lhs.currentTranslationName == rhs.currentTranslationName &&
        lhs.availableVoiceovers == rhs.availableVoiceovers
    }

    var body: some View {
        if let info = activeVoiceoverInfo {
            voiceoverCapsule(info: info)
        }
    }

    // MARK: - Капсула озвучки

    @ViewBuilder
    private func voiceoverCapsule(info: VoiceoverDisplayInfo) -> some View {
        if availableVoiceovers.count > 1 {
            Menu {
                Picker("Озвучка", selection: Binding(
                    get: { activeVoiceoverIndex ?? -1 },
                    set: { idx in
                        if idx >= 0 && idx < availableVoiceovers.count {
                            vm.switchVoiceover(to: availableVoiceovers[idx], at: idx)
                        }
                        onInteraction?()
                    }
                )) {
                    ForEach(Array(availableVoiceovers.enumerated()), id: \.offset) { idx, name in
                        let itemStudio = DubbingStudio.detect(from: name)
                        let itemTitle = displayTranslationName(name, at: idx, in: availableVoiceovers)
                        let itemFlag = LanguageFlag.detect(from: name + " " + itemTitle)
                        if let itemStudio, itemStudio.hasAsset {
                            Label(LanguageFlag.stripLeadingEmoji(from: itemTitle), image: itemStudio.assetName).tag(idx)
                        } else if itemFlag.hasAsset {
                            Label(LanguageFlag.stripLeadingEmoji(from: itemTitle), image: itemFlag.assetName).tag(idx)
                        } else {
                            Text(itemTitle).tag(idx)
                        }
                    }
                }
            } label: {
                voiceoverCapsuleContent(info: info, isInteractive: true)
            }
            .menuOrder(.priority)
            .accessibilityLabel("Выбор озвучки: \(info.title)")
        } else {
            voiceoverCapsuleContent(info: info, isInteractive: false)
                .accessibilityLabel("Озвучка: \(info.title)")
        }
    }

    private func voiceoverCapsuleContent(info: VoiceoverDisplayInfo, isInteractive: Bool) -> some View {
        HStack(spacing: 7) {
            // Иконка: логотип студии или круглый флаг
            if let studio = info.studio, studio.hasAsset {
                Image(studio.assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            } else if info.flag.hasAsset {
                Image(info.flag.assetName)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
                    )
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22)
            }

            // Название озвучки
            Text(info.title)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)

            // Индикатор возможности выбора
            if isInteractive {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(.leading, (info.studio?.hasAsset == true || info.flag.hasAsset) ? 10 : 13)
        .padding(.trailing, isInteractive ? 11 : 13)
        .frame(height: 44)
        .clipShape(Capsule())
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Хелперы и Модели

    private struct VoiceoverDisplayInfo {
        let title: String
        let studio: DubbingStudio?
        let flag: LanguageFlag
    }

    private var activeVoiceoverInfo: VoiceoverDisplayInfo? {
        guard let raw = currentTranslationName ?? availableVoiceovers.first, !raw.isEmpty else {
            return nil
        }
        let idx = activeVoiceoverIndex ?? 0
        let formatted = displayTranslationName(raw, at: idx, in: availableVoiceovers)
        let studio = DubbingStudio.detect(from: raw)
        let flag = LanguageFlag.detect(from: raw + " " + formatted)
        let title = LanguageFlag.stripLeadingEmoji(from: formatted)
        return VoiceoverDisplayInfo(title: title, studio: studio, flag: flag)
    }

    private var activeVoiceoverIndex: Int? {
        if let current = currentTranslationName {
            if let directIdx = availableVoiceovers.firstIndex(of: current) {
                return directIdx
            }
            if let matchIdx = availableVoiceovers.firstIndex(where: { allohaTranslationNamesMatch($0, current, exactOnly: true) }) {
                return matchIdx
            }
            if let matchIdx = availableVoiceovers.firstIndex(where: { allohaTranslationNamesMatch($0, current, exactOnly: false) }) {
                return matchIdx
            }
        }
        return availableVoiceovers.isEmpty ? nil : 0
    }
}
