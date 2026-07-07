import SwiftUI
import UIKit

// MARK: - UIHostingController, который принудительно держит landscape
// и при закрытии возвращает портрет через AppDelegate.orientationLock.

final class PlayerHostingController<Content: View>: UIHostingController<Content> {

    var onDismissed: (() -> Void)?

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var shouldAutorotate: Bool { true }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        AppDelegate.orientationLock = .landscape
        
        if #available(iOS 16.0, *) {
            if let scene = view.window?.windowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
                    print("[PlayerHostingController] rotation error: \(error)")
                }
                setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard isBeingDismissed || isMovingFromParent else { return }
        
        AppDelegate.orientationLock = .portrait
        
        if #available(iOS 16.0, *) {
            if let scene = view.window?.windowScene {
                scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
                scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDismissed?()
    }
}
