import Foundation
import SwiftUI

@main
struct AuthPresentationTests {
    @MainActor
    static func main() {
        var count = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message)
            count += 1
        }
        let phrase = "  Один клик —\nи ты уже в кино  "
        let plan = AuthWordRevealPlan(phrase)
        check(plan.parts.map(\.text).joined() == phrase, "Preserve spaces, punctuation and manual line breaks")
        check(plan.wordCount == 7, "Standalone dash shares the preceding beat")
        check(plan.parts.first(where: { $0.text == "—" })?.wordIndex == 1, "Punctuation belongs with preceding word")
        check(AuthWordRevealPlan("").duration == 0, "Empty phrase is safe")
        check(AuthWordRevealPlan(" \n ").wordCount == 0, "Whitespace is not animated as a word")
        check(AuthWordRevealPlan("sloosh-ай сердцем").wordCount == 2, "Hyphenated brand is one word")
        for i in 0..<plan.wordCount {
            let start = Double(i) * AuthWordRevealPlan.stagger
            check(AuthWordRevealPlan.visibility(of: i, at: start) == 0, "Each word starts on its own beat")
            check(AuthWordRevealPlan.visibility(of: i, at: start + AuthWordRevealPlan.wordDuration + 0.001) == 1, "Every word reaches full focus")
            check(AuthWordRevealPlan.visibility(of: i, at: plan.duration + 0.001) == 1, "Hold begins only after last word is readable")
            let samples = (0...100).map { AuthWordRevealPlan.visibility(of: i, at: Double($0) * plan.duration / 100) }
            check(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 }, "No flashing backwards during reveal")
        }
        check(AuthWordRevealPlan.visibility(of: 1, at: 0.17) == 0, "Second word stays hidden while first word appears")
        check(AuthWordRevealPlan.visibility(of: 0, at: 0.17) > 0, "First word is already appearing")

        func pixels<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> [UInt8] {
            let renderer = ImageRenderer(content: view.frame(width: width, height: height).background(.black))
            renderer.scale = 1
            guard let image = renderer.cgImage else { fatalError("Auth view must render") }
            var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
            data.withUnsafeMutableBytes { bytes in
                let cg = CGContext(data: bytes.baseAddress, width: image.width, height: image.height,
                                   bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
                cg.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            return data
        }
        func litCount(_ pixels: [UInt8]) -> Int {
            stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 30 || pixels[$0 + 1] > 30 || pixels[$0 + 2] > 30 }.count
        }
        let title = "Кино дома"
        func renderedTitle(_ elapsed: Double, width: CGFloat = 320) -> [UInt8] {
            pixels(AuthAnimatedPhrase(phrase: title, elapsed: elapsed, accent: .green)
                .font(.system(size: 25, weight: .bold)).multilineTextAlignment(.center), width: width, height: 120)
        }
        let hidden = renderedTitle(0)
        let partial = renderedTitle(0.3)
        let full = renderedTitle(10)
        check(litCount(hidden) == 0, "Actual text renderer must hide all words initially")
        check(litCount(partial) > 0, "Actual intermediate frame contains visible lettering")
        check(litCount(full) > litCount(partial), "Actual reveal must be word-staggered, not instantly complete")
        check(litCount(renderedTitle(10, width: 160)) > 50, "Native text remains visible on narrow layouts")
        for text in ["Не только смотри,\nно и sloosh-ай", "Залипнуть на все выходные?\nЛегко"] {
            let complete = AuthWordRevealPlan(text).duration
            for width in [CGFloat(208), 320] {
                let image = pixels(AuthAnimatedPhrase(phrase: text, elapsed: complete, accent: .green)
                    .font(.system(size: 32, weight: .bold)).multilineTextAlignment(.center), width: width, height: 240)
                check(litCount(image) > 100, "Cyrillic/newlines/brand render with larger text and wrapping")
            }
        }
        let background0 = pixels(AuthCinematicBackdrop(time: 0, accent: .green), width: 200, height: 400)
        let background8 = pixels(AuthCinematicBackdrop(time: 8, accent: .green), width: 200, height: 400)
        check(litCount(background0) > 500, "Background has actual light/depth rather than solid black")
        check(background0 != background8, "Background light changes over time")
        let maxChannel = stride(from: 0, to: background0.count, by: 4).map { max(background0[$0], background0[$0 + 1], background0[$0 + 2]) }.max() ?? 255
        check(maxChannel < 150, "Background remains restrained enough for white hero text")
        print("✓ Auth presentation: \(count) checks passed")
    }
}
