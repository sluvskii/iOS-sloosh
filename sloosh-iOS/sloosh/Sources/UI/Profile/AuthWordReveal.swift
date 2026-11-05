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
enum AuthPhraseInkRole { case neutral, brand }

struct AuthPhraseInkCanvas: View, Animatable {
    let phrase: String
    var elapsed: Double
    let accent: Color
    let scale: CGFloat
    let role: AuthPhraseInkRole
    let logoBundle: Bundle
    @Environment(\.self) private var environment

    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    var body: some View {
        Canvas { context, size in
            let plan = AuthPhraseLayout.fit(phrase, in: size, scale: scale)
            // Color.Resolved.red/green/blue are sRGB components, not linear ones.
            // Let SwiftUI supply the correctly tagged CGColor instead of re-encoding.
            let accentColor = accent.resolve(in: environment).cgColor
            let logo = context.resolve(Image("LogoText", bundle: logoBundle).renderingMode(.template))
            var top = max(0, (size.height - plan.inkSize.height) / 2)
            for line in plan.lines {
                let baseline = CGPoint(x: (size.width - line.ink.width) / 2 - line.ink.minX,
                                       y: size.height - top - line.ink.maxY)
                for run in CTLineGetGlyphRuns(line.shaped) as! [CTRun] {
                    let attributes = CTRunGetAttributes(run) as NSDictionary
                    guard let index = attributes[AuthPhraseLayout.wordIndexKey.rawValue] as? Int else { continue }
                    let usesAccent = attributes[AuthPhraseLayout.accentKey.rawValue] as? Bool == true
                    guard usesAccent == (role == .brand) else { continue }
                    let visibility = AuthWordRevealPlan.visibility(of: index, at: elapsed)
                    guard visibility > 0 else { continue }
                    var wordContext = context
                    wordContext.opacity *= visibility
                    wordContext.translateBy(x: 0, y: (1 - visibility) * 5)
                    if visibility < 1 { wordContext.addFilter(.blur(radius: (1 - visibility) * 7)) }
                    if let rect = AuthInlineBrand.logoRect(in: run) {
                        let destination = CGRect(x: baseline.x + rect.minX,
                                                 y: size.height - baseline.y - rect.maxY,
                                                 width: rect.width, height: rect.height)
                        // Explicit alpha-mask tint: resolved template SVGs can render
                        // white despite ResolvedImage.shading. Tint inside the layer;
                        // apply the word's reveal opacity/blur to its complete result.
                        wordContext.drawLayer { tinted in
                            tinted.draw(logo, in: destination)
                            tinted.blendMode = .sourceIn
                            tinted.fill(Path(destination), with: .color(accent))
                        }
                        continue
                    }
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
    var logoBundle: Bundle = .main
    var phraseOpacity: Double = 1
    var phraseBlur: CGFloat = 0

    var body: some View {
        ZStack {
            AuthPhraseInkCanvas(phrase: phrase, elapsed: elapsed, accent: accent, scale: scale,
                                role: .neutral, logoBundle: logoBundle)
                .opacity(phraseOpacity)
                .blur(radius: phraseBlur)
                .modifier(AuthPhraseForeground())
            AuthPhraseInkCanvas(phrase: phrase, elapsed: elapsed, accent: accent, scale: scale,
                                role: .brand, logoBundle: logoBundle)
                .opacity(phraseOpacity)
                .blur(radius: phraseBlur)
                .blendMode(.normal)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phrase)
    }
}

/// Blend neutral hero ink only. The brand logo/suffix is a separate normal-blend
/// sibling so additive backdrop light cannot turn the accent yellow.
struct AuthPhraseForeground: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let appearance = BackdropForegroundAppearance(
            isDark: true, increasedContrast: contrast == .increased,
            reduceTransparency: reduceTransparency, opacity: 1
        )
        content.blendMode(appearance.blendMode)
    }
}
