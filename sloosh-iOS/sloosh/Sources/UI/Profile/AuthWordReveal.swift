import SwiftUI

/// Preserve native Text wrapping, spaces and explicit line breaks. Only the ink
/// is animated; word positions never move as more of the phrase is revealed.
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

private struct AuthWordIndex: TextAttribute {
    let value: Int
}

private struct AuthWordRevealRenderer: TextRenderer {
    var elapsed: Double
    var animatableData: Double {
        get { elapsed }
        set { elapsed = newValue }
    }

    var displayPadding: EdgeInsets { EdgeInsets(top: 8, leading: 8, bottom: 13, trailing: 8) }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                guard let word = run[AuthWordIndex.self] else {
                    context.draw(run)
                    continue
                }
                let visibility = AuthWordRevealPlan.visibility(of: word.value, at: elapsed)
                guard visibility > 0 else { continue }
                var wordContext = context
                wordContext.opacity *= visibility
                wordContext.translateBy(x: 0, y: (1 - visibility) * 5)
                if visibility < 1 {
                    wordContext.addFilter(.blur(radius: (1 - visibility) * 7))
                }
                wordContext.draw(run, options: .disablesSubpixelQuantization)
            }
        }
    }
}

struct AuthAnimatedPhrase: View {
    let phrase: String
    let elapsed: Double
    let accent: Color

    private var text: Text {
        AuthWordRevealPlan(phrase).parts.reduce(Text("")) { result, part in
            guard let index = part.wordIndex else { return result + Text(part.text) }
            let color = part.text.localizedCaseInsensitiveContains("sloosh") ? accent : Color.white.opacity(0.92)
            return result + Text(part.text)
                .foregroundColor(color)
                .customAttribute(AuthWordIndex(value: index))
        }
    }

    var body: some View {
        text
            .textRenderer(AuthWordRevealRenderer(elapsed: elapsed))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(phrase)
    }
}
