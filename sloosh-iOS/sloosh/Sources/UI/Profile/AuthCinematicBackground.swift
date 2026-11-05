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
    var includesDither = true
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            let screen = Path(CGRect(origin: .zero, size: size))
            context.fill(screen, with: .color(.black))
            let phase = time * .pi / 18

            func glow(_ color: Color, opacity: Double, x: Double, y: Double, radius: Double) {
                context.fill(screen, with: .radialGradient(
                    Gradient(stops: AuthBackgroundSmoothing.glowStops.map {
                        .init(color: color.opacity(opacity * $0.opacity), location: $0.location)
                    }),
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
                    Gradient(stops: AuthBackgroundSmoothing.beamStops.map {
                        .init(color: accent.opacity((index == 0 ? 0.045 : 0.025) * $0.opacity), location: $0.location)
                    }),
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

            // Fixed, zero-motion grain at one physical pixel. It breaks up 8-bit
            // contours without changing the approved palette or blurring text.
            if includesDither {
                var dither = context
                dither.blendMode = .softLight
                dither.opacity = AuthBackgroundSmoothing.ditherOpacity
                dither.fill(screen, with: .tiledImage(
                    AuthBackgroundSmoothing.noiseImage.interpolation(.none),
                    scale: 1 / max(displayScale, 1)
                ))
            }
        }
    }
}

/// Smooth derivatives at light-field edges avoid visible contour/ribbon ridges.
/// The texture is generated once and never seeded from animation time.
enum AuthBackgroundSmoothing {
    struct Stop {
        let location: CGFloat
        let opacity: Double
    }
    static let ditherOpacity: Double = 0.055
    static let textureSize = 64
    static let noiseBytes: [UInt8] = {
        var seed: UInt32 = 0x51_00_5A
        return (0..<(textureSize * textureSize)).map { _ in
            seed = seed &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: seed >> 24)
        }
    }()
    static let noiseImage: Image = {
        let data = Data(noiseBytes) as CFData
        let provider = CGDataProvider(data: data)!
        let image = CGImage(width: textureSize, height: textureSize,
                            bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: textureSize,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return Image(decorative: image, scale: 1)
    }()
    static let glowStops: [Stop] = (0...32).map { index in
        let t = Double(index) / 32
        let gaussian = (exp(-4.5 * t * t) - exp(-4.5)) / (1 - exp(-4.5))
        let edge = min(1, max(0, (t - 0.8) / 0.2))
        let feather = 1 - edge * edge * (3 - 2 * edge)
        return Stop(location: t, opacity: max(0, gaussian * feather))
    }
    static let beamStops: [Stop] = (0...32).map { index in
        let t = Double(index) / 32
        return Stop(location: t, opacity: pow(sin(.pi * t), 2))
    }
}
