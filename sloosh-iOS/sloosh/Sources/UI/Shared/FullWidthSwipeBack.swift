import SwiftUI
import UIKit

public struct FullWidthSwipeBackModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    
    public func body(content: Content) -> some View {
        content
            .background(FullWidthSwipeBackRepresentable(onSwipe: {
                dismiss()
            }))
    }
}

public extension View {
    func fullWidthSwipeBack() -> some View {
        self.modifier(FullWidthSwipeBackModifier())
    }
}

private struct FullWidthSwipeBackRepresentable: UIViewRepresentable {
    let onSwipe: () -> Void
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onSwipe: onSwipe)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onSwipe: () -> Void
        
        init(onSwipe: @escaping () -> Void) {
            self.onSwipe = onSwipe
        }
        
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            
            if gesture.state == .ended {
                if translation.x > 80 && velocity.x > 100 {
                    onSwipe()
                }
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}
