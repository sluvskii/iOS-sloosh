import SwiftUI

struct Toast: Equatable {
    var id = UUID()
    var title: String
    var systemImage: String
    var tintColor: Color = .primary
}

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: Toast?
    private var dismissTask: Task<Void, Never>?
    
    private init() {}
    
    func show(title: String, systemImage: String, tintColor: Color = .primary, duration: TimeInterval = 3.0) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            currentToast = Toast(title: title, systemImage: systemImage, tintColor: tintColor)
        }
        
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }
    
    func dismiss() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            currentToast = nil
        }
    }
}

struct ToastOverlayModifier: ViewModifier {
    @StateObject private var manager = ToastManager.shared
    @State private var dragOffset: CGFloat = 0
    
    func body(content: Content) -> View {
        ZStack(alignment: .top) {
            content
            
            if let toast = manager.currentToast {
                ToastView(toast: toast)
                    .padding(.top, 50) // Avoid dynamic island / notch
                    .offset(y: dragOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if value.translation.height < 0 {
                                    dragOffset = value.translation.height
                                }
                            }
                            .onEnded { value in
                                if value.translation.height < -20 {
                                    manager.dismiss()
                                }
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    dragOffset = 0
                                }
                            }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.8)))
                    .zIndex(100)
            }
        }
    }
}

struct ToastView: View {
    let toast: Toast
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(toast.tintColor)
                .contentTransition(.symbolEffect(.replace))
            
            Text(toast.title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(2)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(in: Capsule())
        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 5)
        .sensoryFeedback(.success, trigger: toast.id)
    }
}

extension View {
    func toastOverlay() -> some View {
        self.modifier(ToastOverlayModifier())
    }
}
