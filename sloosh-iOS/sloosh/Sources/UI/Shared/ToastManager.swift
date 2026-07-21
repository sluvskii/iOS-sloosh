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
        ZStack(alignment: .top) {
            content
            
            if let toast = manager.currentToast {
                ToastView(toast: toast)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                    .padding(.top, 60) // Below dynamic island
                    .zIndex(999)
            }
        }
        .sensoryFeedback(.success, trigger: manager.currentToast?.title)
    }
}

struct ToastView: View {
    let toast: Toast
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.slooshAccent)
                .contentTransition(.symbolEffect(.replace))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                
                if let subtitle = toast.subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassEffect(in: Capsule())
        .padding(.horizontal, 24)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    } else {
                        // slight resistance when dragging down
                        dragOffset = value.translation.height * 0.2
                    }
                }
                .onEnded { value in
                    if value.translation.height < -30 || value.predictedEndTranslation.height < -50 {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            ToastManager.shared.currentToast = nil
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            dragOffset = 0
                        }
                    }
                }
        )
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
