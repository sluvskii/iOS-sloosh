import SwiftUI

public enum RadialDownloadState: Equatable {
    case idle
    case downloading(progress: Double)
    case paused(progress: Double)
    case downloaded
}

public struct RadialDownloadIndicator: View {
    let state: RadialDownloadState
    let onAction: () -> Void
    
    public init(state: RadialDownloadState, onAction: @escaping () -> Void) {
        self.state = state
        self.onAction = onAction
    }
    
    public var body: some View {
        Button(action: onAction) {
            ZStack {
                // Фоновое кольцо (очень легкое)
                Circle()
                    .stroke(Color.primary.opacity(0.15), lineWidth: 2)
                    .frame(width: 28, height: 28)
                
                // Прогресс
                if case .downloading(let progress) = state {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.slooshAccent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: progress)
                } else if case .paused(let progress) = state {
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.gray, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 28, height: 28)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: progress)
                } else if case .downloaded = state {
                    // Круг заливается при скачивании
                    Circle()
                        .fill(Color.slooshAccent)
                        .frame(width: 28, height: 28)
                        .transition(.scale.combined(with: .opacity))
                }
                
                // Центральная иконка с SF Symbols animations (iOS 17+)
                if #available(iOS 17.0, *) {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(iconColor)
                        .contentTransition(.symbolEffect(.replace))
                } else {
                    Image(systemName: iconName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(iconColor)
                        .transition(.scale.combined(with: .opacity))
                        .id(iconName)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: state)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var iconName: String {
        switch state {
        case .idle:
            return "arrow.down"
        case .downloading:
            return "stop.fill"
        case .paused:
            return "play.fill"
        case .downloaded:
            return "checkmark"
        }
    }
    
    private var iconColor: Color {
        switch state {
        case .idle:
            return .primary
        case .downloading:
            return .slooshAccent
        case .paused:
            return .primary
        case .downloaded:
            return .white
        }
    }
}
