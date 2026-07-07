import SwiftUI

struct Toast: Equatable {
    let title: String
    let subtitle: String?
    let icon: String
    
    init(title: String, subtitle: String? = nil, icon: String = "checkmark.circle.fill") {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
    }
}

class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: Toast?
    
    private var dismissTask: Task<Void, Never>?
    
    private init() {}
    
    @MainActor
    func show(title: String, subtitle: String? = nil, icon: String = "checkmark.circle.fill", duration: TimeInterval = 3.0) {
        dismissTask?.cancel()
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            self.currentToast = Toast(title: title, subtitle: subtitle, icon: icon)
        }
        
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                if self.currentToast?.title == title {
                    self.currentToast = nil
                }
            }
        }
    }
}

struct ToastModifier: ViewModifier {
    @ObservedObject private var manager = ToastManager.shared
    
    func body(content: Content) -> some View {
        ZStack(alignment: .bottom) {
            content
            
            if let toast = manager.currentToast {
                ToastView(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, 60) // Above tab bar
                    .zIndex(999)
            }
        }
    }
}

struct ToastView: View {
    let toast: Toast
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.slooshAccent)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                
                if let subtitle = toast.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        }
        .padding(.horizontal, 24)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                ToastManager.shared.currentToast = nil
            }
        }
    }
}

extension View {
    func withToasts() -> some View {
        self.modifier(ToastModifier())
    }
}
