import SwiftUI

/// Isolated from the form: only the background redraws at a capped frame rate.
/// Native gradient falloffs avoid huge blurred offscreen textures on tall phones.
struct AuthCinematicBackground: View {
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var clock = AuthBackgroundClock()
    @State private var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    private var isPaused: Bool {
        AuthBackgroundMotion.isPaused(reduceMotion: reduceMotion, isActive: scenePhase == .active, lowPower: lowPowerMode)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: isPaused)) { timeline in
            AuthCinematicBackdrop(time: clock.time(at: timeline.date), accent: accent)
        }
        .onAppear { clock.setRunning(!isPaused, at: Date()) }
        .onChange(of: isPaused) { _, paused in clock.setRunning(!paused, at: Date()) }
        .onDisappear { clock.setRunning(false, at: Date()) }
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
            guard size.width > 0, size.height > 0 else { return }
            let screen = Path(CGRect(origin: .zero, size: size))
            context.fill(screen, with: .color(.black))
            // Five native gradients, no large blurred textures, particles or sensors.
            // Wider fields and narrower tilted washes drift at independent speeds.
            for light in AuthBackgroundMotion.lights(at: time) {
                var wash = context
                wash.translateBy(x: size.width * light.x, y: size.height * light.y)
                wash.rotate(by: .degrees(light.angle))
                let radiusX = light.isRibbon ? size.width * light.radiusX : size.height * light.radiusX
                wash.scaleBy(x: radiusX, y: size.height * light.radiusY)
                let color: Color
                switch light.tone {
                case .brand: color = accent
                case .teal: color = Color(red: 0.03, green: 0.5, blue: 0.46)
                case .violet: color = Color(red: 0.22, green: 0.17, blue: 0.49)
                }
                wash.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)), with: .radialGradient(
                    Gradient(stops: AuthBackgroundSmoothing.glowStops.map {
                        .init(color: color.opacity(light.opacity * $0.opacity), location: $0.location)
                    }), center: .zero, startRadius: 0, endRadius: 1
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

/// Pure motion sampling keeps all paths continuous and deterministic at any frame.
/// Breathing is deliberately shallow: movement is visible, luminance never flashes.
enum AuthBackgroundMotion {
    enum Tone { case brand, teal, violet }
    struct Light {
        let tone: Tone
        let x: Double
        let y: Double
        let radiusX: Double
        let radiusY: Double
        let angle: Double
        let opacity: Double
        var isRibbon = false
    }

    static func isPaused(reduceMotion: Bool, isActive: Bool, lowPower: Bool) -> Bool {
        reduceMotion || !isActive || lowPower
    }

    static func lights(at time: TimeInterval) -> [Light] {
        let phase = time * .pi / 11
        let brandRadius = 0.60 + sin(phase * 0.54) * 0.035
        let tealRadius = 0.56 + cos(phase * 0.61) * 0.025
        let violetRadius = 0.50 + sin(phase * 0.74) * 0.035
        return [
            Light(tone: .brand, x: 0.20 + sin(phase * 0.93) * 0.25,
                  y: 0.26 + cos(phase * 0.72) * 0.10,
                  radiusX: brandRadius, radiusY: brandRadius, angle: 0,
                  opacity: 0.26 + sin(phase * 0.96) * 0.025),
            Light(tone: .teal, x: 0.82 + cos(phase * 0.71 + 0.8) * 0.24,
                  y: 0.53 + sin(phase * 0.89 + 0.5) * 0.20,
                  radiusX: tealRadius, radiusY: tealRadius, angle: 0,
                  opacity: 0.19 + sin(phase * 0.80 + 0.6) * 0.025),
            Light(tone: .violet, x: 0.32 + sin(phase * 0.63 + 1.1) * 0.28,
                  y: 0.90 + cos(phase * 0.57) * 0.09,
                  radiusX: violetRadius, radiusY: violetRadius, angle: 0,
                  opacity: 0.20 + sin(phase * 0.68 + 1.6) * 0.020),
            Light(tone: .brand, x: 0.35 + sin(phase * 0.77 + 0.2) * 0.32,
                  y: 0.40 + cos(phase * 0.81) * 0.10,
                  radiusX: 0.21, radiusY: 0.73,
                  angle: -27 + sin(phase * 0.70) * 14,
                  opacity: 0.075 + sin(phase * 0.90 + 0.2) * 0.018, isRibbon: true),
            Light(tone: .teal, x: 0.82 + sin(phase * 0.88 + 1.4) * 0.23,
                  y: 0.62 + sin(phase * 0.67) * 0.13,
                  radiusX: 0.16, radiusY: 0.63,
                  angle: 32 + cos(phase * 0.69) * 11,
                  opacity: 0.055 + sin(phase * 0.76 + 1.7) * 0.013, isRibbon: true)
        ]
    }
}

/// Accumulate only foreground animation time. Pausing never resets the picture,
/// and resuming cannot fast-forward through time spent in background / Low Power.
struct AuthBackgroundClock {
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?

    func time(at date: Date) -> TimeInterval {
        accumulated + (runningSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    mutating func setRunning(_ running: Bool, at date: Date) {
        if running {
            if runningSince == nil { runningSince = date }
        } else if runningSince != nil {
            accumulated = time(at: date)
            runningSince = nil
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
}
