import SwiftUI
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    var items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

enum SharePresenter {
    @MainActor
    static func presentShare(url: URL, text: String) {
        presentShare(items: [url, text])
    }
    
    @MainActor
    static func presentShare(items: [Any]) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
           let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = topVC.view
                popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            topVC.present(activityVC, animated: true)
        }
    }
}

enum NavigationPopPresenter {
    @MainActor
    static func pop() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
           let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController {
            
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            
            if let navVC = (topVC as? UINavigationController) ?? findNavigationController(in: topVC) {
                navVC.popViewController(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    DeepLinkManager.shared.clear()
                }
                return
            }
        }
        
        DeepLinkManager.shared.clear()
    }
    
    private static func findNavigationController(in vc: UIViewController) -> UINavigationController? {
        if let nav = vc as? UINavigationController {
            return nav
        }
        for child in vc.children {
            if let nav = findNavigationController(in: child) {
                return nav
            }
        }
        return nil
    }
}
