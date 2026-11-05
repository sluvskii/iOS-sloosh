import SwiftUI
import CoreText

/// The reveal schedule is independent of visual line wrapping and letter case.
struct AuthWordRevealPlan {
    struct Part {
        let text: String
        let wordIndex: Int?
    }
    let parts: [Part]
    let wordCount: Int

    init(_ text: String) {
        var chunks: [String] = []
        var chunk = ""
        var wasWhitespace: Bool?
        for character in text {
            let whitespace = character.isWhitespace
            if let previous = wasWhitespace, previous != whitespace {
                chunks.append(chunk)
                chunk = ""
            }
            chunk.append(character)
            wasWhitespace = whitespace
        }
        if !chunk.isEmpty { chunks.append(chunk) }
        var count = 0
        parts = chunks.map { chunk in
            guard chunk.first?.isWhitespace == false else {
                return Part(text: chunk, wordIndex: nil)
            }
            // A standalone dash belongs to the preceding word, not its own beat.
            if chunk.unicodeScalars.allSatisfy({ CharacterSet.punctuationCharacters.contains($0) }), count > 0 {
                return Part(text: chunk, wordIndex: count - 1)
            }
            defer { count += 1 }
            return Part(text: chunk, wordIndex: count)
        }
        wordCount = count
    }

    static let stagger: Double = 0.18
    static let wordDuration: Double = 0.52
    var duration: Double { wordCount == 0 ? 0 : Double(wordCount - 1) * Self.stagger + Self.wordDuration }

    static func visibility(of index: Int, at elapsed: Double) -> Double {
        let linear = min(1, max(0, (elapsed - Double(index) * stagger) / wordDuration))
        return linear * linear * (3 - 2 * linear)
    }
}

/// CoreText gives us exact glyph positions and bounds. Each word has its own
/// blur/opacity layer, but all row sizes/positions are fixed before reveal starts.
private struct AuthPhraseInkCanvas: View, Animatable {
    let phrase: String
    var elapsed: Double
    let accent: Color
    let scale: CGFloat
    @Environment(\.self) private var environment

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let plan = AuthPhraseLayout.fit(phrase, in: size, scale: scale)
            let resolvedAccent = accent.resolve(in: environment)
            let accentColor = CGColor(colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!,
                                      components: [CGFloat(resolvedAccent.red), CGFloat(resolvedAccent.green),
                                                   CGFloat(resolvedAccent.blue), CGFloat(resolvedAccent.opacity)])!
            var top = max(0, (size.height - plan.inkSize.height) / 2)
            for line in plan.lines {
                let baseline = CGPoint(x: (size.width - line.ink.width) / 2 - line.ink.minX,
                                       y: size.height - top - line.ink.maxY)
                for run in CTLineGetGlyphRuns(line.shaped) as! [CTRun] {
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    guard let index = attributes[AuthPhraseLayout.wordIndexKey.rawValue] as? Int else { continue }
                    let visibility = AuthWordRevealPlan.visibility(of: index, at: elapsed)
                    guard visibility > 0 else { continue }
                    var wordContext = context
                    wordContext.opacity *= visibility
                    wordContext.translateBy(x: 0, y: (1 - visibility) * 5)
                    if visibility < 1 { wordContext.addFilter(.blur(radius: (1 - visibility) * 7)) }
                    let usesAccent = attributes[AuthPhraseLayout.accentKey.rawValue] as? Bool == true
                    wordContext.withCGContext { cg in
                        cg.translateBy(x: 0, y: size.height)
                        cg.scaleBy(x: 1, y: -1)
                        cg.textMatrix = .identity
                        cg.textPosition = baseline
                        cg.setFillColor(usesAccent ? accentColor : CGColor(gray: 1, alpha: 0.92))
                        CTRunDraw(run, cg, CFRange(location: 0, length: 0))
                    }
                }
                top += line.ink.height + plan.lineGap
            }
        }
    }
}

struct AuthAnimatedPhrase: View {
    let phrase: String
    let elapsed: Double
    let accent: Color
    var scale: CGFloat = 1

    var body: some View {
        AuthPhraseInkCanvas(phrase: phrase, elapsed: elapsed, accent: accent, scale: scale)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(phrase)
    }
}
