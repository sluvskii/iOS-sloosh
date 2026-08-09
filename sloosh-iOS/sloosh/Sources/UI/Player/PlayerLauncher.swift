import SwiftUI
import AVFoundation

// MARK: - PlayerLaunchConfig
// Данные, необходимые для запуска плеера

struct PlayerLaunchConfig: Equatable {
    let iframeUrl: String?
    let directStreamUrl: String?
    let fallbackTitle: String
    let kpId: Int?
    let season: Int?
    let episode: Int?
    let selectedVoiceover: String?
    let voices: [String]
    let subtitles: [PlaybackSubtitle]
    let initialQuality: VideoQualityPreference?
    let seriesResult: AllohaApiResult?

    static func == (lhs: PlayerLaunchConfig, rhs: PlayerLaunchConfig) -> Bool {
        lhs.iframeUrl == rhs.iframeUrl &&
        lhs.directStreamUrl == rhs.directStreamUrl &&
        lhs.fallbackTitle == rhs.fallbackTitle &&
        lhs.kpId == rhs.kpId &&
        lhs.season == rhs.season &&
        lhs.episode == rhs.episode &&
        lhs.selectedVoiceover == rhs.selectedVoiceover
    }
}

// MARK: - PlayerLauncherRepresentable
//
// UIViewControllerRepresentable, который:
// 1. Встраивает ПУСТОЙ прозрачный anchor UIViewController в иерархию SwiftUI
// 2. Когда config != nil, ПРЕЗЕНТУЕТ PlayerHostingController как настоящий UIKit full-screen модал
// 3. Когда config == nil, закрывает ранее открытый плеер
//
// Ключевое отличие от старого подхода:
// PlayerHostingController теперь — настоящий UIKit модал (не child VC),
// поэтому его viewDidDisappear срабатывает ПОСЛЕ завершения анимации dismiss,
// что делает безопасным вызов lockToPortrait() именно там.

struct PlayerLauncherRepresentable: UIViewControllerRepresentable {
    let config: PlayerLaunchConfig?
    let onDismiss: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let anchor = UIViewController()
        anchor.view.backgroundColor = .clear
        anchor.view.isUserInteractionEnabled = false
        return anchor
    }

    func updateUIViewController(_ anchor: UIViewController, context: Context) {
        let coordinator = context.coordinator

        if let config, !coordinator.isPresented {
            // Запускаем плеер
            coordinator.present(config: config, from: anchor, onDismiss: onDismiss)
        } else if config == nil, coordinator.isPresented {
            // Закрываем плеер программно (если нужно)
            coordinator.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator
    class Coordinator {
        var isPresented = false
        private weak var playerVC: UIViewController?

        func present(config: PlayerLaunchConfig, from anchor: UIViewController, onDismiss: @escaping () -> Void) {
            guard !isPresented else { return }

            // Создаём ViewModel и инициализируем её
            let vm = PlayerViewModel()
            vm.player = AVPlayer()
            vm.fallbackTitle = config.fallbackTitle
            vm.targetQualityPreference = config.initialQuality
            vm.seriesResult = config.seriesResult

            if let iframeUrl = config.iframeUrl, !iframeUrl.isEmpty {
                vm.load(
                    iframeUrl: iframeUrl,
                    kpId: config.kpId,
                    season: config.season,
                    episode: config.episode,
                    selectedVoiceover: config.selectedVoiceover,
                    voices: config.voices,
                    subtitles: config.subtitles
                )
            } else if let directUrl = config.directStreamUrl {
                vm.load(
                    iframeUrl: nil,
                    kpId: config.kpId,
                    season: config.season,
                    episode: config.episode,
                    selectedVoiceover: config.selectedVoiceover,
                    directStreamUrl: directUrl,
                    voices: config.voices,
                    subtitles: config.subtitles
                )
            } else {
                vm.error = "Нет URL для воспроизведения"
                vm.isLoading = false
            }

            let containerView = PlayerContainerView(vm: vm, onDismiss: { [weak self] in
                self?.dismiss()
            })

            let hc = PlayerHostingController(rootView: containerView)
            hc.modalPresentationStyle = .fullScreen
            hc.onDismissed = { [weak self] in
                // viewDidDisappear PlayerHostingController
                // Срабатывает ПОСЛЕ завершения анимации dismiss (т.к. это настоящий UIKit модал)
                vm.cleanup()
                self?.isPresented = false
                self?.playerVC = nil
                onDismiss()
            }

            isPresented = true
            playerVC = hc

            // Находим topmost VC для презентации
            let presenter = topVC(from: anchor)
            presenter.present(hc, animated: true)
        }

        func dismiss() {
            playerVC?.dismiss(animated: true)
            // lockToPortrait вызывается в viewDidDisappear PlayerHostingController
        }

        private func topVC(from base: UIViewController) -> UIViewController {
            if let presented = base.presentedViewController {
                return topVC(from: presented)
            }
            return base
        }
    }
}

// MARK: - playerLauncher View Modifier

struct PlayerLauncherModifier: ViewModifier {
    let config: PlayerLaunchConfig?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.background(
            PlayerLauncherRepresentable(config: config, onDismiss: onDismiss)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}

extension View {
    /// Запускает плеер как настоящий UIKit full-screen модал.
    /// Используйте вместо .fullScreenCover для PlayerView.
    /// Плеер открывается когда config != nil, закрывается когда config == nil.
    func playerLauncher(config: PlayerLaunchConfig?, onDismiss: @escaping () -> Void) -> some View {
        modifier(PlayerLauncherModifier(config: config, onDismiss: onDismiss))
    }
}
