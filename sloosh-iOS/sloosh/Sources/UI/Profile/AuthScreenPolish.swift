import SwiftUI

/// Entrance affects only the surrounding chrome, never the approved word reveal.
/// The primary action starts visible; accessibility modes skip the staging entirely.
enum AuthEntranceStage: CaseIterable {
    case header, action, caption

    var delay: Double {
        switch self {
        case .header: 0
        case .action: 0.10
        case .caption: 0.18
        }
    }
    var initialOpacity: Double { self == .action ? 0.72 : 0 }
    var rise: CGFloat { self == .action ? 8 : 4 }

    func opacity(appeared: Bool, reducedEffects: Bool) -> Double {
        appeared || reducedEffects ? 1 : initialOpacity
    }
    func offset(appeared: Bool, reducedEffects: Bool) -> CGFloat {
        appeared || reducedEffects ? 0 : rise
    }
}

struct AuthScreenEntrance: ViewModifier {
    let stage: AuthEntranceStage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var appeared = false

    private var reducedEffects: Bool { reduceMotion || voiceOver }

    func body(content: Content) -> some View {
        content
            .opacity(stage.opacity(appeared: appeared, reducedEffects: reducedEffects))
            .offset(y: stage.offset(appeared: appeared, reducedEffects: reducedEffects))
            .onAppear {
                guard !appeared else { return }
                if reducedEffects {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) { appeared = true }
                } else {
                    withAnimation(.easeOut(duration: 0.65).delay(stage.delay)) { appeared = true }
                }
            }
    }
}

struct AuthPressAppearance {
    let scale: CGFloat
    let offset: CGFloat
    let opacity: Double

    init(isPressed: Bool, reduceMotion: Bool) {
        scale = isPressed && !reduceMotion ? 0.985 : 1
        offset = isPressed && !reduceMotion ? 1 : 0
        opacity = isPressed ? 0.96 : 1
    }
}

struct AuthPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let appearance = AuthPressAppearance(isPressed: configuration.isPressed, reduceMotion: reduceMotion)
        configuration.label
            .scaleEffect(appearance.scale)
            .offset(y: appearance.offset)
            .opacity(appearance.opacity)
            .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
