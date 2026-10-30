import SwiftUI
import CoreGraphics

@main
struct GlassForegroundTests {
    @MainActor
    static func main() {
        var cases = 0
        for dark in [false, true] {
            for contrast in [false, true] {
                for reduce in [false, true] {
                    for blends in [false, true] {
                        for enabled in [false, true] {
                            for inverted in [false, true] {
                                let value = GlassForegroundAppearance(
                                    isDark: dark, increasedContrast: contrast,
                                    reduceTransparency: reduce, blendsContent: blends,
                                    controlEnabled: enabled, isInverted: inverted
                                )
                                let normal = contrast || reduce || !blends || !enabled
                                let lightInk = inverted ? !dark : dark
                                precondition(value.opacity == (normal ? 1 : 0.72))
                                precondition(value.blendMode == (normal ? .normal : (lightInk ? .plusLighter : .plusDarker)))
                                cases += 1
                            }
                        }
                    }
                }
            }
        }
        let neutralTints: [Color?] = [nil, .primary, .secondary, .white]
        for tint in neutralTints {
            precondition(GlassForegroundAppearance.shouldBlend(tint: tint))
        }
        let semanticTints: [Color] = [.red, .green, .orange, .blue]
        for tint in semanticTints {
            precondition(!GlassForegroundAppearance.shouldBlend(tint: tint), "Semantic tint must remain intact")
        }

        // Render the actual foreground modifier, not just its numeric policy.
        // A symbol-shaped foreground should pick up background color, while
        // pixels outside it must stay untouched. No Simulator/API key needed.
        let dark = pixels(dark: true, blend: true)
        let opaque = pixels(dark: true, blend: false)
        let light = pixels(dark: false, blend: true)
        let lightOpaque = pixels(dark: false, blend: false)
        let center = (16 * 32 + 16) * 4
        let edge = (2 * 32 + 2) * 4
        for c in 0..<3 {
            precondition(abs(Int(dark[edge+c]) - Int(opaque[edge+c])) <= 2, "Do not fade or blend the control background")
            precondition(abs(Int(light[edge+c]) - Int(lightOpaque[edge+c])) <= 2)
        }
        precondition((0..<3).contains { Int(dark[center+$0]) < Int(opaque[center+$0]) - 3 }, "Dark foreground must no longer be opaque white")
        precondition((0..<3).contains { Int(light[center+$0]) > Int(lightOpaque[center+$0]) + 3 }, "Light foreground must no longer be opaque black")
        precondition(dark[center] != dark[center+2], "Foreground should retain visible backdrop color")
        print("PASS: \(cases) glass foreground policy cases, semantic tints, 4 rendered foreground/background samples")
    }

    @MainActor
    private static func pixels(dark: Bool, blend: Bool) -> [UInt8] {
        let content = ZStack {
            Color(red: dark ? 0.1 : 0.9, green: dark ? 0.15 : 0.85, blue: dark ? 0.2 : 0.8)
            Image(systemName: "square.fill")
                .resizable()
                .frame(width: 16, height: 16)
                .foregroundStyle(dark ? Color.white : Color.black)
                .glassForeground(isEnabled: blend)
        }
        .frame(width: 32, height: 32)
        .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.cgImage else { fatalError("Foreground sample did not render") }
        var data = [UInt8](repeating: 0, count: 32 * 32 * 4)
        data.withUnsafeMutableBytes { bytes in
            let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(data: bytes.baseAddress, width: 32, height: 32,
                                          bitsPerComponent: 8, bytesPerRow: 32 * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else {
                fatalError("Could not create foreground pixel context")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return data
    }
}
