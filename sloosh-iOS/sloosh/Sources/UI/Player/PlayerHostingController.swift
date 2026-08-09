import SwiftUI
import UIKit

// MARK: - UIHostingController, который принудительно держит landscape
// и при закрытии плавно возвращает портрет через AppDelegate.orientationLock.

final class PlayerHostingController<Content: View>: UIHostingController<Content> {

    var onDismissed: (() -> Void)?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .landscapeRight
    }

    override var shouldAutorotate: Bool { true }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        AppDelegate.lockToLandscape()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        AppDelegate.lockToPortrait()
        onDismissed?()
    }
}
