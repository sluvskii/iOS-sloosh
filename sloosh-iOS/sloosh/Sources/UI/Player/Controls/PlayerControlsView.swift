import SwiftUI

// MARK: - Полный слой контролов плеера

struct PlayerControlsView: View {
    @ObservedObject var vm: PlayerViewModel
    let onDismiss: () -> Void
    var onBackgroundTap: (() -> Void)? = nil

    @State private var showVoiceoverSheet = false
    @State private var showQualitySheet = false
    @State private var showSpeedSheet = false
    @State private var showSubtitleSheet = false
    @Binding var isInteracting: Bool
    @Binding var isPopoverOpen: Bool
    var showControls: Bool
    var isSeeking: Bool

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
                    TopBarView(vm: vm, onDismiss: onDismiss, isInteracting: $isInteracting)
                        .padding(.top, 24) // Увеличенный отступ
                        .offset(y: showControls ? 0 : -8)
                        .opacity(isSeeking ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: isSeeking)

                    Spacer()

                    // ── Нижний блок: инфо слева + правые кнопки + seek bar ───────
                    VStack(alignment: .trailing, spacing: 8) {
                        HStack(alignment: .bottom) {
                            PlayerTitleInfoView(vm: vm)
                                .padding(.leading, 8)
                                .padding(.bottom, 4)
                            
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
                                    showVoiceoverSheet: $showVoiceoverSheet,
                                    showQualitySheet: $showQualitySheet,
                                    showSpeedSheet: $showSpeedSheet,
                                    showSubtitleSheet: $showSubtitleSheet
                                )
                            }
                            .padding(.trailing, 8)
                        }
                        .opacity(isSeeking ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: isSeeking)

                        SeekBarView(vm: vm, isInteracting: $isInteracting)
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
        }
        // Sheets are now popovers on BottomRowView
        .onChange(of: showVoiceoverSheet) { _, _ in isPopoverOpen = showVoiceoverSheet || showQualitySheet || showSpeedSheet || showSubtitleSheet }
        .onChange(of: showQualitySheet)   { _, _ in isPopoverOpen = showVoiceoverSheet || showQualitySheet || showSpeedSheet || showSubtitleSheet }
        .onChange(of: showSpeedSheet)     { _, _ in isPopoverOpen = showVoiceoverSheet || showQualitySheet || showSpeedSheet || showSubtitleSheet }
        .onChange(of: showSubtitleSheet)  { _, _ in isPopoverOpen = showVoiceoverSheet || showQualitySheet || showSpeedSheet || showSubtitleSheet }
    }
}

// MARK: - Инфо о текущем видео снизу слева (Озвучка, Сезон, Серия)

struct PlayerTitleInfoView: View {
    @ObservedObject var vm: PlayerViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Текущая озвучка (сверху)
            if let voiceoverName = displayVoiceoverText {
                Text(voiceoverName)
                    .font(.system(size: vm.isMovie ? 24 : 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .blendMode(.plusLighter)
                    .lineLimit(1)
            }
            
            // Сезон и Серия (снизу, если сериал)
            if !vm.isMovie, let season = vm.currentSeason, let episode = vm.currentEpisode {
                Text("\(season) сезон, \(episode) серия")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                    .blendMode(.plusLighter)
                    .lineLimit(1)
            }
        }
    }
    
    private var displayVoiceoverText: String? {
        let raw = vm.currentTranslationName ?? vm.availableVoiceovers.first
        guard let r = raw, !r.isEmpty else { return nil }
        return cleanTranslationName(r)
    }
}
