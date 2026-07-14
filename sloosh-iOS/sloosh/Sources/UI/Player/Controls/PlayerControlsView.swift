import SwiftUI

// MARK: - Полный слой контролов плеера

struct PlayerControlsView: View {
    @ObservedObject var vm: PlayerViewModel
    let onDismiss: () -> Void

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
            .opacity(isSeeking ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: isSeeking)
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // ── Верхний и нижний блоки ───────────────────────
            VStack {
                TopBarView(vm: vm, onDismiss: onDismiss, isInteracting: $isInteracting)
                    .scaleEffect(showControls ? 1.0 : 0.95)
                    .opacity(isSeeking ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isSeeking)
                    .padding(.top, 24) // Увеличенный отступ

                Spacer()

                // ── Нижний блок: инфо слева + правые кнопки + seek bar ───────
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(alignment: .bottom) {
                        PlayerTitleInfoView(vm: vm)
                            .padding(.leading, 16)
                            .padding(.bottom, 4)
                        
                        Spacer()
                        
                        BottomRowView(
                            vm: vm,
                            showVoiceoverSheet: $showVoiceoverSheet,
                            showQualitySheet: $showQualitySheet,
                            showSpeedSheet: $showSpeedSheet,
                            showSubtitleSheet: $showSubtitleSheet
                        )
                        .padding(.trailing, 16)
                    }
                    .opacity(isSeeking ? 0 : 1)
                    .animation(.easeInOut(duration: 0.2), value: isSeeking)

                    SeekBarView(vm: vm, isInteracting: $isInteracting)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 24) // Увеличенный отступ
                }
                .scaleEffect(showControls ? 1.0 : 0.95)
            }
            .ignoresSafeArea(edges: .vertical) // Игнорируем safe area для идеальной симметрии

            // ── Центральные кнопки (ровно по центру экрана) ───
            CenterControlsView(vm: vm)
                .scaleEffect(showControls ? 1.0 : 0.95)
                .opacity(isSeeking ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: isSeeking)
                .ignoresSafeArea()
        }
        // Sheets are now popovers on BottomRowView
        .onChange(of: showVoiceoverSheet) { _, _ in isPopoverOpen = showVoiceoverSheet || showQualitySheet || showSpeedSheet || showSubtitleSheet }
        .onChange(of: showQualitySheet)   { _, _ in isPopoverOpen = showVoiceoverSheet || showQualitySheet || showSpeedSheet || showSubtitleSheet }
        .onChange(of: showSpeedSheet)     { _, _ in isPopoverOpen = showVoiceoverSheet || showQualitySheet || showSpeedSheet || showSubtitleSheet }
        .onChange(of: showSubtitleSheet)  { _, _ in isPopoverOpen = showVoiceoverSheet || showQualitySheet || showSpeedSheet || showSubtitleSheet }
    }
}

// MARK: - Инфо о текущем видео (Логотип, Сезон, Серия)

struct PlayerTitleInfoView: View {
    @ObservedObject var vm: PlayerViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Логотип или текстовое название
            if let logoUrl = vm.displayLogoUrl {
                AsyncCachedImage(url: logoUrl) {
                    fallbackTextView
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 320, maxHeight: 56, alignment: .leading)
                        .shadow(color: .black.opacity(0.4), radius: 4, x: 0, y: 2)
                } fallback: {
                    fallbackTextView
                }
            } else {
                fallbackTextView
            }
            
            // Сезон и Серия (если это сериал)
            if !vm.isMovie, let season = vm.currentSeason, let episode = vm.currentEpisode {
                Text("\(season) сезон, \(episode) серия")
                    .font(.footnote)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.85))
                    .blendMode(.plusLighter)
                    .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            }
        }
    }
    
    private var fallbackTextView: some View {
        Text(vm.fallbackTitle)
            .font(.title3)
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
    }
}
