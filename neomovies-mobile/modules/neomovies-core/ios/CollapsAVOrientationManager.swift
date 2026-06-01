import Foundation
import UIKit

/// Manages screen orientation for AVPlayer
final class CollapsAVOrientationManager {
    
    // MARK: - Public API
    
    /// Forces the device to landscape orientation
    @MainActor
    func forceLandscapeOrientation() {
        if #available(iOS 16.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: [.landscapeRight, .landscapeLeft])
            windowScene.requestGeometryUpdate(prefs) { _ in }
            UIViewController.attemptRotationToDeviceOrientation()
            return
        }
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
    
    /// Forces the device to portrait orientation
    @MainActor
    func forcePortraitOrientation() {
        if #available(iOS 16.0, *) {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
            let prefs = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: [.portrait])
            windowScene.requestGeometryUpdate(prefs) { _ in }
            UIViewController.attemptRotationToDeviceOrientation()
            return
        }
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        UIViewController.attemptRotationToDeviceOrientation()
    }
}
