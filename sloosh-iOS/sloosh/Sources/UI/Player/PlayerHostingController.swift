import SwiftUI
import UIKit

// MARK: - UIHostingController, который принудительно держит landscape
// При закрытии ТОЛЬКО вызывает onDismissed — lockToPortrait делается
// в completion-блоке UIKit dismiss, строго после завершения анимации.

final class PlayerHostingController<Content: View>: UIHostingController<Content> {

    var onDismissed: (() -> Void)?

    // Пока контроллер жив — всегда поддерживаем landscape.
    // Не зависим от AppDelegate.orientationLock, иначе смена ориентации
    // до завершения dismiss-анимации вызывает цикл open/close.
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
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
        // НЕ вызываем lockToPortrait() здесь — ориентация меняется только
        // в completion-блоке dismiss (в PlayerPresenter.Coordinator.dismissPlayer),
        // чтобы смена происходила строго ПОСЛЕ завершения анимации.
        onDismissed?()
    }
}
