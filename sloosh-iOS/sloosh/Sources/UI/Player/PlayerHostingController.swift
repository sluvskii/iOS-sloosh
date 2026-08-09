import SwiftUI
import UIKit

// MARK: - PlayerHostingController
// Настоящий UIKit full-screen модальный контроллер для плеера.
// Управляет ориентацией экрана: landscape пока активен, portrait после dismiss.
//
// ВАЖНО: этот контроллер должен быть представлен через anchor.present(...),
// а не добавляться как дочерний VC (иначе lifecycle-методы и ориентация не работают корректно).

final class PlayerHostingController<Content: View>: UIHostingController<Content> {

    /// Коллбек, вызывается после полного завершения анимации dismiss (viewDidDisappear)
    var onDismissed: (() -> Void)?

    // Всегда поддерживаем landscape, пока плеер открыт
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
        modalPresentationStyle = .fullScreen
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Блокируем ориентацию в landscape
        AppDelegate.lockToLandscape()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Поскольку это настоящий UIKit-модал (не дочерний VC),
        // viewDidDisappear срабатывает ПОСЛЕ завершения анимации dismiss.
        // Смена ориентации здесь безопасна — нет race condition.
        AppDelegate.lockToPortrait()
        onDismissed?()
    }
}
