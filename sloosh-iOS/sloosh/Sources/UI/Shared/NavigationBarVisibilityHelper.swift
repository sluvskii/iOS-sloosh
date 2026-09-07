import SwiftUI
import UIKit

public struct HideNavigationBarModifier: ViewModifier {
    public func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarBackButtonHidden(true)
            .navigationBarHidden(true)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .toolbar(.hidden, for: .navigationBar)
            .background(HideNavigationBarRepresentable())
    }
}

public extension View {
    func hideNavigationBarWithRestore() -> some View {
        self.modifier(HideNavigationBarModifier())
    }
}

private struct HideNavigationBarRepresentable: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> HideNavBarViewController {
        HideNavBarViewController()
    }
    
    func updateUIViewController(_ uiViewController: HideNavBarViewController, context: Context) {}
}

@MainActor
private final class HideNavBarViewController: UIViewController {
    private var previousNavBarHidden: Bool? = nil
    private weak var cachedNavController: UINavigationController?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.isHidden = true
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
    }
    
    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        if let parent = parent {
            let nav = navigationController ?? parent.navigationController
            cachedNavController = nav
            if let nav = nav {
                if previousNavBarHidden == nil {
                    previousNavBarHidden = nav.isNavigationBarHidden
                }
                if !nav.isNavigationBarHidden {
                    nav.setNavigationBarHidden(true, animated: false)
                }
            }
        } else {
            if let previous = previousNavBarHidden, let nav = cachedNavController {
                if nav.isNavigationBarHidden != previous {
                    nav.setNavigationBarHidden(previous, animated: false)
                }
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let nav = navigationController ?? cachedNavController
        if let nav = nav {
            if previousNavBarHidden == nil {
                previousNavBarHidden = nav.isNavigationBarHidden
            }
            if !nav.isNavigationBarHidden {
                nav.setNavigationBarHidden(true, animated: animated)
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let nav = navigationController ?? cachedNavController
        if let nav = nav, !nav.isNavigationBarHidden {
            nav.setNavigationBarHidden(true, animated: false)
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let hosting = parent ?? self
        let isPopping = isMovingFromParent || (parent?.isMovingFromParent ?? false) || (navigationController?.viewControllers.contains(where: { $0 === hosting }) == false)
        if isPopping {
            if let previous = previousNavBarHidden, let nav = navigationController ?? cachedNavController {
                if nav.isNavigationBarHidden != previous {
                    nav.setNavigationBarHidden(previous, animated: animated)
                }
            }
        }
    }
}
