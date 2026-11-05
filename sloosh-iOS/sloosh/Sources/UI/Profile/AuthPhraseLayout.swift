import Foundation
import CoreText

/// Editorial block lettering: every row has the same INK width, not the same
/// point size. Font line-box padding never participates in optical spacing.
enum AuthPhraseTypography {
    static let baseSize: CGFloat = 28
    static let trackingEm: CGFloat = -0.018
    static let wordSpaceEm: CGFloat = 0.16
    static let margin: CGFloat = 14
}

struct AuthPhraseLayout {
    struct Line {
        let text: String
        let pointSize: CGFloat
        let shaped: CTLine
        let ink: CGRect
    }
    static let wordIndexKey = NSAttributedString.Key("sloosh.auth.wordIndex")
    static let accentKey = NSAttributedString.Key("sloosh.auth.accent")
    let lines: [Line]
    let inkSize: CGSize
    let lineGap: CGFloat

    private final class Cached {
        let plan: AuthPhraseLayout
        init(_ plan: AuthPhraseLayout) { self.plan = plan }
    }
    private static let cache: NSCache<NSString, Cached> = {
        let cache = NSCache<NSString, Cached>()
        cache.countLimit = 128
        return cache
    }()

    static func heroHeight(availableHeight: CGFloat, scale: CGFloat) -> CGFloat {
        guard availableHeight.isFinite, availableHeight > 0, scale.isFinite, scale > 0 else { return 0 }
        return min(availableHeight * 0.4, max(116, availableHeight * 0.29 * sqrt(scale)))
    }

    static func fit(_ phrase: String, in area: CGSize, scale: CGFloat = 1) -> Self {
        let empty = Self(lines: [], inkSize: .zero, lineGap: 0)
        guard area.width.isFinite, area.height.isFinite, scale.isFinite, scale > 0,
              area.width > 2 * AuthPhraseTypography.margin, area.height > 2 * AuthPhraseTypography.margin else { return empty }
        let text = CatalogFallbackTitleStyle.displayTitle(String(phrase.prefix(512)))
        let paragraphs = text.split(whereSeparator: { $0.isNewline })
            .map { $0.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
            .filter { !$0.isEmpty }
        guard !paragraphs.isEmpty else { return empty }
        let key = "\(text)|\(area.width)|\(area.height)|\(scale)" as NSString
        if let cached = cache.object(forKey: key) { return cached.plan }
        let width = area.width - 2 * AuthPhraseTypography.margin
        let height = area.height - 2 * AuthPhraseTypography.margin
        // Global tags survive both manual line breaks and adaptive word wrapping.
        let words = AuthWordRevealPlan(text).parts.filter { $0.wordIndex != nil }

        func shape(_ string: String, size: CGFloat, tags: [AuthWordRevealPlan.Part] = []) -> Line {
            let font = CTFontCreateWithName(CatalogFallbackTitleStyle.postScriptName as CFString, size, nil)
            let base: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTKernAttributeName as String): size * AuthPhraseTypography.trackingEm,
                NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
            ]
            let attributed = NSMutableAttributedString(string: "")
            var space: UniChar = 32, glyph: CGGlyph = 0
            _ = CTFontGetGlyphsForCharacters(font, &space, &glyph, 1)
            var advance = CGSize.zero
            _ = CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
            let parts = string.split(separator: " ")
            for (index, word) in parts.enumerated() {
                if index > 0 {
                    var spacing = base
                    spacing[NSAttributedString.Key(kCTKernAttributeName as String)] = size * AuthPhraseTypography.wordSpaceEm - advance.width
                    attributed.append(NSAttributedString(string: " ", attributes: spacing))
                }
                var attributes = base
                if index < tags.count, let wordIndex = tags[index].wordIndex {
                    attributes[wordIndexKey] = wordIndex
                    attributes[accentKey] = word.contains("SLOOSH")
                }
                if let suffix = AuthInlineBrand.suffix(of: String(word)) {
                    var attachment = attributes
                    attachment[AuthInlineBrand.attachmentKey] = true
                    attachment[NSAttributedString.Key(kCTRunDelegateAttributeName as String)] = AuthInlineBrand.delegate(
                        capHeight: CTFontGetCapHeight(font), hasSuffix: !suffix.isEmpty
                    )
                    attributed.append(NSAttributedString(string: "\u{FFFC}", attributes: attachment))
                    attributed.append(NSAttributedString(string: suffix, attributes: attributes))
                } else {
                    attributed.append(NSAttributedString(string: String(word), attributes: attributes))
                }
            }
            let shaped = CTLineCreateWithAttributedString(attributed)
            let ink = AuthInlineBrand.inkBounds(of: shaped)
            return Line(text: string, pointSize: size, shaped: shaped, ink: ink.isNull ? .zero : ink)
        }

        func plan(_ rows: [String]) -> Self {
            var offset = 0
            // Fit each row separately to a common width. Never stretch glyphs.
            var lines = rows.map { row -> Line in
                let count = row.split(separator: " ").count
                let tags = Array(words[offset..<(offset + count)])
                offset += count
                let sample = shape(row, size: 100, tags: tags)
                var line = shape(row, size: 100 * width / max(sample.ink.width, 1), tags: tags)
                for _ in 0..<2 {
                    line = shape(row, size: line.pointSize * width / max(line.ink.width, 1), tags: tags)
                }
                return line
            }
            var gap = rows.count > 1 ? width * 0.016 : 0
            var inkHeight = lines.reduce(0) { $0 + $1.ink.height } + gap * CGFloat(max(0, rows.count - 1))
            // If height is tight, shrink the whole block uniformly so row widths
            // stay equal and nothing collides with the logo, button or error UI.
            if inkHeight > height {
                let factor = height / inkHeight
                offset = 0
                lines = lines.map { line in
                    let count = line.text.split(separator: " ").count
                    let tags = Array(words[offset..<(offset + count)])
                    offset += count
                    return shape(line.text, size: line.pointSize * factor, tags: tags)
                }
                gap *= factor
                inkHeight = lines.reduce(0) { $0 + $1.ink.height } + gap * CGFloat(max(0, rows.count - 1))
            }
            return Self(lines: lines, inkSize: CGSize(width: lines.map(\.ink.width).max() ?? 0, height: inkHeight), lineGap: gap)
        }
        var best = plan(paragraphs)
        let minimum = AuthPhraseTypography.baseSize * scale
        if (best.lines.map(\.pointSize).min() ?? 0) < minimum {
            // Narrow phones / larger Dynamic Type: prefer another natural line
            // over shrinking a long sentence to unreadable lettering.
            var wrapped: [String] = []
            for paragraph in paragraphs {
                var row = ""
                for word in paragraph.split(separator: " ") {
                    let candidate = row.isEmpty ? String(word) : row + " " + word
                    if !row.isEmpty, shape(candidate, size: minimum).ink.width > width {
                        wrapped.append(row)
                        row = String(word)
                    } else { row = candidate }
                }
                if !row.isEmpty { wrapped.append(row) }
            }
            if wrapped != paragraphs {
                let alternative = plan(wrapped)
                if (alternative.lines.map(\.pointSize).min() ?? 0) > (best.lines.map(\.pointSize).min() ?? 0) * 1.08 {
                    best = alternative
                }
            }
        }
        cache.setObject(Cached(best), forKey: key)
        return best
    }
}
