import SwiftUI

/// Isolated from the form: only the background redraws at a capped frame rate.
/// Native gradient falloffs avoid huge blurred offscreen textures on tall phones.
struct AuthCinematicBackground: View {
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt = Date()
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var isPaused: Bool {
        reduceMotion || scenePhase != .active || lowPowerMode
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: isPaused)) { timeline in
            AuthCinematicBackdrop(time: isPaused ? 0 : timeline.date.timeIntervalSince(startedAt), accent: accent)
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
            lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct AuthCinematicBackdrop: View {
    let time: TimeInterval
    let accent: Color

    var body: some View {
        Canvas { context, size in
            let screen = Path(CGRect(origin: .zero, size: size))
            context.fill(screen, with: .color(.black))
            let phase = time * .pi / 18

            func glow(_ color: Color, opacity: Double, x: Double, y: Double, radius: Double) {
                context.fill(screen, with: .radialGradient(
                    Gradient(stops: [
                        .init(color: color.opacity(opacity), location: 0),
                        .init(color: color.opacity(opacity * 0.35), location: 0.48),
                        .init(color: .clear, location: 1)
                    ]),
                    center: CGPoint(x: size.width * x, y: size.height * y),
                    startRadius: 0, endRadius: size.height * radius
                ))
            }
            // Independent slow drift rather than two circles pulsing in lockstep.
            glow(accent, opacity: 0.28, x: 0.18 + sin(phase) * 0.15,
                 y: 0.27 + cos(phase * 0.8) * 0.07, radius: 0.64)
            glow(Color(red: 0.03, green: 0.5, blue: 0.46), opacity: 0.19,
                 x: 0.88 + cos(phase * 0.7) * 0.12, y: 0.51 + sin(phase * 0.6) * 0.14, radius: 0.57)
            glow(Color(red: 0.22, green: 0.17, blue: 0.49), opacity: 0.22,
                 x: 0.3 + sin(phase * 0.5) * 0.2, y: 0.96, radius: 0.5)

            // Soft projection-light shafts, not visible lines or separate panels.
            for index in 0..<2 {
                var beam = context
                beam.translateBy(x: size.width * (index == 0 ? 0.22 : 0.85), y: size.height * 0.35)
                beam.rotate(by: .degrees(-25 + Double(index) * 13 + sin(phase * 0.65) * 5))
                let width = size.width * (index == 0 ? 0.44 : 0.23)
                let rect = CGRect(x: -width / 2, y: -size.height, width: width, height: size.height * 2)
                beam.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [.clear, accent.opacity(index == 0 ? 0.045 : 0.025), .clear]),
                    startPoint: CGPoint(x: -width / 2, y: 0), endPoint: CGPoint(x: width / 2, y: 0)
                ))
            }
            // Keep the logo and sign-in copy readable against every animation phase.
            context.fill(screen, with: .linearGradient(
                Gradient(stops: [
                    .init(color: .black.opacity(0.3), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 0.55),
                    .init(color: .black.opacity(0.65), location: 1)
                ]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            ))
        }
    }
}
