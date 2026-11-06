import Foundation
import CoreText

/// Reserve typographic space for the real LogoText asset, not a font approximation.
/// Keep in sync with the canonical SVG viewBox (covered by the auth tests).
enum AuthInlineBrand {
    static let aspectRatio: CGFloat = 625.0 / 173.0
    static let attachmentKey = NSAttributedString.Key("sloosh.auth.logo")

    /// Input is display-uppercase. Accent the standalone Cyrillic brand token,
    /// including surrounding punctuation, never the similar-sounding «СЛЫШЬ».
    /// Cyrillic lettering is not a Latin-logo attachment.
    static func isAccentWord(_ word: String) -> Bool {
        word.contains("SLOOSH") || word.trimmingCharacters(in: .punctuationCharacters) == "СЛУШ"
    }

    static func suffix(of word: String) -> String? {
        guard word == "SLOOSH" || word == "SLOOSH-АЙ" else { return nil }
        return String(word.dropFirst(6))
    }

    private final class Metrics {
        let height: CGFloat
        let width: CGFloat
        init(height: CGFloat, hasSuffix: Bool) {
            self.height = height
            width = height * aspectRatio + (hasSuffix ? height * 0.045 : 0)
        }
    }

    static func delegate(capHeight: CGFloat, hasSuffix: Bool) -> CTRunDelegate {
        let pointer = Unmanaged.passRetained(Metrics(height: capHeight, hasSuffix: hasSuffix)).toOpaque()
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { pointer in
            Unmanaged<Metrics>.fromOpaque(pointer).release()
        }, getAscent: { pointer in
            Unmanaged<Metrics>.fromOpaque(pointer).takeUnretainedValue().height
        }, getDescent: { _ in 0 }, getWidth: { pointer in
            Unmanaged<Metrics>.fromOpaque(pointer).takeUnretainedValue().width
        })
        return CTRunDelegateCreate(&callbacks, pointer)!
    }

    static func logoRect(in run: CTRun) -> CGRect? {
        let attributes = CTRunGetAttributes(run) as NSDictionary
        guard attributes[attachmentKey.rawValue] as? Bool == true,
              let font = attributes[kCTFontAttributeName] else { return nil }
        var position = CGPoint.zero
        CTRunGetPositions(run, CFRange(location: 0, length: 1), &position)
        let height = CTFontGetCapHeight(font as! CTFont)
        return CGRect(x: position.x, y: position.y, width: height * aspectRatio, height: height)
    }

    static func inkBounds(of line: CTLine) -> CGRect {
        let runs = CTLineGetGlyphRuns(line) as! [CTRun]
        guard runs.contains(where: { logoRect(in: $0) != nil }) else {
            let bounds = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            return bounds.isNull ? .zero : bounds
        }
        // CTLine glyph-path bounds do not include a custom attachment's artwork.
        // Union actual glyph outlines with its exact reserved logo rectangle.
        var bounds = CGRect.null
        for run in runs {
            if let rect = logoRect(in: run) {
                bounds = bounds.union(rect)
                continue
            }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let value = attributes[kCTFontAttributeName] else { continue }
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            var rects = [CGRect](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            _ = CTFontGetBoundingRectsForGlyphs(value as! CTFont, .horizontal, glyphs, &rects, count)
            for index in 0..<count where !rects[index].isEmpty {
                bounds = bounds.union(rects[index].offsetBy(dx: positions[index].x, dy: positions[index].y))
            }
        }
        return bounds.isNull ? .zero : bounds
    }
}
