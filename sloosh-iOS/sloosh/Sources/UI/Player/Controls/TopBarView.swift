import SwiftUI
import UIKit
import AVKit
import MediaPlayer
import TipKit

// MARK: - Верхняя панель: [X | PiP | AirPlay]    [Логотип / Сезон]      [Ножницы] [Замок]

struct TopBarView: View {
    @ObservedObject var vm: PlayerViewModel
    let onDismiss: () -> Void
    @Binding var isInteracting: Bool
    var onInteraction: (() -> Void)? = nil

    @StateObject private var watchPartyRepo = WatchPartyRepository.shared
    @State private var showFriendPicker = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                // Логотип проекта или название фильма строго по центру на оси кнопок (высота 44)
                centerLogoView
                    .frame(height: 44)
                    .padding(.leading, 156)
                    .padding(.trailing, watchPartyRepo.isConnected ? 208 : 156)
                    .allowsHitTesting(false)
                    .animation(.spring(response: 0.35, dampingFraction: 0.82), value: watchPartyRepo.isConnected)

                // Левая группа: закрыть + (PiP | AirPlay) и правая группа: создать момент + блокировка (высота 44)
                HStack(alignment: .center, spacing: 8) {
                    closeButton
                    dualActionsGroup
                    Spacer()
                    watchPartyButton
                        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: watchPartyRepo.isConnected)
                    clipButton
                    lockButton
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 44)

            // Кнопка выбора сезона и серии (только для сериалов) — аккуратно под строкой кнопок, не смещая логотип
            if !vm.isMovie, let season = vm.currentSeason, let episode = vm.currentEpisode {
                seasonEpisodeButton(season: season, episode: episode)
            }
        }
    }

    // MARK: - Центральный логотип

    private var centerLogoView: some View {
        Group {
            if let logoUrl = vm.displayLogoUrl {
                AsyncCachedImage(url: logoUrl) {
                    fallbackTextView
                } content: { image in
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 36)
                        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
                } fallback: {
                    fallbackTextView
                }
            } else {
                fallbackTextView
            }
        }
        .frame(maxWidth: 240)
    }

    private var fallbackTextView: some View {
        Text(vm.fallbackTitle)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.92))
            .lineLimit(1)
    }

    // MARK: - Компактная кнопка выбора сезона и серии прямо под строкой кнопок

    @ViewBuilder
    private func seasonEpisodeButton(season: Int, episode: Int) -> some View {
        if hasEpisodeSelection, let series = vm.seriesResult {
            Menu {
                if series.seasons.count > 1 {
                    ForEach(series.seasons.sorted(by: { $0.season < $1.season }), id: \.season) { s in
                        Menu {
                            Picker("Серии", selection: Binding(
                                get: { (vm.currentSeason == s.season) ? (vm.currentEpisode ?? -1) : -1 },
                                set: { ep in
                                    if ep >= 0 {
                                        vm.selectEpisode(season: s.season, episode: ep)
                                    }
                                    onInteraction?()
                                }
                            )) {
                                ForEach(s.episodes.sorted(by: { $0.episode < $1.episode }), id: \.episode) { ep in
                                    Text("Серия \(ep.episode)").tag(ep.episode)
                                }
                            }
                        } label: {
                            if vm.currentSeason == s.season {
                                Label("Сезон \(s.season)", systemImage: "checkmark")
                            } else {
                                Text("Сезон \(s.season)")
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
                            onInteraction?()
                        }
                    )) {
                        ForEach(singleSeason.episodes.sorted(by: { $0.episode < $1.episode }), id: \.episode) { ep in
                            Text("Серия \(ep.episode)").tag(ep.episode)
                        }
                    }
                }
            } label: {
                seasonEpisodeButtonContent(season: season, episode: episode, isInteractive: true)
            }
            .buttonStyle(.glassPress)
            .menuOrder(.priority)
            .accessibilityLabel("Выбор серии: \(season) сезон, \(episode) серия")
        } else {
            seasonEpisodeButtonContent(season: season, episode: episode, isInteractive: false)
                .accessibilityLabel("\(season) сезон, \(episode) серия")
        }
    }

    private func seasonEpisodeButtonContent(season: Int, episode: Int, isInteractive: Bool) -> some View {
        HStack(spacing: 4.5) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
                .glassForeground()

            Text("\(season) сезон, \(episode) серия")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .glassForeground()
                .lineLimit(1)

            if isInteractive {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .glassForeground()
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 24)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var hasEpisodeSelection: Bool {
        guard let series = vm.seriesResult else { return false }
        return !series.seasons.isEmpty
    }

    // MARK: - Отдельная кнопка «Закрыть» (нативная круглая иконка как в окне шеринга)

    private var closeButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .glassForeground()
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.glassPress)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Закрыть плеер")
    }

    // MARK: - Двойная капсула: PiP + AirPlay

    private var dualActionsGroup: some View {
        HStack(spacing: 0) {
            // PiP
            if AVPictureInPictureController.isPictureInPictureSupported() {
                Button { vm.togglePiP() } label: {
                    Image(systemName: vm.isPiPActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .glassForeground()
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.glassPress)
                .accessibilityLabel(vm.isPiPActive ? "Выйти из режима картинка в картинке" : "Картинка в картинке")
            }

            // AirPlay (системная кнопка Apple)
            AirPlayButton()
                .frame(width: 44, height: 44)
                .colorMultiply(.white.opacity(0.85))
        }
        .padding(.horizontal, 2)
        .frame(height: 44)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    // MARK: - Совместный просмотр (SharePlay-style)

    @ViewBuilder
    private var watchPartyButton: some View {
        if watchPartyRepo.isConnected, let peer = watchPartyRepo.peerUser {
            Menu {
                Section {
                    Text("Совместный просмотр")
                    if watchPartyRepo.activeSession?.guestUid != nil {
                        Label("Подключён: \(peer.displayTitle)", systemImage: "checkmark.circle.fill")
                    } else {
                        Label("Ожидание: \(peer.displayTitle)", systemImage: "clock")
                    }
                }
                Button(role: .destructive) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    watchPartyRepo.leaveSession()
                } label: {
                    Label("Завершить просмотр", systemImage: "xmark.circle")
                }
            } label: {
                HStack(spacing: 0) {
                    Image(systemName: "shareplay")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.green)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())

                    SlooshAvatarView(user: peer, size: 28, showOnline: true)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .padding(.horizontal, 2)
                .frame(height: 44)
                .contentShape(Capsule())
            }
            .buttonStyle(.glassPress)
            .glassEffect(.regular.interactive(), in: .capsule)
            .accessibilityLabel("Управление совместным просмотром: \(peer.displayTitle)")
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showFriendPicker = true
            } label: {
                Image(systemName: "shareplay")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .glassForeground()
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.glassPress)
            .glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Смотреть вместе")
            .sheet(isPresented: $showFriendPicker) {
                WatchPartyFriendPickerSheet { friend in
                    let mediaId = vm.rootMediaKey ?? vm.fallbackTitle
                    Task {
                        _ = await watchPartyRepo.createSession(
                            mediaId: mediaId,
                            mediaType: vm.isMovie ? "movie" : "tv",
                            title: vm.fallbackTitle,
                            posterUrl: vm.posterUrl,
                            season: vm.currentSeason,
                            episode: vm.currentEpisode,
                            translationId: nil,
                            translationName: vm.currentTranslationName,
                            streamSource: vm.streamSource == .source2 ? "source2" : "source1",
                            currentPosition: vm.currentTime,
                            isPlaying: vm.isPlaying,
                            invitee: friend
                        )
                    }
                }
            }
        }
    }

    // MARK: - Создать момент (вырезать клип)

    private var clipButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                vm.enterClipMode()
            }
        } label: {
            Image(systemName: "scissors")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .glassForeground()
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.glassPress)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Создать момент")
    }

    // MARK: - Блокировка интерфейса

    private var lockButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(.easeInOut(duration: 0.22)) {
                vm.isInterfaceLocked = true
            }
        } label: {
            Image(systemName: "lock.open.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .glassForeground()
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.glassPress)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel("Заблокировать экран")
    }
}

// MARK: - AirPlay — нативная кнопка Apple

struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = UIColor.systemBlue
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
