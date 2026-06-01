import Foundation
import UIKit
import AVFoundation

/// Manages player presentation and UI
final class CollapsAVPlayerPresenter {
    
    // MARK: - Dependencies
    private weak var player: AVPlayer?
    private weak var orientationManager: CollapsAVOrientationManager?
    private weak var uiManager: CollapsAVUIManager?
    
    // MARK: - State
    private var playerVC: CollapsNativePlayerViewController?
    
    // MARK: - Callbacks
    var onCloseTapped: (() -> Void)?
    var onPlayPauseTapped: (() -> Void)?
    var onSeekTapped: ((Double) -> Void)?
    var onQualityTapped: ((UIView) -> Void)?
    var onAudioTapped: ((UIView) -> Void)?
    
    // MARK: - Initialization
    init(
        player: AVPlayer,
        orientationManager: CollapsAVOrientationManager,
        uiManager: CollapsAVUIManager
    ) {
        self.player = player
        self.orientationManager = orientationManager
        self.uiManager = uiManager
    }
    
    // MARK: - Public API
    
    @MainActor
    func presentNativePlayer(
        from controller: UIViewController,
        onQualityTapped: @escaping (UIView) -> Void,
        onAudioTapped: @escaping (UIView) -> Void
    ) {
        if playerVC == nil {
            let vc = CollapsNativePlayerViewController()
            vc.player = player
            vc.showsPlaybackControls = false
            vc.allowsPictureInPicturePlayback = true
            vc.canStartPictureInPictureAutomaticallyFromInline = true
            vc.entersFullScreenWhenPlaybackBegins = true
            vc.exitsFullScreenWhenPlaybackEnds = false
            vc.onCloseTapped = { [weak self] in
                Task { @MainActor in
                    self?.dismissNativePlayer()
                }
            }
            vc.onPlayPauseTapped = { [weak self] in
                self?.onPlayPauseTapped?()
            }
            vc.onQualityTapped = onQualityTapped
            vc.onAudioTapped = onAudioTapped
            playerVC = vc
            uiManager?.updatePlayerVC(vc)
        }
        
        guard let presenter = topViewController(), let playerVC else { return }
        if presenter.presentedViewController === playerVC { return }
        presenter.present(playerVC, animated: true)
    }
    
    @MainActor
    func dismissNativePlayer() {
        playerVC?.dismiss(animated: true)
        onCloseTapped?()
    }
    
    private func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?.rootViewController

        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }
}
