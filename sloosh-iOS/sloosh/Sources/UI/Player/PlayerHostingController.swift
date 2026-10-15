import SwiftUI
import UIKit

// MARK: - UIHostingController, который принудительно держит landscape
// и при закрытии возвращает портрет через AppDelegate.orientationLock.

final class PlayerHostingController<Content: View>: UIHostingController<Content> {

    var onDismissed: (() -> Void)?
    var isTrimmerPresented: Bool = false {
        didSet {
            guard oldValue != isTrimmerPresented else { return }
            if isTrimmerPresented {
                AppDelegate.lockToPortrait()
            } else {
                AppDelegate.lockToLandscape()
            }
            setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if isTrimmerPresented {
            return .portrait
        }
        return .landscape
    }

    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if isTrimmerPresented {
            return .portrait
        }
        return .landscapeRight
    }

    override var shouldAutorotate: Bool { true }

    override var prefersStatusBarHidden: Bool { !isTrimmerPresented }
    override var prefersHomeIndicatorAutoHidden: Bool { !isTrimmerPresented }

    override init(rootView: Content) {
        super.init(rootView: rootView)
        overrideUserInterfaceStyle = .dark
    }

    @MainActor required dynamic init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        overrideUserInterfaceStyle = .dark
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = .black
        view.tintColor = .white
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        overrideUserInterfaceStyle = .dark
        view.tintColor = .white
        if isTrimmerPresented {
            AppDelegate.lockToPortrait()
        } else {
            AppDelegate.lockToLandscape()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isBeingDismissed {
            AppDelegate.lockToPortrait()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            AppDelegate.lockToPortrait()
            onDismissed?()
        }
    }
}
